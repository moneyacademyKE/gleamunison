import gleam/dict
import gleamunison/identity.{Local, Ref, hash_bytes}
import gleamunison/ast
import gleamunison/elab_types.{TVar}
import gleamunison/lower.{lower_type_ref}
import gleamunison/typecheck
import gleamunison/types
import gleamunison/codebase.{hash_of_definition}
import gleamunison/loader.{new_loader, ensure_loaded}
import gleamunison/compile.{new as new_compiler, compile_definition}

pub fn typecheck_alpha_equivalence_test() {
  let cache = types.empty_cache()
  let ref = Ref(hash_bytes(<<"ref">>))
  let t2 = ast.Fn([ast.TypeVar(1)], ast.TypeVar(1), ast.Required([]))
  let unit1 = ast.Unit(
    root: ref,
    defs: [#(ref, ast.TermDef(term: ast.Lambda(binder: Local(0), body: ast.LocalVarRef(Local(0))), typ: t2))]
  )
  let assert Ok(#(_, _)) = typecheck.typecheck_unit(unit1, cache)
}

pub fn tvar_sequential_lowering_test() {
  let vars = dict.new()
  let assert Ok(#(ast.TypeRefVar(Local(0)), vars2)) = lower_type_ref(TVar("a"), vars)
  let assert Ok(#(ast.TypeRefVar(Local(1)), _)) = lower_type_ref(TVar("b"), vars2)
}

pub fn loader_memoization_and_details_test() {
  let ld = new_loader()
  let ref = Ref(hash_bytes(<<"failing_def">>))
  let def = ast.TermDef(term: ast.LocalVarRef(Local(123)), typ: ast.Builtin(ast.IntType))
  let assert Error(#(ld2, loader.CompileFailed(_, _))) = ensure_loaded(ld, ref, def)
  let assert Error(#(_, loader.CompileFailed(_, _))) = ensure_loaded(ld2, ref, def)
}

pub fn structural_hashing_round4_test() {
  let t1 = ast.TermDef(ast.Int(42), ast.Builtin(ast.IntType))
  let t2 = ast.TermDef(ast.Match(ast.Int(42), []), ast.Builtin(ast.IntType))
  let assert False = identity.hash_equal(hash_of_definition(t1), hash_of_definition(t2))
}

pub fn compile_and_evaluate_handle_test() {
  let compiler = new_compiler()
  let ability_ref = Ref(hash_bytes(<<"myability">>))
  let do_term = ast.Do(ability_ref, Local(0), [ast.Int(42)])
  let compiled = compile_definition(compiler, ast.TermDef(ast.Handle(do_term, ast.Int(100), ability_ref), ast.TypeVar(0)), Ref(hash_bytes(<<"test_handle_mod">>)))
  let assert Ok(_) = compiled
}
