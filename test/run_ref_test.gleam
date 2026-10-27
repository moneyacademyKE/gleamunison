//// Run by hash: resolve the closure, load it, execute it. These tests use an
//// in-memory store, which is the same adapter contract dets satisfies.

import gleam/dynamic.{type Dynamic}
import gleam/string
import gleamunison/ast
import gleamunison/bootstrap_types
import gleamunison/codebase
import gleamunison/genesis
import gleamunison/identity.{type DefinitionRef, Local, Ref, hash_bytes}
import gleamunison/namespace
import gleamunison/repl_eval
import gleamunison/run_error
import gleamunison/run_ref
import gleeunit/should

fn insert(
  cb: codebase.Codebase,
  definition: ast.Definition,
) -> #(codebase.Codebase, DefinitionRef) {
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(cb) =
    codebase.insert(cb, ast.Unit(root: ref, defs: [#(ref, definition)]))
  #(cb, ref)
}

fn int_fn_returning(value: Int) -> ast.Definition {
  ast.TermDef(
    term: ast.Lambda(binder: Local(0), body: ast.Int(value)),
    typ: ast.Fn(
      params: [ast.Builtin(ast.IntType)],
      result: ast.Builtin(ast.IntType),
      requires: ast.Required([]),
    ),
  )
}

pub fn a_stored_dependency_resolves_and_executes_test() {
  let #(cb, dep_ref) = insert(codebase.empty(), int_fn_returning(7))
  let main =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(dep_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(cb, main)
  run_ref.run(codebase.get_adapter(cb), main_ref, []) |> should.equal(Ok("7"))
}

pub fn a_genesis_builtin_needs_no_store_entry_test() {
  let main =
    ast.TermDef(
      term: ast.Apply(
        function: ast.Apply(
          function: ast.RefTo(genesis.builtin_int_add()),
          arg: ast.Int(1),
        ),
        arg: ast.Int(2),
      ),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(codebase.empty(), main)
  run_ref.run(codebase.get_adapter(cb), main_ref, []) |> should.equal(Ok("3"))
}

/// The shape production actually emits. `a_genesis_builtin_needs_no_store_entry_test`
/// builds the AST with `genesis.builtin_int_add()`, but the elaborator wires a
/// dependency as `ref_for_name(name)` (sha256 of the name), never as the
/// synthetic genesis ref. A test that only ever used the genesis ref proved a
/// shape the compiler cannot produce, and hid the regression where `run` on a
/// published definition could not resolve `+` at all.
pub fn a_builtin_reached_by_name_ref_needs_no_store_entry_test() {
  let plus = repl_eval.ref_for_name("+")
  let main =
    ast.TermDef(
      term: ast.Apply(
        function: ast.Apply(function: ast.RefTo(plus), arg: ast.Int(1)),
        arg: ast.Int(2),
      ),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(codebase.empty(), main)
  run_ref.run(codebase.get_adapter(cb), main_ref, []) |> should.equal(Ok("3"))
}

pub fn a_stored_process_round_trip_uses_genesis_builtins_test() {
  let self_ref = repl_eval.ref_for_name("self")
  let send_ref = repl_eval.ref_for_name("send")
  let recv_ref = repl_eval.ref_for_name("recv")
  let main =
    ast.TermDef(
      term: ast.Let(
        binder: Local(0),
        value: ast.Apply(
          function: ast.Apply(
            function: ast.RefTo(send_ref),
            arg: ast.RefTo(self_ref),
          ),
          arg: ast.Text(<<"jet-removal:stored-round-trip">>),
        ),
        body: ast.RefTo(recv_ref),
      ),
      typ: bootstrap_types.host_value(),
    )
  let #(cb, main_ref) = insert(codebase.empty(), main)
  run_ref.run(codebase.get_adapter(cb), main_ref, [])
  |> should.equal(Ok("<<\"jet-removal:stored-round-trip\">>"))
}

pub fn a_missing_dependency_names_the_ref_test() {
  let absent = Ref(hash_bytes(<<"absent-dependency">>))
  let main =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(absent), arg: ast.Int(1)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(codebase.empty(), main)
  let assert Error(run_error.Missing(got)) =
    run_ref.run(codebase.get_adapter(cb), main_ref, [])
  got |> should.equal(absent)
}

pub fn a_name_reference_resolves_through_the_namespace_test() {
  // Elaborated terms reference dependencies by ref_for_name(name), not by
  // content hash. The namespace binds the name to the content ref; the module
  // is then loaded under the name ref so the caller's module name matches.
  let #(cb, dep_ref) = insert(codebase.empty(), int_fn_returning(9))
  let name_ref = repl_eval.ref_for_name("dep")
  let main =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(name_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(cb, main)
  let adapter = codebase.get_adapter(cb)
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "dep", dep_ref),
    )
  run_ref.run(adapter, main_ref, []) |> should.equal(Ok("9"))
}

pub fn a_name_reference_uses_the_selected_branch_without_fallback_test() {
  let #(cb, release_dep_ref) = insert(codebase.empty(), int_fn_returning(12))
  let #(cb, main_dep_ref) = insert(cb, int_fn_returning(13))
  let name_ref = repl_eval.ref_for_name("release-dep")
  let main =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(name_ref), arg: ast.Int(0)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(cb, main)
  let adapter = codebase.get_adapter(cb)
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "release",
      namespace.set(namespace.empty(), "release-dep", release_dep_ref),
    )
  run_ref.run_on_branch(adapter, main_ref, "release", [])
  |> should.equal(Ok("12"))
  let assert Ok(_) =
    namespace.commit(
      adapter,
      "main",
      namespace.set(namespace.empty(), "release-dep", main_dep_ref),
    )
  run_ref.run_on_branch(adapter, main_ref, "release", [])
  |> should.equal(Ok("12"))
  run_ref.run_on_branch(adapter, main_ref, "main", [])
  |> should.equal(Ok("13"))
}

pub fn a_name_reference_without_a_binding_is_missing_test() {
  let name_ref = repl_eval.ref_for_name("unbound")
  let main =
    ast.TermDef(
      term: ast.Apply(function: ast.RefTo(name_ref), arg: ast.Int(1)),
      typ: ast.Builtin(ast.IntType),
    )
  let #(cb, main_ref) = insert(codebase.empty(), main)
  let assert Error(run_error.Missing(got)) =
    run_ref.run(codebase.get_adapter(cb), main_ref, [])
  got |> should.equal(name_ref)
}

pub fn an_absent_root_ref_is_missing_test() {
  let absent = Ref(hash_bytes(<<"absent-root">>))
  let assert Error(run_error.Missing(got)) =
    run_ref.run(codebase.get_adapter(codebase.empty()), absent, [])
  got |> should.equal(absent)
}

pub fn a_type_definition_refuses_to_execute_test() {
  let definition = ast.TypeDef(ast.Structural(Local(0), [], []))
  let #(cb, ref) = insert(codebase.empty(), definition)
  let assert Error(run_error.NotExecutable(got, _)) =
    run_ref.run(codebase.get_adapter(cb), ref, [])
  got |> should.equal(ref)
}

pub fn absence_is_reported_before_evidence_test() {
  // Ordering matters for exit codes: an absent definition is absent (2), not
  // unverified (1). The gate must not mask a missing ref behind a policy
  // failure, which it would if evidence were checked first.
  let absent = Ref(hash_bytes(<<"absent-before-evidence">>))
  let assert Error(run_error.Missing(got)) =
    run_ref.run_verified(
      codebase.get_adapter(codebase.empty()),
      absent,
      [],
      False,
    )
  got |> should.equal(absent)
}

pub fn raw_absence_is_reported_before_evidence_test() {
  let absent = Ref(hash_bytes(<<"absent-before-evidence-raw">>))
  let assert Error(run_error.Missing(got)) =
    run_ref.run_verified_raw(
      codebase.get_adapter(codebase.empty()),
      absent,
      [],
      False,
    )
  got |> should.equal(absent)
}

pub fn the_escape_hatch_runs_stored_content_test() {
  let definition = ast.TermDef(term: ast.Int(11), typ: ast.Builtin(ast.IntType))
  let #(cb, ref) = insert(codebase.empty(), definition)
  run_ref.run_verified(codebase.get_adapter(cb), ref, [], True)
  |> should.equal(Ok("11"))
}

// --- the run gate reports WHY it refused ------------------------------------

fn int_value(n: Int) -> ast.Definition {
  ast.TermDef(term: ast.Int(n), typ: ast.Builtin(ast.IntType))
}

/// The gate refuses before executing, and says what is missing. With no signing
/// key configured there is no policy to enforce, and the message names the
/// variable an operator has to set rather than a bare "not verified".
pub fn run_gate_refuses_and_names_the_reason_test() {
  let #(cb, ref) = insert(codebase.empty(), int_value(7))
  let assert Error(error) =
    run_ref.run_verified(codebase.get_adapter(cb), ref, [], False)
  run_error.describe(error)
  |> string.contains("GLEAMUNISON_EVIDENCE_SIGNING_KEY")
  |> should.be_true
}

/// The escape hatch is explicit, and only then does unevidenced content run.
pub fn run_gate_is_skipped_only_when_explicitly_allowed_test() {
  let #(cb, ref) = insert(codebase.empty(), int_value(7))
  run_ref.run_verified(codebase.get_adapter(cb), ref, [], True)
  |> should.equal(Ok("7"))
}

// --- an effect inside an APPLIED function runs ------------------------------
//
// `run <hash> <arg>` applies the stored closure one argument at a time. The
// baseline handler frames were installed around `'$eval'()` — which only
// *builds* the closure — and popped before the fold that applies the
// arguments, so an effectful function was admitted by the turnstile and then
// died with `ability m_74eafa15 (operation 0) is not handled here`. The
// zero-argument case passed, which is why the hole survived.
pub fn an_effectful_function_runs_with_its_argument_test() {
  let console = repl_eval.ref_for_name("Console")
  let def =
    ast.TermDef(
      term: ast.Lambda(
        binder: Local(0),
        body: ast.Do(console, Local(0), [ast.Text(<<"probe">>)]),
      ),
      typ: ast.Fn(
        params: [ast.Builtin(ast.TextType)],
        result: ast.Builtin(ast.IntType),
        requires: ast.Required([]),
      ),
    )
  let #(cb, ref) = insert(codebase.empty(), def)
  run_ref.run(codebase.get_adapter(cb), ref, [text_arg(<<"probe">>)])
  |> should.equal(Ok("0"))
}

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn text_arg(value: BitArray) -> Dynamic
