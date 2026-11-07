import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/identity.{
  type DefinitionRef, Ref, hash_bytes, parse_ref_hex, ref_hex,
}
import gleamunison/namespace_codec
import gleamunison/storage.{type StorageAdapter}

/// The name layer as data. A namespace maps names to definition refs;
/// namespaces are stored content-addressed, branches are named pointers to
/// namespace heads with a causal history chain. The branch pointer cell is
/// the ONLY mutable datum here: namespaces and head chunks are immutable CAS.
pub type Namespace {
  Namespace(bindings: Dict(String, DefinitionRef))
}

pub type Diff {
  Diff(added: List(String), removed: List(String), changed: List(String))
}

pub fn empty() -> Namespace {
  Namespace(dict.new())
}

pub fn set(ns: Namespace, name: String, ref: DefinitionRef) -> Namespace {
  Namespace(dict.insert(ns.bindings, name, ref))
}

pub fn get(ns: Namespace, name: String) -> Result(DefinitionRef, Nil) {
  dict.get(ns.bindings, name)
}

/// Whether this selected namespace binds a content ref under any name.
pub fn binds(ns: Namespace, ref: DefinitionRef) -> Bool {
  dict.values(ns.bindings) |> list.any(fn(bound) { bound == ref })
}

/// Every name bound to this content ref, in the sorted order `names/1` uses.
pub fn names_for_ref(ns: Namespace, ref: DefinitionRef) -> List(String) {
  names(ns)
  |> list.filter(fn(name) { get(ns, name) == Ok(ref) })
}

pub fn remove(ns: Namespace, name: String) -> Namespace {
  Namespace(dict.delete(ns.bindings, name))
}

pub fn names(ns: Namespace) -> List(String) {
  dict.keys(ns.bindings) |> list.sort(string.compare)
}

pub fn save(
  adapter: StorageAdapter,
  ns: Namespace,
) -> Result(DefinitionRef, String) {
  let bytes = namespace_codec.serialize_bindings(ns.bindings)
  let ref = Ref(hash_bytes(bytes))
  adapter.insert(ref, bytes)
  |> result.map(fn(_) { ref })
  |> result.map_error(storage.describe_error)
}

pub fn load(
  adapter: StorageAdapter,
  ref: DefinitionRef,
) -> Result(Namespace, String) {
  case adapter.lookup(ref) {
    Ok(Some(bytes)) ->
      case Ref(hash_bytes(bytes)) == ref {
        True ->
          namespace_codec.parse_bindings(bytes)
          |> result.map(Namespace)
          |> result.replace_error("corrupt namespace chunk")
        False -> Error("namespace integrity failure")
      }
    Ok(None) -> Error("namespace not found")
    Error(error) -> Error(storage.describe_error(error))
  }
}

// --- Branches: mutable pointer cell + immutable history chain ----------------

pub fn branch_pointer_ref(branch: String) -> DefinitionRef {
  Ref(hash_bytes(bit_array.from_string("branchptr:" <> branch)))
}

/// Current head of a branch: #(sequence number, namespace ref).
pub fn branch_head(
  adapter: StorageAdapter,
  branch: String,
) -> Result(#(Int, DefinitionRef), String) {
  use prior <- result.try(read_head(adapter, branch))
  case prior {
    Some(#(seq, ns_ref, _)) -> Ok(#(seq, ns_ref))
    None -> Error("no such branch: " <> branch)
  }
}

/// The branch a pointer chunk names: the embedded name and the name-derived
/// key must agree, so a stray chunk cannot invent a branch.
pub fn branch_name_of(ref: DefinitionRef, bytes: BitArray) -> Option(String) {
  case namespace_codec.parse_head(bytes) {
    Ok(#(branch, seq, _, _)) if seq > 0 ->
      case branch_pointer_ref(branch) == ref {
        True -> Some(branch)
        False -> None
      }
    _ -> None
  }
}

/// A mutable pointer has a name-derived key, not a content hash. Safety scans
/// can skip it only when both its embedded branch and pointer key agree —
/// the same rule that names the branch, so the two cannot disagree.
pub fn is_branch_pointer(ref: DefinitionRef, bytes: BitArray) -> Bool {
  option.is_some(branch_name_of(ref, bytes))
}

/// Point branch at ns (stored if needed), recording the causal link to the
/// previous head. Returns the new head's content ref.
pub fn commit(
  adapter: StorageAdapter,
  branch: String,
  ns: Namespace,
) -> Result(DefinitionRef, String) {
  // Read/validate first: a failed or corrupt head is not a new branch.
  use prior <- result.try(read_head(adapter, branch))
  let #(seq, prev) = case prior {
    Some(#(n, _, head)) -> #(n + 1, Some(head))
    None -> #(1, None)
  }
  use ns_ref <- result.try(save(adapter, ns))
  let head_bytes = namespace_codec.serialize_head(branch, seq, ns_ref, prev)
  let head_ref = Ref(hash_bytes(head_bytes))
  use _ <- result.try(
    adapter.insert(head_ref, head_bytes)
    |> result.map_error(storage.describe_error),
  )
  // The branch pointer cell is overwritten (the one mutable datum).
  use _ <- result.try(
    adapter.insert(branch_pointer_ref(branch), head_bytes)
    |> result.map_error(storage.describe_error),
  )
  Ok(head_ref)
}

fn read_head(
  adapter: StorageAdapter,
  branch: String,
) -> Result(Option(#(Int, DefinitionRef, DefinitionRef)), String) {
  case adapter.lookup(branch_pointer_ref(branch)) {
    Ok(Some(bytes)) ->
      case namespace_codec.parse_head(bytes) {
        Ok(#(name, seq, ns_ref, _)) if name == branch && seq > 0 ->
          Ok(Some(#(seq, ns_ref, Ref(hash_bytes(bytes)))))
        _ -> Error("corrupt branch head or branch identity mismatch")
      }
    Ok(None) -> Ok(None)
    Error(error) -> Error(storage.describe_error(error))
  }
}

/// Only a genuinely missing pointer is an empty namespace. Read errors and
/// corrupt/dangling heads must refuse safety decisions and mutations.
pub fn load_current_or_empty(
  adapter: StorageAdapter,
  branch: String,
) -> Result(Namespace, String) {
  use prior <- result.try(read_head(adapter, branch))
  case prior {
    None -> Ok(empty())
    Some(#(_, ns_ref, _)) -> load(adapter, ns_ref)
  }
}

/// Load the namespace a branch currently points at.
pub fn load_current(
  adapter: StorageAdapter,
  branch: String,
) -> Result(Namespace, String) {
  use #(_, ns_ref) <- result.try(branch_head(adapter, branch))
  load(adapter, ns_ref)
}

/// Walk the head chain newest-first: #(seq, namespace ref) entries.
/// Only a genuinely missing pointer is an empty history; a corrupt head or
/// a store failure is an error, never a silent empty list.
pub fn history(
  adapter: StorageAdapter,
  branch: String,
) -> Result(List(#(Int, DefinitionRef)), String) {
  case adapter.lookup(branch_pointer_ref(branch)) {
    Error(error) -> Error(storage.describe_error(error))
    Ok(None) -> Ok([])
    Ok(Some(bytes)) ->
      case namespace_codec.parse_head(bytes) {
        Ok(#(name, seq, _ns_ref, _)) if name == branch && seq > 0 -> {
          use chain <- result.try(walk_head_chain(adapter, bytes, []))
          Ok(
            list.reverse(chain)
            |> list.map(fn(h) {
              let #(_, cseq, cns, _, _) = h
              #(cseq, cns)
            }),
          )
        }
        _ -> Error("corrupt branch head or branch identity mismatch")
      }
  }
}

// --- Diff & merge -------------------------------------------------------------

pub fn diff(before: Namespace, after: Namespace) -> Diff {
  let before_names = names(before)
  let after_names = names(after)
  let added =
    list.filter(after_names, fn(n) { !list.contains(before_names, n) })
  let removed =
    list.filter(before_names, fn(n) { !list.contains(after_names, n) })
  let changed =
    list.filter(after_names, fn(n) {
      case get(before, n), get(after, n) {
        Ok(a), Ok(b) -> a != b
        _, _ -> False
      }
    })
  Diff(added:, removed:, changed:)
}

/// Union of two namespaces. Conflict when the same name maps to different
/// refs on each side; agreeing bindings merge clean.
pub fn merge(a: Namespace, b: Namespace) -> Result(Namespace, List(String)) {
  let conflicts =
    list.filter(names(a), fn(n) {
      case get(a, n), get(b, n) {
        Ok(ra), Ok(rb) -> ra != rb
        _, _ -> False
      }
    })
  case conflicts {
    [] -> Ok(Namespace(dict.merge(a.bindings, b.bindings)))
    _ -> Error(conflicts)
  }
}

// ── Sync: branches as transferable chunk sets ───────────────────────────────
// A branch is three kinds of data: the mutable pointer cell (keyed by a
// name-derived ref, not content), the immutable head chain, and the
// namespace snapshots. Export walks all three; import verifies content
// chunks by hash and the pointer chunk by parsing. The pointer ref is
// derivable from the branch name alone — a remote peer can request it
// without negotiation.

/// Every chunk a branch needs to travel: content chunks first (ns snapshots
/// and head chain, each verified by content hash), the pointer cell last
/// (verified by parsing — its ref is name-derived, not content-derived).
pub fn export_branch(
  adapter: StorageAdapter,
  branch: String,
) -> Result(List(#(String, BitArray)), String) {
  let ptr_ref = branch_pointer_ref(branch)
  case adapter.lookup(ptr_ref) {
    Ok(Some(head_bytes)) -> {
      use heads <- result.try(walk_head_chain(adapter, head_bytes, []))
      let ns_refs =
        list.filter_map(heads, fn(h) {
          let #(_, _, ns_ref, _, _) = h
          Ok(ns_ref)
        })
        |> list.unique
      use ns_chunks <- result.try(
        list.try_map(ns_refs, fn(r) { fetch_chunk(adapter, r) }),
      )
      let head_chunks =
        list.map(heads, fn(h) {
          let #(_, _, _, _, bytes) = h
          #("chunk:" <> ref_hex(Ref(hash_bytes(bytes))), bytes)
        })
      let ns_entries =
        list.map(ns_chunks, fn(pair) { #("chunk:" <> pair.0, pair.1) })
      Ok(
        list.flatten([
          ns_entries,
          head_chunks,
          [#("pointer:" <> branch, head_bytes)],
        ]),
      )
    }
    Ok(None) -> Error("no such branch: " <> branch)
    Error(error) -> Error(storage.describe_error(error))
  }
}

fn walk_head_chain(
  adapter: StorageAdapter,
  head_bytes: BitArray,
  acc: List(#(String, Int, DefinitionRef, Option(DefinitionRef), BitArray)),
) -> Result(
  List(#(String, Int, DefinitionRef, Option(DefinitionRef), BitArray)),
  String,
) {
  case namespace_codec.parse_head(head_bytes) {
    Error(_) -> Error("corrupt head chunk")
    Ok(#(b, seq, ns_ref, prev)) -> {
      let next = [#(b, seq, ns_ref, prev, head_bytes), ..acc]
      case prev {
        None -> Ok(next)
        Some(prev_ref) ->
          case adapter.lookup(prev_ref) {
            Ok(Some(prev_bytes)) -> walk_head_chain(adapter, prev_bytes, next)
            Ok(None) -> Error("missing head chunk in chain")
            Error(error) -> Error(storage.describe_error(error))
          }
      }
    }
  }
}

fn fetch_chunk(
  adapter: StorageAdapter,
  ref: DefinitionRef,
) -> Result(#(String, BitArray), String) {
  case adapter.lookup(ref) {
    Ok(Some(bytes)) -> Ok(#(ref_hex(ref), bytes))
    Ok(None) -> Error("missing chunk: " <> ref_hex(ref))
    Error(error) -> Error(storage.describe_error(error))
  }
}

/// Import a branch chunk set. Content chunks are verified against their
/// hash before insert; the pointer must match its embedded branch. Validate
/// the whole set, then write immutable chunks and publish ONE pointer last.
/// Failed content writes may leave immutable, retry-safe orphan chunks;
/// they never publish a partially imported branch. No cross-store transaction.
pub fn import_branch(
  adapter: StorageAdapter,
  chunks: List(#(String, BitArray)),
) -> Result(Nil, String) {
  use Nil <- result.try(
    list.try_map(chunks, fn(pair) { verify_chunk(pair) })
    |> result.map(fn(_) { Nil }),
  )
  let pointers =
    list.filter(chunks, fn(p) { string.starts_with(p.0, "pointer:") })
  use _ <- result.try(case list.length(pointers) <= 1 {
    True -> Ok(Nil)
    False -> Error("import accepts one branch pointer at a time")
  })
  let content =
    list.filter(chunks, fn(p) { !string.starts_with(p.0, "pointer:") })
  list.fold(list.append(content, pointers), Ok(Nil), fn(acc, pair) {
    case acc {
      Error(e) -> Error(e)
      Ok(_) -> {
        let #(key, bytes) = pair
        use ref <- result.try(case string.starts_with(key, "pointer:") {
          True -> Ok(branch_pointer_ref(string.drop_start(key, 8)))
          False -> parse_ref_hex(string.drop_start(key, 6))
        })
        adapter.insert(ref, bytes)
        |> result.map_error(storage.describe_error)
      }
    }
  })
}

fn verify_chunk(pair: #(String, BitArray)) -> Result(Nil, String) {
  let #(key, bytes) = pair
  case string.starts_with(key, "pointer:") {
    True -> {
      let branch = string.drop_start(key, 8)
      case namespace_codec.parse_head(bytes) {
        Ok(#(name, seq, _, _)) if name == branch && seq > 0 -> Ok(Nil)
        _ -> Error("pointer branch identity mismatch or invalid head")
      }
    }
    False -> {
      let expected = string.drop_start(key, 6)
      case
        string.starts_with(key, "chunk:")
        && ref_hex(Ref(hash_bytes(bytes))) == expected
      {
        True -> Ok(Nil)
        False -> Error("chunk hash mismatch: " <> expected)
      }
    }
  }
}

/// The pointer ref as hex: the id a peer requests to start a branch pull.
pub fn pointer_ref_hex(branch: String) -> String {
  ref_hex(branch_pointer_ref(branch))
}

/// Parse a head chunk into the refs it points at: its namespace snapshot
/// and its predecessor (hex), so a puller can keep walking. The chunk's
/// own content key is included for the import set.
pub fn parse_head_hexes(
  bytes: BitArray,
) -> Result(#(String, String, Option(String)), String) {
  case namespace_codec.parse_head(bytes) {
    Error(_) -> Error("corrupt head chunk")
    Ok(#(_, _, ns_ref, prev)) -> {
      let self_hex = ref_hex(Ref(hash_bytes(bytes)))
      let prev_hex = case prev {
        Some(r) -> Some(ref_hex(r))
        None -> None
      }
      Ok(#(self_hex, ref_hex(ns_ref), prev_hex))
    }
  }
}
