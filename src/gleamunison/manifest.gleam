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
  type DefinitionRef, type Hash, Ref, hash_bytes, hash_to_debug_string,
  parse_ref_hex, ref_hex,
}
import gleamunison/storage.{type StorageAdapter}

pub type ManifestDef {
  ManifestDef(name: String, hash_hex: String, effectful: Bool)
}

pub type Manifest {
  Manifest(
    name: String,
    version: String,
    defs: List(ManifestDef),
    /// Hex hashes of manifests this package depends on.
    deps: List(String),
    require_evidence: Bool,
    /// 1 is the legacy name=hash format; 2 carries effectful per-def flags.
    format_version: Int,
  )
}

pub fn new(name: String, version: String) -> Manifest {
  Manifest(name, version, [], [], True, 2)
}

/// Add a pure definition. Pure is the conservative compatibility default.
pub fn add_def(m: Manifest, name: String, hash_hex: String) -> Manifest {
  add_def_with_effect(m, name, hash_hex, False)
}

pub fn add_def_with_effect(
  m: Manifest,
  name: String,
  hash_hex: String,
  effectful: Bool,
) -> Manifest {
  Manifest(
    ..m,
    defs: list.append(m.defs, [ManifestDef(name, hash_hex, effectful)]),
    format_version: 2,
  )
}

pub fn def_name(def: ManifestDef) -> String {
  def.name
}

pub fn def_hash(def: ManifestDef) -> String {
  def.hash_hex
}

pub fn def_effectful(def: ManifestDef) -> Bool {
  def.effectful
}

pub fn add_dep(m: Manifest, manifest_hash_hex: String) -> Manifest {
  Manifest(
    ..m,
    deps: list.append(m.deps, [manifest_hash_hex]),
    format_version: 2,
  )
}

pub fn without_evidence_requirement(m: Manifest) -> Manifest {
  Manifest(..m, require_evidence: False, format_version: 2)
}

/// Content hash over the canonical form: same contents, same hash,
/// regardless of the order defs were added in.
pub fn hash_of(m: Manifest) -> Hash {
  hash_bytes(bit_array.from_string(serialize(m)))
}

/// The ref this manifest is stored under.
pub fn ref_of(m: Manifest) -> DefinitionRef {
  Ref(hash_of(m))
}

/// A ref from a hex string (what a user pastes into `pkg install`).
pub fn ref_from_hex(hex: String) -> Result(DefinitionRef, String) {
  parse_ref_hex(hex)
  |> result.map_error(fn(reason) { "invalid manifest reference: " <> reason })
}

/// Current canonical text. The version marker makes the format unambiguous;
/// the effect token is part of the content identity.
fn canonical(m: Manifest) -> String {
  let defs =
    m.defs
    |> list.sort(fn(a, b) { string.compare(def_sort_key(a), def_sort_key(b)) })
    |> list.map(serialize_def)
    |> string.join(",")
  let deps =
    m.deps
    |> list.sort(string.compare)
    |> string.join(",")
  let ev = evidence_flag(m.require_evidence)
  "pkg:2:"
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

/// Legacy canonical text is retained so a parsed old manifest re-hashes to
/// its existing ref. Legacy entries have no effect metadata and are pure.
fn legacy_canonical(m: Manifest) -> String {
  let defs =
    m.defs
    |> list.sort(fn(a, b) {
      string.compare(a.name <> a.hash_hex, b.name <> b.hash_hex)
    })
    |> list.map(fn(d) { d.name <> "=" <> d.hash_hex })
    |> string.join(",")
  let deps =
    m.deps
    |> list.sort(string.compare)
    |> string.join(",")
  "pkg:"
  <> m.name
  <> ":"
  <> m.version
  <> ":"
  <> defs
  <> ":"
  <> deps
  <> ":"
  <> evidence_flag(m.require_evidence)
}

fn def_sort_key(def: ManifestDef) -> String {
  def.name <> def.hash_hex <> effect_token(def.effectful)
}

fn serialize_def(def: ManifestDef) -> String {
  def.name <> "=" <> def.hash_hex <> "=" <> effect_token(def.effectful)
}

fn effect_token(effectful: Bool) -> String {
  case effectful {
    True -> "effectful"
    False -> "pure"
  }
}

fn evidence_flag(required: Bool) -> String {
  case required {
    True -> "yes"
    False -> "no"
  }
}

/// Serialize using the format version carried by the value. This preserves
/// the hash of legacy manifests loaded from the store.
pub fn serialize(m: Manifest) -> String {
  case m.format_version {
    1 -> legacy_canonical(m)
    _ -> canonical(m)
  }
}

/// Parse current manifests and the original name=hash format. Legacy entries
/// deliberately become pure: absent metadata never grants Io admission.
pub fn parse(text: String) -> Result(Manifest, String) {
  case string.split(text, ":") {
    ["pkg", "2", name, version, defs, deps, ev] ->
      parse_parts(name, version, defs, deps, ev, 2, parse_current_defs)
    ["pkg", name, version, defs, deps, ev] ->
      parse_parts(name, version, defs, deps, ev, 1, parse_legacy_defs)
    _ -> Error("not a manifest: " <> text)
  }
}

fn parse_parts(
  name: String,
  version: String,
  defs: String,
  deps: String,
  ev: String,
  format_version: Int,
  parse_defs: fn(String) -> Result(List(ManifestDef), String),
) -> Result(Manifest, String) {
  use def_entries <- result.try(parse_defs(defs))
  let dep_list = case deps {
    "" -> []
    _ -> string.split(deps, ",")
  }
  use require_evidence <- result.try(case ev {
    "yes" -> Ok(True)
    "no" -> Ok(False)
    _ -> Error("bad evidence flag: " <> ev)
  })
  Ok(Manifest(
    name,
    version,
    def_entries,
    dep_list,
    require_evidence,
    format_version,
  ))
}

fn parse_legacy_defs(s: String) -> Result(List(ManifestDef), String) {
  case s {
    "" -> Ok([])
    _ ->
      list.try_map(string.split(s, ","), fn(pair) {
        case string.split(pair, "=") {
          [name, hash] -> Ok(ManifestDef(name, hash, False))
          _ -> Error("bad legacy def entry: " <> pair)
        }
      })
  }
}

fn parse_current_defs(s: String) -> Result(List(ManifestDef), String) {
  case s {
    "" -> Ok([])
    _ ->
      list.try_map(string.split(s, ","), fn(pair) {
        case string.split(pair, "=") {
          [name, hash, effect] ->
            case effect {
              "pure" -> Ok(ManifestDef(name, hash, False))
              "effectful" -> Ok(ManifestDef(name, hash, True))
              _ -> Error("bad effect flag: " <> effect)
            }
          _ -> Error("bad current def entry: " <> pair)
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
  |> result.map_error(fn(e) { "store manifest: " <> storage.describe_error(e) })
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
    |> result.map_error(fn(e) {
      "fetch manifest: " <> storage.describe_error(e)
    }),
  )
  case bytes {
    option.None -> Error("manifest not found: " <> ref_hex(ref))
    option.Some(b) ->
      case bit_array.to_string(b) {
        Error(_) -> Error("manifest bytes are not utf-8")
        Ok(text) -> {
          use m <- result.try(parse(text))
          let actual = hash_of(m)
          case hash_to_debug_string(actual) == ref_hex(ref) {
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
