//// `gleamunison publish <file.lisp>` — the evidence turnstile as a command.
//// Every term definition in the file must carry a passing Test attestation
//// on its content hash (put there by `gleamunison test`). Refusal lists
//// exactly the unevidenced definitions; success merges the defs into
//// .gleamunison/published as name → hash lines. The hash is the identity:
//// re-publishing a def replaces its old entry.

import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamunison/codebase
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/identity.{hash_to_debug_string}
import gleamunison/storage
import gleamunison/test_runner
import gleamunison/turnstile
import gleamunison/types
import gleamunison/verify
import simplifile

pub fn command(args: List(String)) -> Nil {
  case args {
    [path] -> run(path)
    _ -> io.println("usage: gleam run -- publish <file.lisp>")
  }
}

fn run(path: String) -> Nil {
  let _ = simplifile.create_directory_all(".gleamunison")
  case storage.dets(".gleamunison/store.dets") {
    Error(e) -> io.println("publish: cannot open store: " <> string.inspect(e))
    Ok(adapter) ->
      case verify.load_defs_file_scoped(path) {
        Error(err) -> io.println("publish: " <> err)
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
            Error(err) -> io.println("publish: " <> err)
            Ok(pairs) ->
              case turnstile.check(adapter, pairs) {
                Error(missing) ->
                  io.println(
                    "publish: REFUSED — no passing test evidence for: "
                    <> string.join(missing, ", ")
                    <> "\npublish: run `gleam run -- test "
                    <> path
                    <> "` first; evidence attaches to the content hash.",
                  )
                Ok(passed) -> {
                  write_manifest(pairs)
                  list.each(pairs, fn(p) {
                    io.println(
                      "published: " <> p.0 <> "  #" <> string.slice(p.1, 0, 12),
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

pub fn hash_defs(
  names: List(String),
  defs: List(#(String, elab_types.SurfaceDef)),
  cache: types.TypeCache,
  acc: List(#(String, String)),
) -> Result(List(#(String, String)), String) {
  case names {
    [] -> Ok(list.reverse(acc))
    [name, ..rest] ->
      case test_runner.elaborated_def_for(name, defs, cache) {
        Error(e) -> Error("cannot elaborate " <> name <> ": " <> e)
        Ok(def) -> {
          let hex = hash_to_debug_string(codebase.hash_of_definition(def))
          hash_defs(rest, defs, cache, [#(name, hex), ..acc])
        }
      }
  }
}

fn write_manifest(pairs: List(#(String, String))) -> Nil {
  let path = ".gleamunison/published"
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
  let _ = simplifile.write(path, content)
  Nil
}
