//// Package manifests: the unit of distribution.
////
//// A manifest is pure data: name, version, the definition hashes it
//// contains, the manifests it depends on, and whether installation must
//// see passing-test evidence for every definition. The manifest is itself
//// content-addressed and stored in the DAG — the DAG is the registry;
//// there is no server, no mutable name→version table, no latest.

import gleam/bit_array
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/identity.{
  type DefinitionRef, type Hash, Ref, hash_bytes, hash_from_bytes,
  hash_to_debug_string, hex_to_bytes,
}
import gleamunison/storage.{type StorageAdapter}

pub type Manifest {
  Manifest(
    name: String,
    version: String,
    /// (definition name, hash hex) pairs; hashing/serialization are
    /// canonical (sorted), so order in this list is presentation only.
    defs: List(#(String, String)),
    /// Hex hashes of manifests this package depends on.
    deps: List(String),
    require_evidence: Bool,
  )
}

pub fn new(name: String, version: String) -> Manifest {
  Manifest(name, version, [], [], True)
}

pub fn add_def(m: Manifest, name: String, hash_hex: String) -> Manifest {
  Manifest(..m, defs: list.append(m.defs, [#(name, hash_hex)]))
}

pub fn add_dep(m: Manifest, manifest_hash_hex: String) -> Manifest {
  Manifest(..m, deps: list.append(m.deps, [manifest_hash_hex]))
}

pub fn without_evidence_requirement(m: Manifest) -> Manifest {
  Manifest(..m, require_evidence: False)
}

/// Content hash over the canonical form: same contents, same hash,
/// regardless of the order defs were added in.
pub fn hash_of(m: Manifest) -> Hash {
  hash_bytes(bit_array.from_string(canonical(m)))
}

/// The ref this manifest is stored under.
pub fn ref_of(m: Manifest) -> DefinitionRef {
  Ref(hash_of(m))
}

/// A ref from a hex string (what a user pastes into `pkg install`).
pub fn ref_from_hex(hex: String) -> DefinitionRef {
  Ref(hash_from_bytes(hex_to_bytes(hex)))
}

/// The hex form of a ref — the shareable name of a manifest.
pub fn ref_hex_of(ref: DefinitionRef) -> String {
  hash_to_debug_string(ref_hash(ref))
}

fn canonical(m: Manifest) -> String {
  let defs =
    m.defs
    |> list.sort(fn(a, b) { string.compare(a.0 <> a.1, b.0 <> b.1) })
    |> list.map(fn(p) { p.0 <> "=" <> p.1 })
    |> string.join(",")
  let deps =
    m.deps
    |> list.sort(string.compare)
    |> string.join(",")
  let ev = case m.require_evidence {
    True -> "yes"
    False -> "no"
  }
  "pkg:"
  <> m.name
  <> ":"
  <> m.version
  <> ":"
  <> defs
  <> ":"
  <> deps
  <> ":"
  <> ev
}

/// Canonical text serialization — what gets stored in the DAG.
pub fn serialize(m: Manifest) -> String {
  canonical(m)
}

/// Parse a manifest back from its canonical text form.
pub fn parse(text: String) -> Result(Manifest, String) {
  case string.split(text, ":") {
    ["pkg", name, version, defs, deps, ev] -> {
      use def_pairs <- result.try(parse_defs(defs))
      let dep_list = case deps {
        "" -> []
        _ -> string.split(deps, ",")
      }
      use require_evidence <- result.try(case ev {
        "yes" -> Ok(True)
        "no" -> Ok(False)
        _ -> Error("bad evidence flag: " <> ev)
      })
      Ok(Manifest(name, version, def_pairs, dep_list, require_evidence))
    }
    _ -> Error("not a manifest: " <> text)
  }
}

fn parse_defs(s: String) -> Result(List(#(String, String)), String) {
  case s {
    "" -> Ok([])
    _ ->
      list.try_map(string.split(s, ","), fn(pair) {
        case string.split(pair, "=") {
          [name, hash] -> Ok(#(name, hash))
          _ -> Error("bad def entry: " <> pair)
        }
      })
  }
}

/// Store the manifest in the DAG under its content hash. Returns the ref.
pub fn store(
  adapter: StorageAdapter,
  m: Manifest,
) -> Result(DefinitionRef, String) {
  let ref = ref_of(m)
  adapter.insert(ref, bit_array.from_string(serialize(m)))
  |> result.map_error(fn(e) { "store manifest: " <> storage_error(e) })
  |> result.map(fn(_) { ref })
}

/// Fetch a manifest by ref. The stored bytes re-hash to the requested ref
/// or the fetch fails: integrity is structural, not trusted.
pub fn fetch(
  adapter: StorageAdapter,
  ref: DefinitionRef,
) -> Result(Manifest, String) {
  use bytes <- result.try(
    adapter.lookup(ref)
    |> result.map_error(fn(e) { "fetch manifest: " <> storage_error(e) }),
  )
  case bytes {
    option.None ->
      Error("manifest not found: " <> hash_to_debug_string(ref_hash(ref)))
    option.Some(b) ->
      case bit_array.to_string(b) {
        Error(_) -> Error("manifest bytes are not utf-8")
        Ok(text) -> {
          use m <- result.try(parse(text))
          let actual = hash_of(m)
          case
            hash_to_debug_string(actual) == hash_to_debug_string(ref_hash(ref))
          {
            True -> Ok(m)
            False ->
              Error(
                "manifest integrity failure: stored bytes do not hash to the requested ref",
              )
          }
        }
      }
  }
}

fn ref_hash(r: DefinitionRef) -> Hash {
  let Ref(h) = r
  h
}

fn storage_error(e: storage.StorageError) -> String {
  case e {
    storage.StorageError(msg) -> msg
    storage.NotFound -> "not found"
    storage.IoError(reason) -> "io: " <> reason
  }
}
