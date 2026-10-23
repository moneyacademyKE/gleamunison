//// Run a definition by content hash: the store is the program.
////
//// Resolve the dependency closure first, then load it, then execute. A ref
//// whose module is already in the runtime (a genesis builtin, or a jet) needs
//// no store entry, so a stored definition that adds two numbers does not have
//// to carry the definition of `+`.

import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/compile
import gleamunison/definition_refs
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/jets
import gleamunison/loader
import gleamunison/namespace
import gleamunison/repl_eval
import gleamunison/storage
import gleamunison/types
import gleamunison/verify

@external(erlang, "gleamunison_repl_ffi", "call_eval")
fn call_eval_ffi(
  mod_name: String,
  args: List(Dynamic),
) -> Result(Dynamic, String)

@external(erlang, "gleamunison_ffi", "render_term")
fn render_term_ffi(term: Dynamic) -> String

const run_branch = "main"

pub type RunError {
  Missing(ref: DefinitionRef)
  Unreadable(ref: DefinitionRef, reason: String)
  NotExecutable(ref: DefinitionRef, kind: String)
  LoadFailed(ref: DefinitionRef, reason: String)
  Cycle(ref: DefinitionRef)
  ArityUnavailable(ref: DefinitionRef, expected: Int, supplied: Int)
  EvaluationFailed(ref: DefinitionRef, reason: String)
}

pub fn run(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
) -> Result(String, RunError) {
  let cb = codebase.with_adapter(adapter)
  use definition <- result.try(
    codebase.get(cb, ref)
    |> result.map_error(fn(error) { read_error(ref, error) }),
  )
  case definition {
    ast.TermDef(term: _, typ: typ) -> {
      // A function is a value: arity comes from the declared type, and calling
      // it is one apply per argument. Supplying the wrong count is refused
      // here, before any dependency work, so a value cannot be "called".
      let expected = arity_of(typ)
      let supplied = list.length(args)
      case expected == supplied {
        False -> Error(ArityUnavailable(ref, expected, supplied))
        True -> {
          // The baseline environment first: ability declarations and the
          // builtin names (`+`, `eq?`, ...) are forwarding modules the
          // elaborator references by name, exactly as the REPL and `verify`
          // establish them. Without it a stored definition that adds two
          // numbers looks like it depends on a missing definition.
          let _ =
            repl_eval.bootstrap_defs(
              verify.get_init_defs(),
              types.empty_cache(),
            )
          use ld <- result.try(
            resolve_definition(loader.new_loader(), cb, ref, definition, []),
          )
          let _ = ld
          call_eval_ffi(compile.module_name_for(ref), args)
          |> result.map(render_term_ffi)
          |> result.map_error(fn(reason) { EvaluationFailed(ref, reason) })
        }
      }
    }
    ast.TypeDef(_) -> Error(NotExecutable(ref, "a type definition"))
    ast.AbilityDecl(_) -> Error(NotExecutable(ref, "an ability declaration"))
  }
}

/// A definition's declared arity: parameters along the curried function chain.
/// The surface language curries `(define (f a b) ...)` into nested one-arg
/// lambdas, so `fn a b -> ...` types as `Fn([Int], Fn([Int], Int))`: arity is
/// the sum along the chain, not the top-level parameter count. Anything that
/// is not a function is a value, which takes no arguments.
pub fn arity_of(typ: ast.Type) -> Int {
  case typ {
    ast.Fn(params:, result:, ..) -> list.length(params) + arity_of(result)
    _ -> 0
  }
}

/// Load one ref and everything it points at, dependencies first: a compiled
/// module calls its dependencies by module name at run time.
fn resolve(
  ld: loader.Loader,
  cb: codebase.Codebase,
  ref: DefinitionRef,
  visiting: List(DefinitionRef),
) -> Result(loader.Loader, RunError) {
  case loader.is_loaded(ld, ref) || loader.module_available(ref) {
    True -> Ok(ld)
    False ->
      case jets.get_jet(ref) {
        option.Some(_) ->
          loader.ensure_loaded_jet(ld, ref)
          |> result.map_error(fn(pair) {
            LoadFailed(ref, describe_load(pair.1))
          })
        option.None -> {
          case codebase.get(cb, ref) {
            Ok(definition) ->
              resolve_definition(ld, cb, ref, definition, visiting)
            Error(codebase.NotFound(_)) ->
              // An elaborated term references its dependencies by
              // ref_for_name(name), not by content hash. Those refs live in the
              // branch namespace (name → content ref), the same table
              // `publish` and `pkg install` commit. The module is loaded under
              // the NAME ref so its module name matches what the caller emits.
              case resolve_name_ref(cb, ref) {
                Ok(definition) ->
                  resolve_definition(ld, cb, ref, definition, visiting)
                Error(_) -> Error(Missing(ref))
              }
            Error(other) -> Error(read_error(ref, other))
          }
        }
      }
  }
}

fn resolve_definition(
  ld: loader.Loader,
  cb: codebase.Codebase,
  ref: DefinitionRef,
  definition: ast.Definition,
  visiting: List(DefinitionRef),
) -> Result(loader.Loader, RunError) {
  case list.contains(visiting, ref) {
    // Content addressing makes this unreachable by construction: a definition
    // cannot hash its own hash. Reaching it means the store admitted content
    // that does not match its key.
    True -> Error(Cycle(ref))
    False -> {
      let visiting = [ref, ..visiting]
      use ld <- result.try(
        list.try_fold(
          definition_refs.refs_of_definition(definition),
          ld,
          fn(ld, dependency) { resolve(ld, cb, dependency, visiting) },
        ),
      )
      loader.ensure_loaded(ld, ref, definition)
      |> result.map_error(fn(pair) { LoadFailed(ref, describe_load(pair.1)) })
    }
  }
}

/// A name reference is sha256(name); the namespace binds that name to a content
/// ref. Finding the name means scanning the binding table, which is small and
/// loaded once per run.
fn resolve_name_ref(
  cb: codebase.Codebase,
  ref: DefinitionRef,
) -> Result(ast.Definition, Nil) {
  case namespace.load_current(codebase.get_adapter(cb), run_branch) {
    Error(_) -> Error(Nil)
    Ok(ns) ->
      list.find_map(namespace.names(ns), fn(name) {
        case repl_eval.ref_for_name(name) == ref {
          False -> Error(Nil)
          True ->
            case namespace.get(ns, name) {
              Error(_) -> Error(Nil)
              Ok(content_ref) ->
                codebase.get(cb, content_ref)
                |> result.map_error(fn(_) { Nil })
            }
        }
      })
  }
}

fn read_error(ref: DefinitionRef, error: codebase.ReadError) -> RunError {
  case error {
    codebase.NotFound(_) -> Missing(ref)
    codebase.StoreFailure(reason) -> Unreadable(ref, string.inspect(reason))
    codebase.Corrupt(_, reason) ->
      Unreadable(ref, "content does not match its ref: " <> reason)
    codebase.DecodeFailed(_, reason) ->
      Unreadable(ref, "payload is not a definition: " <> reason)
  }
}

fn describe_load(error: loader.LoaderError) -> String {
  case error {
    loader.CompileFailed(_, message) -> "compile failed: " <> message
    loader.LoadFailed(_, message) -> "load failed: " <> message
  }
}

pub fn hex(ref: DefinitionRef) -> String {
  let Ref(hash) = ref
  hash_to_debug_string(hash)
}

pub fn describe(error: RunError) -> String {
  case error {
    Missing(ref) ->
      "not in the store: " <> hex(ref) <> " (publish it or sync it first)"
    Unreadable(ref, reason) -> "cannot read " <> hex(ref) <> ": " <> reason
    NotExecutable(ref, kind) ->
      hex(ref) <> " is " <> kind <> ", not a runnable term"
    LoadFailed(ref, reason) -> "cannot load " <> hex(ref) <> ": " <> reason
    Cycle(ref) ->
      "dependency cycle at "
      <> hex(ref)
      <> "; the store disagrees with its refs"
    ArityUnavailable(ref, expected, supplied) ->
      hex(ref)
      <> " expects "
      <> int.to_string(expected)
      <> " argument(s), got "
      <> int.to_string(supplied)
    EvaluationFailed(ref, reason) ->
      "evaluation of " <> hex(ref) <> " failed: " <> reason
  }
}
