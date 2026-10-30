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
import gleam/option.{None}
import gleam/string
import gleamunison/cli_lifecycle
import gleamunison/cli_result
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/identity.{short_hash_hex}
import gleamunison/publication
import gleamunison/storage
import gleamunison/verify
import simplifile

const publish_branch = "main"

// One exit boundary: cli_result owns the stream and the code, so a command
// cannot quietly invent its own.
fn fail(message: String) -> Nil {
  cli_result.fail(message)
}

pub fn command(args: List(String)) -> Nil {
  case args {
    [path] -> run(path)
    _ -> fail("usage: gleam run -- publish <file.lisp>")
  }
}

fn run(path: String) -> Nil {
  case cli_lifecycle.resolve_context(None) {
    Error(reason) -> fail("publish: " <> reason)
    Ok(context) -> publish_with_store(path, context)
  }
}

fn publish_with_store(
  path: String,
  context: cli_lifecycle.StoreContext,
) -> Nil {
  let store_path = cli_lifecycle.store_path(context)
  let manifest_path = cli_lifecycle.manifest_path(context)
  let _ = simplifile.create_directory_all(cli_lifecycle.root_dir(context))
  case storage.dets(store_path) {
    Error(e) -> fail("publish: cannot open store: " <> string.inspect(e))
    Ok(adapter) ->
      case verify.load_defs_file_scoped(path) {
        Error(err) -> {
          let _ = adapter.close()
          fail("publish: " <> err)
        }
        Ok(#(cache, defs, file_names)) -> {
          let term_names =
            list.filter_map(defs, fn(pair) {
              case pair.1 {
                SurfaceTermDef(_) ->
                  case list.contains(file_names, pair.0) {
                    True -> Ok(pair.0)
                    False -> Error(Nil)
                  }
                _ -> Error(Nil)
              }
            })
          case publication.subjects(term_names, defs, cache) {
            Error(err) -> {
              let _ = adapter.close()
              fail("publish: " <> err)
            }
            Ok(selected) -> {
              let decision =
                publication.admit(
                  adapter,
                  cli_lifecycle.root_dir(context),
                  publish_branch,
                  selected,
                )
              case adapter.close() {
                Error(e) ->
                  fail("publish: cannot close store: " <> string.inspect(e))
                Ok(_) -> Nil
              }
              case decision {
                Error(publication.MissingEvidence(missing)) ->
                  fail(refusal_message(path, missing))
                Error(publication.Failed(reason)) -> fail("publish: " <> reason)
                Ok(_) -> {
                  write_manifest(manifest_path, selected)
                  list.each(selected, fn(subject) {
                    io.println(
                      "published: "
                      <> subject.name
                      <> "  #"
                      <> short_hash_hex(subject.content_ref),
                    )
                  })
                  io.println(
                    "publish: "
                    <> int.to_string(list.length(selected))
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

// Name the hash of every refused definition. Without it the attestation path
// for an effectful def is unreachable: the hash is what evidence attaches to,
// and publish was the only command that printed one — while refusing to print
// it.
fn refusal_message(path: String, missing: List(publication.Subject)) -> String {
  let names = list.map(missing, fn(subject) { subject.name })
  let hashes =
    list.map(missing, fn(subject) {
      "  " <> subject.name <> "  #" <> subject.content_ref
    })
  "publish: REFUSED — no evidence for: "
  <> string.join(names, ", ")
  <> "\npublish: content hashes (attest these):\n"
  <> string.join(hashes, "\n")
  <> "\npublish: pure defs need `gleam run -- test "
  <> path
  <> "` (evidence attaches to the content hash);"
  <> " effectful defs may instead carry human attestation:"
  <> " `gleam run -- evidence attest <hash> io <note>`"
}

fn write_manifest(path: String, selected: List(publication.Subject)) -> Nil {
  let existing = case simplifile.read(path) {
    Ok(content) -> string.split(content, "\n")
    Error(_) -> []
  }
  let names = list.map(selected, fn(subject) { subject.name })
  let kept =
    list.filter(existing, fn(line) {
      case string.split_once(line, " ") {
        Ok(#(name, _)) -> !list.contains(names, name)
        Error(_) -> line != ""
      }
    })
  let new_lines =
    list.map(selected, fn(subject) {
      subject.name <> " " <> subject.content_ref
    })
  let content = string.join(list.append(kept, new_lines), "\n") <> "\n"
  case simplifile.write(path, content) {
    Ok(_) -> Nil
    Error(e) -> fail("publish: cannot write manifest: " <> string.inspect(e))
  }
}
