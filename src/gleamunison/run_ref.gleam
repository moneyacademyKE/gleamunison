//// Run a definition by content hash: the store is the program.
////
//// Resolve the dependency closure first, then load it, then execute. A ref
//// whose module is already in the runtime as a genesis builtin needs no store
//// entry, so a stored definition that adds two numbers does not have to carry
//// the definition of `+`.

import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/result
import gleamunison/ast
import gleamunison/codebase
import gleamunison/compile
import gleamunison/effect_evidence
import gleamunison/evidence
import gleamunison/identity.{type DefinitionRef}
import gleamunison/loader
import gleamunison/name_snapshot
import gleamunison/repl_eval
import gleamunison/run_closure
import gleamunison/run_error.{
  type RunError, ArityUnavailable, EvaluationFailed, LoadFailed, NoEvidence,
  NotExecutable, Unreadable, hex, read_error,
}
import gleamunison/storage
import gleamunison/trust
import gleamunison/turnstile
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
          case evidence.snapshot(adapter) {
            Error(_) -> Error(NoEvidence(ref, "evidence_unreadable"))
            Ok(snapshot) ->
              // The rule is the turnstile's, not a second opinion. `publish`
              // admits an effectful definition on a human `io` attestation,
              // because a suite cannot drive real IO. Asking only for `test`
              // here meant such a definition was admitted and then refused at
              // the moment it was run: the gate that lets content in and the
              // gate that executes it have to be the same rule.
              case
                turnstile.admits(
                  snapshot,
                  hex(ref),
                  definition_is_effectful(adapter, ref),
                  policy,
                )
              {
                True -> Ok(Nil)
                False ->
                  Error(NoEvidence(ref, refusal_for(snapshot, ref, policy)))
              }
          }
      }
  }
}

/// Name the refusal the way an operator can act on: which evidence is missing.
fn refusal_for(
  snapshot: evidence.Snapshot,
  ref: DefinitionRef,
  policy: trust.TrustPolicy,
) -> String {
  case trust.verified_in(snapshot, hex(ref), evidence.Test, policy) {
    Error(refusal) -> trust.refusal_name(refusal)
    Ok(_) -> "no_record:io"
  }
}

fn definition_is_effectful(
  adapter: storage.StorageAdapter,
  ref: DefinitionRef,
) -> Bool {
  case codebase.get(codebase.with_adapter(adapter), ref) {
    Ok(definition) -> effect_evidence.definition_is_effectful(definition)
    // Unreadable content is already refused by preflight; if it reaches here the
    // conservative answer is "pure", which demands test evidence.
    Error(_) -> False
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

fn run_raw_on_branch(
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
          use ld <- result.try(run_closure.resolve_definition(
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
      use ld <- result.try(run_closure.resolve_definition(
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
