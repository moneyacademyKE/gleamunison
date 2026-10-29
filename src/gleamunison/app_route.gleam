//// Serve admitted definitions, never scratch or arbitrary CAS content.
//// A route resolves through one selected branch, then delegates execution and
//// evidence admission to the same `run_ref` gate used by `run --json`.

import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string
import gleamunison/app_path
import gleamunison/app_response
import gleamunison/identity.{type DefinitionRef}
import gleamunison/json
import gleamunison/namespace
import gleamunison/run_error
import gleamunison/run_ref
import gleamunison/storage

const max_request_bytes = 65_536

const max_arguments = 8

pub type Response {
  Response(status: Int, body: String)
}

type Target {
  Named(String)
  Content(String)
}

pub fn request(
  adapter: storage.StorageAdapter,
  branch: String,
  raw_target: String,
  body: String,
) -> Response {
  case prepare(adapter, branch, raw_target, body) {
    Error(response) -> response
    Ok(#(ref, args)) -> execute(adapter, branch, ref, args)
  }
}

fn prepare(
  adapter: storage.StorageAdapter,
  branch: String,
  raw_target: String,
  body: String,
) -> Result(#(DefinitionRef, List(Dynamic)), Response) {
  use _ <- result.try(check_request_size(body))
  use target <- result.try(parse_target(raw_target))
  use args <- result.try(decode_arguments(body))
  use ref <- result.try(resolve(adapter, branch, target))
  Ok(#(ref, args))
}

fn check_request_size(body: String) -> Result(Nil, Response) {
  case bit_array.byte_size(bit_array.from_string(body)) <= max_request_bytes {
    True -> Ok(Nil)
    False ->
      Error(failure(
        413,
        "request_too_large",
        "application input exceeds 65536 bytes",
      ))
  }
}

fn parse_target(raw: String) -> Result(Target, Response) {
  case string.split(raw, "/") {
    ["ref", hex] -> Ok(Content(hex))
    [name] ->
      case app_path.segment(name) {
        Error(_) -> Error(invalid_target())
        Ok(decoded) ->
          case valid_name(decoded) {
            True -> Ok(Named(decoded))
            False -> Error(invalid_target())
          }
      }
    _ -> Error(invalid_target())
  }
}

fn valid_name(name: String) -> Bool {
  let size = bit_array.byte_size(bit_array.from_string(name))
  name != "" && size <= 256 && !string.contains(name, "/")
}

fn invalid_target() -> Response {
  failure(
    400,
    "invalid_route",
    "expected /app/<name> or /app/ref/<content-ref>",
  )
}

fn decode_arguments(body: String) -> Result(List(Dynamic), Response) {
  case string.trim(body) {
    "" -> Ok([])
    _ ->
      case json.decode(bit_array.from_string(body)) {
        Error(_) -> Error(invalid_request())
        Ok(value) ->
          case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
            Error(_) -> Error(invalid_request())
            Ok(envelope) ->
              case dict.keys(envelope), dict.get(envelope, "args") {
                ["args"], Ok(encoded) ->
                  case decode.run(encoded, decode.list(decode.dynamic)) {
                    Error(_) -> Error(invalid_request())
                    Ok(args) ->
                      case list.length(args) <= max_arguments {
                        True -> Ok(args)
                        False -> Error(invalid_request())
                      }
                  }
                _, _ -> Error(invalid_request())
              }
          }
      }
  }
}

fn invalid_request() -> Response {
  failure(
    400,
    "invalid_request",
    "expected a JSON object with only an args array of at most 8 values",
  )
}

fn resolve(
  adapter: storage.StorageAdapter,
  branch: String,
  target: Target,
) -> Result(DefinitionRef, Response) {
  case namespace.load_current_or_empty(adapter, branch) {
    Error(reason) -> Error(failure(503, "storage_unavailable", reason))
    Ok(ns) ->
      case target {
        Named(name) ->
          namespace.get(ns, name)
          |> result.map_error(fn(_) {
            failure(404, "not_found", "no admitted route named " <> name)
          })
        Content(hex) ->
          case identity.parse_ref_hex(hex) {
            Error(message) -> Error(failure(400, "invalid_route", message))
            Ok(ref) ->
              case namespace.binds(ns, ref) {
                True -> Ok(ref)
                False ->
                  Error(failure(
                    404,
                    "not_found",
                    "content is not bound on the selected branch",
                  ))
              }
          }
      }
  }
}

fn execute(
  adapter: storage.StorageAdapter,
  branch: String,
  ref: DefinitionRef,
  args: List(Dynamic),
) -> Response {
  case run_ref.run_verified_raw_on_branch(adapter, ref, branch, args, False) {
    Error(error) -> execution_failure(error)
    Ok(term) -> {
      let hex = identity.ref_hex(ref)
      case app_response.success(hex, branch, term) {
        Ok(body) -> Response(200, body)
        Error(code) ->
          failure(413, code, "application result exceeds the response budget")
      }
    }
  }
}

fn execution_failure(error: run_error.RunError) -> Response {
  let detail = run_error.describe(error)
  case error {
    run_error.Missing(_) -> failure(404, "not_found", detail)
    run_error.NoEvidence(_, _) -> failure(403, "evidence_refused", detail)
    run_error.ArityUnavailable(_, _, _) ->
      failure(400, "invalid_arguments", detail)
    run_error.NotExecutable(_, _) -> failure(422, "not_executable", detail)
    run_error.EvaluationFailed(_, _) ->
      failure(422, "evaluation_failed", detail)
    run_error.Unreadable(_, _)
    | run_error.Cycle(_)
    | run_error.LoadFailed(_, _) ->
      failure(500, "execution_unavailable", detail)
  }
}

fn failure(status: Int, code: String, detail: String) -> Response {
  Response(status, app_response.failure(code, detail))
}
