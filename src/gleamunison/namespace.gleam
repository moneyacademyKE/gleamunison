import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/identity.{
  type DefinitionRef, Ref, hash_bytes, hash_to_debug_string, parse_ref_hex,
}
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

pub fn remove(ns: Namespace, name: String) -> Namespace {
  Namespace(dict.delete(ns.bindings, name))
}

pub fn names(ns: Namespace) -> List(String) {
  dict.keys(ns.bindings) |> list.sort(string.compare)
}

// --- Canonical serialization ------------------------------------------------

fn b64(s: String) -> String {
  bit_array.base64_encode(bit_array.from_string(s), True)
}

fn unb64(s: String) -> Result(String, Nil) {
  use bits <- result.try(bit_array.base64_decode(s))
  bit_array.to_string(bits)
}

fn ref_hex(r: DefinitionRef) -> String {
  let Ref(h) = r
  hash_to_debug_string(h)
}

fn hex_ref(s: String) -> Result(DefinitionRef, Nil) {
  parse_ref_hex(s) |> result.replace_error(Nil)
}

fn serialize_ns(ns: Namespace) -> BitArray {
  let lines =
    dict.to_list(ns.bindings)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(kv) { b64(kv.0) <> ":" <> ref_hex(kv.1) })
  bit_array.from_string(string.join(["ns", "1", ..lines], "\n"))
}

fn parse_ns(bytes: BitArray) -> Result(Namespace, Nil) {
  use text <- result.try(bit_array.to_string(bytes))
  case string.split(text, "\n") {
    ["ns", "1", ..lines] -> {
      use pairs <- result.try(
        list.try_fold(lines, [], fn(acc, line) {
          case string.split(line, ":") {
            [name_b64, hex] -> {
              use name <- result.try(unb64(name_b64))
              use ref <- result.try(hex_ref(hex))
              Ok([#(name, ref), ..acc])
            }
            _ -> Error(Nil)
          }
        }),
      )
      Ok(Namespace(dict.from_list(pairs)))
    }
    _ -> Error(Nil)
  }
}

pub fn save(
  adapter: StorageAdapter,
  ns: Namespace,
) -> Result(DefinitionRef, String) {
  let bytes = serialize_ns(ns)
  let ref = Ref(hash_bytes(bytes))
  adapter.insert(ref, bytes)
  |> result.map(fn(_) { ref })
  |> result.map_error(fn(_) { "store insert failed" })
}

pub fn load(
  adapter: StorageAdapter,
  ref: DefinitionRef,
) -> Result(Namespace, String) {
  case adapter.lookup(ref) {
    Ok(Some(bytes)) ->
      parse_ns(bytes) |> result.replace_error("corrupt namespace chunk")
    Ok(None) -> Error("namespace not found")
    Error(_) -> Error("store lookup failed")
  }
}

// --- Branches: mutable pointer cell + immutable history chain ----------------

pub fn branch_pointer_ref(branch: String) -> DefinitionRef {
  Ref(hash_bytes(bit_array.from_string("branchptr:" <> branch)))
}

fn serialize_head(
  branch: String,
  seq: Int,
  ns_ref: DefinitionRef,
  prev: Option(DefinitionRef),
) -> BitArray {
  let prev_hex = case prev {
    Some(r) -> ref_hex(r)
    None -> "-"
  }
  bit_array.from_string(string.join(
    ["head", "1", b64(branch), int.to_string(seq), ref_hex(ns_ref), prev_hex],
    ":",
  ))
}

fn parse_head(
  bytes: BitArray,
) -> Result(#(String, Int, DefinitionRef, Option(DefinitionRef)), Nil) {
  use text <- result.try(bit_array.to_string(bytes))
  case string.split(text, ":") {
    ["head", "1", branch_b64, seq_s, ns_hex, prev_hex] -> {
      use branch <- result.try(unb64(branch_b64))
      use seq <- result.try(int.parse(seq_s) |> result.replace_error(Nil))
      use ns_ref <- result.try(hex_ref(ns_hex))
      use prev <- result.try(case prev_hex {
        "-" -> Ok(None)
        hex -> hex_ref(hex) |> result.map(Some)
      })
      Ok(#(branch, seq, ns_ref, prev))
    }
    _ -> Error(Nil)
  }
}

/// Current head of a branch: #(sequence number, namespace ref).
pub fn branch_head(
  adapter: StorageAdapter,
  branch: String,
) -> Result(#(Int, DefinitionRef), String) {
  case adapter.lookup(branch_pointer_ref(branch)) {
    Ok(Some(bytes)) ->
      case parse_head(bytes) {
        Ok(#(_, seq, ns_ref, _)) -> Ok(#(seq, ns_ref))
        Error(_) -> Error("corrupt branch head")
      }
    Ok(None) -> Error("no such branch: " <> branch)
    Error(_) -> Error("store lookup failed")
  }
}

/// Point branch at ns (stored if needed), recording the causal link to the
/// previous head. Returns the new head's content ref.
pub fn commit(
  adapter: StorageAdapter,
  branch: String,
  ns: Namespace,
) -> Result(DefinitionRef, String) {
  use ns_ref <- result.try(save(adapter, ns))
  let #(seq, prev) = case branch_head(adapter, branch) {
    Ok(#(n, _)) -> #(n + 1, head_chunk_ref(adapter, branch))
    Error(_) -> #(1, None)
  }
  let head_bytes = serialize_head(branch, seq, ns_ref, prev)
  let head_ref = Ref(hash_bytes(head_bytes))
  use _ <- result.try(
    adapter.insert(head_ref, head_bytes)
    |> result.map_error(fn(_) { "store insert failed" }),
  )
  // The branch pointer cell is overwritten (the one mutable datum).
  use _ <- result.try(
    adapter.insert(branch_pointer_ref(branch), head_bytes)
    |> result.map_error(fn(_) { "store insert failed" }),
  )
  Ok(head_ref)
}

fn head_chunk_ref(
  adapter: StorageAdapter,
  branch: String,
) -> Option(DefinitionRef) {
  case adapter.lookup(branch_pointer_ref(branch)) {
    Ok(Some(bytes)) -> Some(Ref(hash_bytes(bytes)))
    _ -> None
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
pub fn history(
  adapter: StorageAdapter,
  branch: String,
) -> List(#(Int, DefinitionRef)) {
  case branch_head(adapter, branch) {
    Error(_) -> []
    Ok(#(seq, ns_ref)) ->
      walk(adapter, branch_pointer_ref(branch), [#(seq, ns_ref)])
      |> list.reverse
  }
}

fn walk(
  adapter: StorageAdapter,
  ptr: DefinitionRef,
  acc: List(#(Int, DefinitionRef)),
) -> List(#(Int, DefinitionRef)) {
  case adapter.lookup(ptr) {
    Ok(Some(bytes)) ->
      case parse_head(bytes) {
        Ok(#(_, _, _, Some(prev_head_ref))) ->
          case adapter.lookup(prev_head_ref) {
            Ok(Some(prev_bytes)) ->
              case parse_head(prev_bytes) {
                Ok(#(_, pseq, pns, _)) ->
                  walk(adapter, prev_head_ref, [#(pseq, pns), ..acc])
                Error(_) -> acc
              }
            _ -> acc
          }
        _ -> acc
      }
    _ -> acc
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
    Error(_) -> Error("store lookup failed")
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
  case parse_head(head_bytes) {
    Error(_) -> Error("corrupt head chunk")
    Ok(#(b, seq, ns_ref, prev)) -> {
      let next = [#(b, seq, ns_ref, prev, head_bytes), ..acc]
      case prev {
        None -> Ok(next)
        Some(prev_ref) ->
          case adapter.lookup(prev_ref) {
            Ok(Some(prev_bytes)) -> walk_head_chain(adapter, prev_bytes, next)
            Ok(None) -> Error("missing head chunk in chain")
            Error(_) -> Error("store lookup failed")
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
    Error(_) -> Error("store lookup failed")
  }
}

/// Import a branch chunk set. Content chunks are verified against their
/// hash before insert; the pointer chunk must parse as a head. A tampered
/// chunk is refused — nothing partial lands.
pub fn import_branch(
  adapter: StorageAdapter,
  chunks: List(#(String, BitArray)),
) -> Result(Nil, String) {
  use Nil <- result.try(
    list.try_map(chunks, fn(pair) { verify_chunk(pair) })
    |> result.map(fn(_) { Nil }),
  )
  list.fold(chunks, Ok(Nil), fn(acc, pair) {
    case acc {
      Error(e) -> Error(e)
      Ok(_) -> {
        let #(key, bytes) = pair
        use ref <- result.try(case string.starts_with(key, "pointer:") {
          True -> Ok(branch_pointer_ref(string.drop_start(key, 8)))
          False -> parse_ref_hex(string.drop_start(key, 6))
        })
        adapter.insert(ref, bytes)
        |> result.map_error(fn(_) { "store insert failed" })
      }
    }
  })
}

fn verify_chunk(pair: #(String, BitArray)) -> Result(Nil, String) {
  let #(key, bytes) = pair
  case string.starts_with(key, "pointer:") {
    True ->
      case parse_head(bytes) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error("pointer chunk does not parse as a head")
      }
    False -> {
      let expected = string.drop_start(key, 6)
      case ref_hex(Ref(hash_bytes(bytes))) == expected {
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
  case parse_head(bytes) {
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
