//// Package installation: the registry's read path.
////
//// install_from_store composes the three shipped pieces: manifest fetch
//// (integrity re-hashed), the evidence turnstile (no passing test on the
//// content hash, no install), and the versioned namespace (bindings land
//// as a commit on the target branch — causal history included).
////
//// v1 scope: manifest deps are listed but not auto-installed — install
//// them first, separately. Peer fetching is the CLI's job (sync first,
//// then install from the now-populated local store).

import gleam/list
import gleam/result
import gleam/string
import gleamunison/manifest
import gleamunison/namespace
import gleamunison/storage.{type StorageAdapter}
import gleamunison/turnstile

/// Install a package from the local store onto a branch.
/// Returns the admitted definition names. Refuses (Error naming the
/// unevidenced defs) when the manifest requires evidence and any gated
/// def lacks a passing Test attestation.
pub fn install_from_store(
  adapter: StorageAdapter,
  manifest_hex: String,
  branch: String,
) -> Result(List(String), String) {
  use m <- result.try(manifest.fetch(
    adapter,
    manifest.ref_from_hex(manifest_hex),
  ))
  use admitted <- result.try(case m.require_evidence {
    True ->
      turnstile.check(adapter, m.defs)
      |> result.map_error(fn(missing) {
        "install REFUSED — no passing test evidence for: "
        <> string.join(missing, ", ")
      })
    False -> Ok(list.map(m.defs, fn(d) { d.0 }))
  })
  let current = case namespace.load_current(adapter, branch) {
    Ok(ns) -> ns
    Error(_) -> namespace.empty()
  }
  let next =
    list.fold(m.defs, current, fn(ns, d) {
      namespace.set(ns, d.0, manifest.ref_from_hex(d.1))
    })
  use _ <- result.try(namespace.commit(adapter, branch, next))
  Ok(admitted)
}
