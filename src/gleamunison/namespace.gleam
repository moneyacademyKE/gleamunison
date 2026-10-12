import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamunison/identity.{
  type DefinitionRef, Ref, hash_bytes, hash_from_bytes, hash_to_debug_string,
  hex_to_bytes,
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

fn hex_ref(s: String) -> DefinitionRef {
  Ref(hash_from_bytes(hex_to_bytes(s)))
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
              Ok([#(name, hex_ref(hex)), ..acc])
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

fn branch_pointer_ref(branch: String) -> DefinitionRef {
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
      let prev = case prev_hex {
        "-" -> None
        hex -> Some(hex_ref(hex))
      }
      Ok(#(branch, seq, hex_ref(ns_hex), prev))
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
