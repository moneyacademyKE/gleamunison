//// Test-only manifest builders, relocated from src (bk-e431).
////
//// `add_def`, `add_dep` and `without_evidence_requirement` had zero
//// production callers: production builds manifests through
//// `manifest.new` + `add_def_with_effect` + `store` (pkg.gleam). These
//// conveniences shadowed that path from the public API. Bodies are
//// verbatim from src/gleamunison/manifest.gleam.

import gleam/list
import gleamunison/manifest.{type Manifest, Manifest, add_def_with_effect}

/// Add a pure definition. Pure is the conservative compatibility default.
pub fn add_def(m: Manifest, name: String, hash_hex: String) -> Manifest {
  add_def_with_effect(m, name, hash_hex, False)
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
