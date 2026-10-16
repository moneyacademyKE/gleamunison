//// Package installation: the registry's read path.
////
//// install_from_store composes the three shipped pieces: manifest fetch
//// (integrity re-hashed), the evidence turnstile (no passing test on the
//// content hash, no install), and the versioned namespace (bindings land
//// as a commit on the target branch — causal history included).
////
//// v2: manifest deps install recursively (cycle-safe — a manifest is
//// installed once per install, even under repeated or cyclic dep edges).
//// Peer fetching is the CLI's job: `manifest_closure` computes exactly
//// the ref set a peer transfer needs, so sync moves the closure, not
//// the universe.

import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleamunison/manifest
import gleamunison/namespace
import gleamunison/storage.{type StorageAdapter}
import gleamunison/turnstile

/// The transitive ref set a package needs: every manifest in its dep
/// graph plus every def hash those manifests carry.
pub type Closure {
  Closure(manifests: List(String), defs: List(String))
}

/// Walk the dep graph from a root manifest hash, collecting manifests
/// and def hashes. Cycle-safe: visited manifests are never re-entered.
pub fn manifest_closure(
  adapter: StorageAdapter,
  root_hex: String,
) -> Result(Closure, String) {
  use #(ms, ds, _seen) <- result.try(closure_walk(
    adapter,
    [root_hex],
    [],
    [],
    set.new(),
  ))
  Ok(Closure(manifests: list.reverse(ms), defs: list.reverse(ds)))
}

fn closure_walk(
  adapter: StorageAdapter,
  queue: List(String),
  ms: List(String),
  ds: List(String),
  seen: Set(String),
) -> Result(#(List(String), List(String), Set(String)), String) {
  case queue {
    [] -> Ok(#(ms, ds, seen))
    [hex, ..rest] ->
      case set.contains(seen, hex) {
        True -> closure_walk(adapter, rest, ms, ds, seen)
        False -> {
          use m <- result.try(manifest.fetch(
            adapter,
            manifest.ref_from_hex(hex),
          ))
          let seen = set.insert(seen, hex)
          let def_hashes = list.map(m.defs, fn(d) { d.1 })
          closure_walk(
            adapter,
            list.append(m.deps, rest),
            [hex, ..ms],
            list.append(def_hashes, ds),
            seen,
          )
        }
      }
  }
}

/// Pull exactly a package's closure through `fetch_batch` (a transport
/// that fetches ref hexes into the local adapter). Manifests are walked
/// iteratively — dep manifests only become readable once they land —
/// then missing def chunks are fetched in one batch. Returns the
/// closure that was transferred.
pub fn pull_closure(
  adapter: StorageAdapter,
  root_hex: String,
  fetch_batch: fn(List(String)) -> Result(Nil, String),
) -> Result(Closure, String) {
  use closure <- result.try(pull_manifests(
    adapter,
    [root_hex],
    [],
    [],
    set.new(),
    fetch_batch,
  ))
  let missing_defs =
    list.filter(closure.defs, fn(hex) { !is_local(adapter, hex) })
  case missing_defs {
    [] -> Ok(Nil)
    _ -> fetch_batch(missing_defs)
  }
  |> result.map(fn(_) { closure })
}

fn pull_manifests(
  adapter: StorageAdapter,
  queue: List(String),
  ms: List(String),
  ds: List(String),
  seen: Set(String),
  fetch_batch: fn(List(String)) -> Result(Nil, String),
) -> Result(Closure, String) {
  case queue {
    [] -> Ok(Closure(manifests: list.reverse(ms), defs: list.reverse(ds)))
    [hex, ..rest] ->
      case set.contains(seen, hex) {
        True -> pull_manifests(adapter, rest, ms, ds, seen, fetch_batch)
        False -> {
          let seen = set.insert(seen, hex)
          use _ <- result.try(case is_local(adapter, hex) {
            True -> Ok(Nil)
            False -> fetch_batch([hex])
          })
          use m <- result.try(manifest.fetch(
            adapter,
            manifest.ref_from_hex(hex),
          ))
          let def_hashes = list.map(m.defs, fn(d) { d.1 })
          pull_manifests(
            adapter,
            list.append(m.deps, rest),
            [hex, ..ms],
            list.append(def_hashes, ds),
            seen,
            fetch_batch,
          )
        }
      }
  }
}

fn is_local(adapter: StorageAdapter, hex: String) -> Bool {
  case adapter.lookup(manifest.ref_from_hex(hex)) {
    Ok(Some(_)) -> True
    _ -> False
  }
}

/// Install a package from the local store onto a branch.
/// Deps install first, recursively; each manifest in the graph installs
/// once even under cyclic or repeated dep edges. Returns every admitted
/// definition name (deps first). Refuses (Error naming the unevidenced
/// defs) when a gated manifest lacks passing Test attestation.
pub fn install_from_store(
  adapter: StorageAdapter,
  manifest_hex: String,
  branch: String,
) -> Result(List(String), String) {
  use #(names, _visited) <- result.try(install_recursive(
    adapter,
    manifest_hex,
    branch,
    set.new(),
  ))
  Ok(names)
}

fn install_recursive(
  adapter: StorageAdapter,
  manifest_hex: String,
  branch: String,
  visited: Set(String),
) -> Result(#(List(String), Set(String)), String) {
  case set.contains(visited, manifest_hex) {
    True -> Ok(#([], visited))
    False -> {
      let visited = set.insert(visited, manifest_hex)
      use m <- result.try(manifest.fetch(
        adapter,
        manifest.ref_from_hex(manifest_hex),
      ))
      use #(dep_names, visited) <- result.try(
        list.try_fold(m.deps, #([], visited), fn(acc, dep_hex) {
          let #(names, vis) = acc
          use #(dn, vis2) <- result.try(install_recursive(
            adapter,
            dep_hex,
            branch,
            vis,
          ))
          Ok(#(list.append(names, dn), vis2))
        }),
      )
      use admitted <- result.try(case m.require_evidence {
        True ->
          // Manifests carry name+hash only today (no effect flags), so
          // package defs are gated as pure: Test evidence required.
          // Manifest-carried requirement rows are a filed follow-up.
          turnstile.check(
            adapter,
            list.map(m.defs, fn(d) { #(d.0, d.1, False) }),
          )
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
      Ok(#(list.append(dep_names, admitted), visited))
    }
  }
}

/// Publish #(name, hash, effectful) triples as a manifest in the DAG. The
/// turnstile runs first with the real flags: pure defs need passing-test
/// evidence, effectful defs may carry Io attestation. Any unevidenced def
/// refuses the whole publish (Error names them). Success stores the
/// manifest (name+hash only — effect flags are a filed follow-up) and
/// returns its hex: the shareable name of the package.
pub fn publish_to_store(
  adapter: StorageAdapter,
  defs: List(#(String, String, Bool)),
  name: String,
  version: String,
) -> Result(String, List(String)) {
  use _ <- result.try(turnstile.check(adapter, defs))
  let m =
    list.fold(defs, manifest.new(name, version), fn(m, d) {
      manifest.add_def(m, d.0, d.1)
    })
  case manifest.store(adapter, m) {
    Ok(ref) -> Ok(manifest.ref_hex_of(ref))
    Error(_) -> Error(["store manifest failed"])
  }
}
