//// Run a definition by content hash: the store is the program.
////
//// Resolve the dependency closure first, then load it, then execute. A ref
//// whose module is already in the runtime (a genesis builtin, or a jet) needs
//// no store entry, so a stored definition that adds two numbers does not have
//// to carry the definition of `+`.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/ast
import gleamunison/bootstraps
import gleamunison/codebase
import gleamunison/compile
import gleamunison/definition_refs
import gleamunison/evidence
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/jets
import gleamunison/loader
import gleamunison/name_snapshot
import gleamunison/repl_eval
import gleamunison/storage
import gleamunison/trust
import gleamunison/types
import gleamunison/verify

@external(erlang, "gleamunison_repl_ffi", "call_eval")
fn call_eval_ffi(
  mod_name: String,
  args: List(Dynamic),
) -> Result(Dynamic, String)

@external(erlang, "gleamunison_ffi", "render_term")
fn render_term_ffi(term: Dynamic) -> String

const default_branch = "main"

pub type RunError {
  Missing(ref: DefinitionRef)
  Unreadable(ref: DefinitionRef, reason: String)
  NotExecutable(ref: DefinitionRef, kind: String)
  LoadFailed(ref: DefinitionRef, reason: String)
  Cycle(ref: DefinitionRef)
  ArityUnavailable(ref: DefinitionRef, expected: Int, supplied: Int)
  NoEvidence(ref: DefinitionRef, reason: String)
  EvaluationFailed(ref: DefinitionRef, reason: String)
}

/// Execute with the evidence gate on. A definition runs only when a verified
/// Test record covers its content hash — the same turnstile `publish` passes,
/// checked again at the moment of execution because a store can be filled by
/// `sync` or `pkg install` long after admission. `allow_unverified` is the
/// explicit escape hatch for local stores; the caller warns on stderr.
///
/// Existence is settled first: an absent definition is absent, not unverified,
/// and a caller reading exit codes must be able to tell the two apart.
pub fn run_verified(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
  allow_unverified: Bool,
) -> Result(String, RunError) {
  run_verified_on_branch(adapter, ref, default_branch, args, allow_unverified)
}

pub fn run_verified_on_branch(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  branch: String,
  args: List(Dynamic),
  allow_unverified: Bool,
) -> Result(String, RunError) {
  use _ <- result.try(preflight(adapter, ref))
  use _ <- result.try(evidence_gate(adapter, ref, allow_unverified))
  run_on_branch(adapter, ref, branch, args)
}

/// The same gate, returning the raw term for a caller that renders it itself.
pub fn run_verified_raw(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
  allow_unverified: Bool,
) -> Result(Dynamic, RunError) {
  run_verified_raw_on_branch(
    adapter,
    ref,
    default_branch,
    args,
    allow_unverified,
  )
}

pub fn run_verified_raw_on_branch(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  branch: String,
  args: List(Dynamic),
  allow_unverified: Bool,
) -> Result(Dynamic, RunError) {
  use _ <- result.try(preflight(adapter, ref))
  use _ <- result.try(evidence_gate(adapter, ref, allow_unverified))
  execute(adapter, ref, branch, args)
}

fn preflight(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
) -> Result(Nil, RunError) {
  let cb = codebase.with_adapter(adapter)
  codebase.get(cb, ref)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(error) { read_error(ref, error) })
}

fn evidence_gate(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  allow_unverified: Bool,
) -> Result(Nil, RunError) {
  case allow_unverified {
    True -> Ok(Nil)
    False ->
      case trust.production_policy() {
        Error(reason) -> Error(NoEvidence(ref, reason))
        Ok(policy) ->
          case trust.verified(adapter, hex(ref), evidence.Test, policy) {
            Ok(_) -> Ok(Nil)
            Error(refusal) ->
              Error(NoEvidence(ref, trust.refusal_name(refusal)))
          }
      }
  }
}

/// The CLI-facing text form: execute, then render the way the REPL does.
pub fn run(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
) -> Result(String, RunError) {
  run_on_branch(adapter, ref, default_branch, args)
}

pub fn run_on_branch(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  branch: String,
  args: List(Dynamic),
) -> Result(String, RunError) {
  use term <- result.try(execute(adapter, ref, branch, args))
  Ok(render_term_ffi(term))
}

pub fn run_raw(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  args: List(Dynamic),
) -> Result(Dynamic, RunError) {
  run_raw_on_branch(adapter, ref, default_branch, args)
}

pub fn run_raw_on_branch(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  branch: String,
  args: List(Dynamic),
) -> Result(Dynamic, RunError) {
  execute(adapter, ref, branch, args)
}

fn execute(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  branch: String,
  args: List(Dynamic),
) -> Result(Dynamic, RunError) {
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
          use names <- result.try(
            name_snapshot.read(adapter, branch)
            |> result.map_error(fn(reason) { Unreadable(ref, reason) }),
          )
          use ld <- result.try(resolve_definition(
            loader.new_loader(),
            cb,
            ref,
            definition,
            [],
            names,
          ))
          let _ = ld
          call_eval_ffi(compile.module_name_for(ref), args)
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
  names: name_snapshot.Bindings,
) -> Result(loader.Loader, RunError) {
  case loader.is_loaded(ld, ref) {
    True -> Ok(ld)
    False ->
      case codebase.get(cb, ref) {
        Ok(definition) ->
          resolve_definition(ld, cb, ref, definition, visiting, names)
        Error(codebase.NotFound(_)) ->
          // Resolve the selected branch before consulting the VM module table.
          case dict.get(names, ref) {
            Ok(content_ref) -> {
              use definition <- result.try(
                codebase.get(cb, content_ref)
                |> result.map_error(fn(error) { read_error(content_ref, error) }),
              )
              resolve_definition(ld, cb, ref, definition, visiting, names)
            }
            Error(_) -> resolve_runtime_ref(ld, ref)
          }
        Error(other) -> Error(read_error(ref, other))
      }
  }
}

fn is_bootstrap_ref(ref: DefinitionRef) -> Bool {
  list.any(bootstraps.get_init_defs_data(), fn(definition) {
    case definition {
      bootstraps.BAbility(name, _) -> repl_eval.ref_for_name(name) == ref
      bootstraps.BTerm(_, known_ref) -> known_ref == ref
    }
  })
}

fn resolve_runtime_ref(
  ld: loader.Loader,
  ref: DefinitionRef,
) -> Result(loader.Loader, RunError) {
  case jets.get_jet(ref) {
    option.Some(_) ->
      loader.ensure_loaded_jet(ld, ref)
      |> result.map_error(fn(pair) { LoadFailed(ref, describe_load(pair.1)) })
    option.None ->
      case is_bootstrap_ref(ref) && loader.module_available(ref) {
        True -> Ok(ld)
        False -> Error(Missing(ref))
      }
  }
}

fn resolve_definition(
  ld: loader.Loader,
  cb: codebase.Codebase,
  ref: DefinitionRef,
  definition: ast.Definition,
  visiting: List(DefinitionRef),
  names: name_snapshot.Bindings,
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
          fn(ld, dependency) { resolve(ld, cb, dependency, visiting, names) },
        ),
      )
      loader.ensure_loaded(ld, ref, definition)
      |> result.map_error(fn(pair) { LoadFailed(ref, describe_load(pair.1)) })
    }
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
      case supplied == 0 {
        True ->
          hex(ref)
          <> " is a function of arity "
          <> int.to_string(expected)
          <> "; pass "
          <> int.to_string(expected)
          <> " argument(s), or inspect it without calling"
        False ->
          hex(ref)
          <> " expects "
          <> int.to_string(expected)
          <> " argument(s), got "
          <> int.to_string(supplied)
      }
    NoEvidence(ref, reason) -> hex(ref) <> " is not verified: " <> reason
    EvaluationFailed(ref, reason) ->
      "evaluation of " <> hex(ref) <> " failed: " <> reason
  }
}

/// The declared arity of a stored definition, without executing it. Used by
/// `run --json` to report a function instead of calling it.
pub fn declared_arity(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
) -> Result(Int, RunError) {
  let cb = codebase.with_adapter(adapter)
  use definition <- result.try(
    codebase.get(cb, ref)
    |> result.map_error(fn(error) { read_error(ref, error) }),
  )
  case definition {
    ast.TermDef(typ: typ, ..) -> Ok(arity_of(typ))
    ast.TypeDef(_) -> Error(NotExecutable(ref, "a type definition"))
    ast.AbilityDecl(_) -> Error(NotExecutable(ref, "an ability declaration"))
  }
}

pub type FunctionInfo {
  FunctionInfo(module: String, arity: Int, exports: List(#(String, Int)))
}

/// What a stored function is, without calling it: the compiled module, the
/// declared arity, and the export table it actually loaded with. The closure
/// is loaded (dependencies first) because the export table only exists once
/// the module is in the runtime — but `'$eval'` is never applied, so this is
/// inspection, not execution.
pub fn inspect_function(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
) -> Result(FunctionInfo, RunError) {
  inspect_function_on_branch(adapter, ref, default_branch)
}

pub fn inspect_function_on_branch(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
  branch: String,
) -> Result(FunctionInfo, RunError) {
  let cb = codebase.with_adapter(adapter)
  use definition <- result.try(
    codebase.get(cb, ref)
    |> result.map_error(fn(error) { read_error(ref, error) }),
  )
  case definition {
    ast.TermDef(typ: typ, ..) -> {
      let _ =
        repl_eval.bootstrap_defs(verify.get_init_defs(), types.empty_cache())
      use names <- result.try(
        name_snapshot.read(adapter, branch)
        |> result.map_error(fn(reason) { Unreadable(ref, reason) }),
      )
      use ld <- result.try(resolve_definition(
        loader.new_loader(),
        cb,
        ref,
        definition,
        [],
        names,
      ))
      let _ = ld
      use exports <- result.try(
        loader.exports(ref)
        |> result.map_error(fn(reason) { LoadFailed(ref, reason) }),
      )
      Ok(FunctionInfo(
        module: compile.module_name_for(ref),
        arity: arity_of(typ),
        exports: exports,
      ))
    }
    ast.TypeDef(_) -> Error(NotExecutable(ref, "a type definition"))
    ast.AbilityDecl(_) -> Error(NotExecutable(ref, "an ability declaration"))
  }
}
