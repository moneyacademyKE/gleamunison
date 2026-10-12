import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/datetime
import gleamunison/effects.{
  type HandlerFrame, type OpHandler, HandlerFrame, RuntimeConfig,
}
import gleamunison/elab_types.{type SurfaceDef, SurfaceTermDef, SurfaceUnit}
import gleamunison/elaborate as elab
import gleamunison/evidence
import gleamunison/identity.{type DefinitionRef, hash_to_debug_string}
import gleamunison/repl_eval
import gleamunison/storage.{type StorageAdapter}
import gleamunison/transcript
import gleamunison/types.{type TypeCache}

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn unsafe_coerce(val: Dynamic) -> a

/// One test definition's outcome: assertion tallies from the Test tape.
pub type TestResult {
  TestResult(name: String, passed: Int, failed: Int, error: Option(String))
}

/// The Test ability's ref: surface-declared abilities are keyed by name hash.
pub fn ability_ref() -> DefinitionRef {
  repl_eval.ref_for_name("Test")
}

/// The expect handler: passes the assertion value through unchanged; the
/// recorder on the frame is what makes the run observable.
fn expect_handler() -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    case args {
      [first, ..] -> cont(first)
      [] -> cont(to_dynamic(0))
    }
  }
}

fn expect_frame() -> HandlerFrame {
  HandlerFrame(
    ability: ability_ref(),
    ops: dict.from_list([#(0, expect_handler())]),
  )
}

fn is_test_name(name: String) -> Bool {
  string.starts_with(name, "test_")
}

fn verdict_of(r: TestResult) -> String {
  case r.error, r.failed {
    Some(_), _ -> "error"
    None, 0 -> "pass"
    None, _ -> "fail"
  }
}

/// Run every `test_`-named definition under a recording Test handler.
/// The runner owns loading: all non-test defs are compiled and loaded first
/// (idempotent — handle_define unloads before loading), so test bodies may
/// reference them at runtime. Pure sweep: results are values; nothing is
/// stored here.
pub fn run_suite(
  defs: List(#(String, SurfaceDef)),
  cache: TypeCache,
) -> List(TestResult) {
  // Load every non-test term def so test bodies can reference them at
  // runtime. Each define elaborates against the FULL def list (dependency
  // order preserved), and handle_define unloads before loading, so
  // re-loading an already-bootstrapped def is idempotent.
  let loaded_cache =
    list.fold(defs, cache, fn(c, pair) {
      case pair {
        #(name, SurfaceTermDef(val)) ->
          case is_test_name(name) {
            True -> c
            False ->
              case repl_eval.handle_define(name, val, c, defs) {
                Ok(#(nc, _)) -> nc
                Error(_) -> c
              }
          }
        _ -> c
      }
    })
  defs
  |> list.filter(fn(pair) { is_test_name(pair.0) })
  |> list.map(fn(pair) {
    let #(name, sd) = pair
    case sd {
      SurfaceTermDef(body) -> {
        let rec = transcript.start()
        let frames = transcript.wrap_frames(rec, [expect_frame()])
        let outcome =
          effects.run(RuntimeConfig(ambient_handlers: frames), fn() {
            to_dynamic(repl_eval.do_eval(
              body,
              name <> "__run",
              loaded_cache,
              defs,
            ))
          })
        let eval_result: Result(#(String, ast.Type, TypeCache), String) =
          unsafe_coerce(outcome)
        let entries = transcript.entries(rec)
        transcript.stop(rec)
        let failed = list.count(entries, fn(e) { e.result_repr == "0" })
        case eval_result {
          Error(err) ->
            TestResult(name:, passed: 0, failed: 0, error: Some(err))
          Ok(_) ->
            TestResult(
              name:,
              passed: list.length(entries) - failed,
              failed:,
              error: None,
            )
        }
      }
      _ -> TestResult(name:, passed: 0, failed: 0, error: Some("not a term"))
    }
  })
}

/// Elaborate the unit and return the core definition for a name, so callers
/// can hash the SUBJECT of a test (not the surface source).
pub fn elaborated_def_for(
  name: String,
  defs: List(#(String, SurfaceDef)),
  cache: TypeCache,
) -> Result(ast.Definition, String) {
  let root = repl_eval.ref_for_name(name)
  case elab.elaborate_unit(SurfaceUnit(root: root, defs:), cache) {
    Error(err) -> Error(string.inspect(err))
    Ok(#(unit, _, _)) ->
      case list.key_find(unit.defs, root) {
        Ok(def) -> Ok(def)
        Error(_) -> Error("no def for " <> name)
      }
  }
}

/// Attach one evidence record per test result to its subject's hash.
/// A test named `test_foo` attests the definition `foo`. Orphan tests
/// (no such subject) attach nothing and are skipped in the output.
pub fn attach_results(
  adapter: StorageAdapter,
  results: List(TestResult),
  defs: List(#(String, SurfaceDef)),
  cache: TypeCache,
) -> List(Result(#(DefinitionRef, String), evidence.AttachError)) {
  results
  |> list.filter_map(fn(r) {
    let subject_name = string.drop_start(r.name, 5)
    let subject_exists =
      list.any(defs, fn(pair) { pair.0 == subject_name && is_term_def(pair.1) })
    case subject_exists {
      False -> Error(Nil)
      True -> {
        case elaborated_def_for(subject_name, defs, cache) {
          Error(_) -> Error(Nil)
          Ok(subject_def) -> {
            let subject_hex =
              hash_to_debug_string(codebase.hash_of_definition(subject_def))
            let payload =
              r.name
              <> ": "
              <> int.to_string(r.passed)
              <> " passed, "
              <> int.to_string(r.failed)
              <> " failed"
              <> case r.error {
                Some(e) -> ", error: " <> e
                None -> ""
              }
            Ok(evidence.attach(
              adapter,
              subject: subject_hex,
              kind: evidence.Test,
              verdict: verdict_of(r),
              payload:,
              ts: datetime.to_unix(datetime.now()),
            ))
          }
        }
      }
    }
  })
}

fn is_term_def(sd: SurfaceDef) -> Bool {
  case sd {
    SurfaceTermDef(_) -> True
    _ -> False
  }
}
