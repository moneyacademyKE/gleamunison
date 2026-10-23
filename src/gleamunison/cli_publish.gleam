//// `gleamunison publish <file.lisp>` — the evidence turnstile as a command.
//// Every term definition in the file must carry a passing Test attestation
//// on its content hash (put there by `gleamunison test`). Refusal lists
//// exactly the unevidenced definitions. Admission does two things: the def
//// bytes enter the store (so `run <hash>` and peers can resolve them), and
//// .gleamunison/published records name → hash. The hash is the identity:
//// re-publishing a def replaces its old entry.

import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/ast
import gleamunison/cli_lifecycle
import gleamunison/codebase
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/identity.{Ref, hash_to_debug_string, parse_ref_hex}
import gleamunison/namespace
import gleamunison/repl_eval
import gleamunison/storage
import gleamunison/store_log
import gleamunison/test_runner
import gleamunison/trust
import gleamunison/turnstile
import gleamunison/types
import gleamunison/verify
import simplifile

const publish_branch = "main"

@external(erlang, "gleamunison_ffi", "halt_failure")
fn halt_failure() -> Nil

fn fail(message: String) -> Nil {
  io.println(message)
  halt_failure()
}

pub fn command(args: List(String)) -> Nil {
  case args {
    [path] -> run(path)
    _ -> fail("usage: gleam run -- publish <file.lisp>")
  }
}

fn run(path: String) -> Nil {
  case cli_lifecycle.resolve_store_path() {
    Error(reason) -> fail("publish: " <> reason)
    Ok(store_path) -> publish_with_store(path, store_path)
  }
}

fn publish_with_store(path: String, store_path: String) -> Nil {
  let _ = simplifile.create_directory_all(store_dir(store_path))
  let manifest_path = case cli_lifecycle.resolve_manifest_path() {
    Ok(found) -> found
    Error(reason) -> {
      fail("publish: " <> reason)
      ""
    }
  }
  case storage.dets(store_path) {
    Error(e) -> fail("publish: cannot open store: " <> string.inspect(e))
    Ok(adapter) ->
      case verify.load_defs_file_scoped(path) {
        Error(err) -> {
          let _ = adapter.close()
          fail("publish: " <> err)
        }
        Ok(#(cache, defs, file_names)) -> {
          let file_set = list.filter(file_names, fn(_) { True })
          let term_names =
            list.filter_map(defs, fn(pair) {
              case pair.1 {
                SurfaceTermDef(_) ->
                  case list.contains(file_set, pair.0) {
                    True -> Ok(pair.0)
                    False -> Error(Nil)
                  }
                _ -> Error(Nil)
              }
            })
          case hash_defs(term_names, defs, cache, []) {
            Error(err) -> {
              let _ = adapter.close()
              fail("publish: " <> err)
            }
            Ok(pairs) -> {
              let decision = case trust.production_policy() {
                Error(reason) -> Error([reason])
                Ok(policy) ->
                  turnstile.check_with_policy(adapter, pairs, policy)
              }
              case decision {
                Error(missing) -> {
                  let _ = adapter.close()
                  fail(
                    "publish: REFUSED — no evidence for: "
                    <> string.join(missing, ", ")
                    <> "\npublish: pure defs need `gleam run -- test "
                    <> path
                    <> "` (evidence attaches to the content hash);"
                    <> " effectful defs may instead carry human attestation:"
                    <> " `gleam run -- evidence attest <hash> io <note>`",
                  )
                }
                Ok(passed) -> {
                  let prepared = {
                    use _ <- result.try(store_definitions(
                      adapter,
                      store_dir(store_path),
                      term_names,
                      defs,
                      cache,
                    ))
                    bind_names(adapter, pairs)
                  }
                  case adapter.close() {
                    Error(e) ->
                      fail("publish: cannot close store: " <> string.inspect(e))
                    Ok(_) -> Nil
                  }
                  case prepared {
                    Error(err) -> fail("publish: " <> err)
                    Ok(_) -> {
                      write_manifest(manifest_path, pairs)
                      list.each(pairs, fn(p) {
                        io.println(
                          "published: "
                          <> p.0
                          <> "  #"
                          <> string.slice(p.1, 0, 12),
                        )
                      })
                      io.println(
                        "publish: "
                        <> int.to_string(list.length(passed))
                        <> " definitions admitted by evidence",
                      )
                    }
                  }
                }
              }
            }
          }
        }
      }
  }
}

/// Admission is the moment a definition earns a place in the store. Publishing
/// means fetchable by hash, not merely named; without this the store could only
/// ever be fed by peers.
fn store_definitions(
  adapter: storage.StorageAdapter,
  dir: String,
  names: List(String),
  defs: List(#(String, elab_types.SurfaceDef)),
  cache: types.TypeCache,
) -> Result(Nil, String) {
  let cb = codebase.with_adapter(adapter)
  use _ <- result.try(
    list.try_fold(names, cb, fn(cb, name) {
      case test_runner.elaborated_def_for(name, defs, cache) {
        Error(e) -> Error("cannot elaborate " <> name <> ": " <> e)
        Ok(definition) -> {
          let ref = Ref(codebase.hash_of_definition(definition))
          use _ <- result.try(
            codebase.insert(cb, ast.Unit(root: ref, defs: [#(ref, definition)]))
            |> result.map_error(fn(error) {
              "cannot store " <> name <> ": " <> string.inspect(error)
            }),
          )
          // Admission is the moment content enters the store, so it is the
          // moment the content log records it. A log that cannot be written is
          // reported, not swallowed: the store must be able to say what it holds.
          store_log.record_content(dir, ref_hex(ref), "term")
          |> result.map_error(fn(reason) {
            "cannot record " <> name <> ": " <> reason
          })
          |> result.replace(cb)
        }
      }
    }),
  )
  Ok(Nil)
}

/// Names are the runtime ABI: an elaborated term references its dependencies by
/// ref_for_name, not by content hash. Binding name → content ref in the branch
/// namespace is what lets `run <hash>` resolve those references later, and it is
/// the same binding `pkg install` commits. One table, one owner.
fn bind_names(
  adapter: storage.StorageAdapter,
  pairs: List(#(String, String, Bool)),
) -> Result(Nil, String) {
  let current = case namespace.load_current(adapter, publish_branch) {
    Ok(ns) -> ns
    Error(_) -> namespace.empty()
  }
  use next <- result.try(
    list.try_fold(pairs, current, fn(ns, pair) {
      case parse_ref_hex(pair.1) {
        Error(e) -> Error("cannot bind " <> pair.0 <> ": " <> e)
        Ok(ref) -> Ok(namespace.set(ns, pair.0, ref))
      }
    }),
  )
  namespace.commit(adapter, publish_branch, next)
  |> result.map_error(fn(e) { "cannot commit namespace: " <> e })
  |> result.map(fn(_) { Nil })
}

pub fn hash_defs(
  names: List(String),
  defs: List(#(String, elab_types.SurfaceDef)),
  cache: types.TypeCache,
  acc: List(#(String, String, Bool)),
) -> Result(List(#(String, String, Bool)), String) {
  let _ = acc
  case elaborate_all(names, defs, cache, []) {
    Error(e) -> Error(e)
    Ok(entries) -> {
      let effectful = compute_effectful(entries)
      Ok(
        list.map(entries, fn(e) { #(e.0, e.1, list.contains(effectful, e.0)) }),
      )
    }
  }
}

/// Phase 1: elaborate each named def, keeping the elaborated term — the
/// term is the honest source of effect evidence (ability `Do` nodes live
/// there; top-level value types carry no requirement row).
fn elaborate_all(
  names: List(String),
  defs: List(#(String, elab_types.SurfaceDef)),
  cache: types.TypeCache,
  acc: List(#(String, String, ast.Term)),
) -> Result(List(#(String, String, ast.Term)), String) {
  case names {
    [] -> Ok(list.reverse(acc))
    [name, ..rest] ->
      case test_runner.elaborated_def_for(name, defs, cache) {
        Error(e) -> Error("cannot elaborate " <> name <> ": " <> e)
        Ok(def) ->
          case def {
            ast.TermDef(term, _) -> {
              let hex = hash_to_debug_string(codebase.hash_of_definition(def))
              elaborate_all(rest, defs, cache, [#(name, hex, term), ..acc])
            }
            _ -> Error(name <> " is not a term definition")
          }
      }
  }
}

/// Phase 2: transitive effect closure. A def is effectful when its own
/// term performs an ability op, or it references (directly or through
/// other batch defs) one that does. Conservative by design: a `Do` under a
/// `Handle` still counts — discharged-in-term handlers are rare enough
/// that the safe direction wins. Ambient jets (`now`, `read_line`) are
/// invisible to the term walk — a documented limit of the current effect
/// system, not a loophole: their users still need Test or Io evidence.
fn compute_effectful(
  entries: List(#(String, String, ast.Term)),
) -> List(String) {
  let initial =
    list.filter_map(entries, fn(e) {
      case term_has_do(e.2) {
        True -> Ok(e.0)
        False -> Error(Nil)
      }
    })
  expand_effectful(entries, initial)
}

fn expand_effectful(
  entries: List(#(String, String, ast.Term)),
  known: List(String),
) -> List(String) {
  let new =
    list.filter_map(entries, fn(e) {
      case list.contains(known, e.0) {
        True -> Error(Nil)
        False -> {
          let dep_names =
            list.filter_map(term_deps(e.2), fn(h) { name_of_hex(entries, h) })
          case list.any(dep_names, fn(n) { list.contains(known, n) }) {
            True -> Ok(e.0)
            False -> Error(Nil)
          }
        }
      }
    })
  case new {
    [] -> known
    _ -> expand_effectful(entries, list.append(known, new))
  }
}

fn name_of_hex(
  entries: List(#(String, String, ast.Term)),
  hex: String,
) -> Result(String, Nil) {
  // Elaboration wires intra-batch refs by name (ref_for_name = sha256 of
  // the name), while evidence identity is the content hash. Closure edges
  // come from the term's refs, so they key on name-hashes; content hashes
  // stay strictly for evidence.
  case
    list.find(entries, fn(e) { ref_hex(repl_eval.ref_for_name(e.0)) == hex })
  {
    Ok(e) -> Ok(e.0)
    Error(_) -> Error(Nil)
  }
}

fn term_has_do(t: ast.Term) -> Bool {
  case t {
    ast.Do(..) -> True
    ast.RefTo(_)
    | ast.LocalVarRef(_)
    | ast.Int(_)
    | ast.Float(_)
    | ast.Text(_)
    | ast.Hole -> False
    ast.List(items) -> list.any(items, term_has_do)
    ast.Apply(f, a) -> term_has_do(f) || term_has_do(a)
    ast.Lambda(_, body) -> term_has_do(body)
    ast.Let(_, value, body) -> term_has_do(value) || term_has_do(body)
    ast.Match(scrutinee, cases) ->
      term_has_do(scrutinee) || list.any(cases, case_has_do)
    ast.Handle(comp, handler, _) -> term_has_do(comp) || term_has_do(handler)
    ast.Construct(_, args) -> list.any(args, term_has_do)
    ast.Use(_, call, body) -> term_has_do(call) || term_has_do(body)
    ast.Located(inner, _) -> term_has_do(inner)
  }
}

fn case_has_do(c: ast.Case) -> Bool {
  let guard_has = case c.guard {
    option.Some(ast.GuardTerm(t)) -> term_has_do(t)
    option.None -> False
  }
  guard_has || term_has_do(c.body)
}

/// Every definition hash this term references — the closure edges. Ability
/// refs and constructor refs won't resolve to batch names, which is fine:
/// they carry no effect evidence of their own here.
fn term_deps(t: ast.Term) -> List(String) {
  do_term_deps(t, [])
}

fn do_term_deps(t: ast.Term, acc: List(String)) -> List(String) {
  case t {
    ast.RefTo(ref) -> [ref_hex(ref), ..acc]
    ast.LocalVarRef(_) | ast.Int(_) | ast.Float(_) | ast.Text(_) | ast.Hole ->
      acc
    ast.List(items) -> list.fold(items, acc, fn(a, x) { do_term_deps(x, a) })
    ast.Apply(f, a) -> do_term_deps(a, do_term_deps(f, acc))
    ast.Lambda(_, body) -> do_term_deps(body, acc)
    ast.Let(_, value, body) -> do_term_deps(body, do_term_deps(value, acc))
    ast.Match(scrutinee, cases) -> {
      let acc2 = do_term_deps(scrutinee, acc)
      list.fold(cases, acc2, fn(a, c) {
        let a2 = case c.guard {
          option.Some(ast.GuardTerm(gt)) -> do_term_deps(gt, a)
          option.None -> a
        }
        do_term_deps(c.body, a2)
      })
    }
    ast.Do(_, _, args) -> list.fold(args, acc, fn(a, x) { do_term_deps(x, a) })
    ast.Handle(comp, handler, _) ->
      do_term_deps(handler, do_term_deps(comp, acc))
    ast.Construct(_, args) ->
      list.fold(args, acc, fn(a, x) { do_term_deps(x, a) })
    ast.Use(_, call, body) -> do_term_deps(body, do_term_deps(call, acc))
    ast.Located(inner, _) -> do_term_deps(inner, acc)
  }
}

fn ref_hex(ref: identity.DefinitionRef) -> String {
  let identity.Ref(h) = ref
  hash_to_debug_string(h)
}

fn write_manifest(path: String, pairs: List(#(String, String, Bool))) -> Nil {
  let existing = case simplifile.read(path) {
    Ok(content) -> string.split(content, "\n")
    Error(_) -> []
  }
  let names = list.map(pairs, fn(p) { p.0 })
  let kept =
    list.filter(existing, fn(line) {
      case string.split_once(line, " ") {
        Ok(#(name, _)) -> !list.contains(names, name)
        Error(_) -> line != ""
      }
    })
  let new_lines = list.map(pairs, fn(p) { p.0 <> " " <> p.1 })
  let content = string.join(list.append(kept, new_lines), "\n") <> "\n"
  case simplifile.write(path, content) {
    Ok(_) -> Nil
    Error(e) -> fail("publish: cannot write manifest: " <> string.inspect(e))
  }
}

/// The directory a store file lives in, so an overridden store creates its own
/// directory rather than the default one.
fn store_dir(path: String) -> String {
  case list.reverse(string.split(path, "/")) {
    [_, ..parent] ->
      case list.reverse(parent) |> string.join("/") {
        "" -> "/"
        dir -> dir
      }
    [] -> "."
  }
}
