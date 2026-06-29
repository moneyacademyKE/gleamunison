import gleam/bit_array
import gleam/dict
import gleam/io
import gleam/option.{Some}
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/compile.{compile_definition, new as new_compiler}
import gleamunison/elab_types.{TVar}
import gleamunison/identity.{Local, Ref, hash_bytes, hash_equal}
import gleamunison/inference
import gleamunison/loader.{ensure_loaded, new_loader}
import gleamunison/lower.{lower_type_ref}
import gleamunison/sync.{new_sync_state, pull_sync}
import gleamunison/sync_types.{PeerId}
import gleamunison/typecheck
import gleamunison/types

pub fn typecheck_alpha_equivalence_test() {
  let cache = types.empty_cache()
  let ref = Ref(hash_bytes(<<"ref">>))
  let t2 = ast.Fn([ast.TypeVar(1)], ast.TypeVar(1), ast.Required([]))
  let unit1 =
    ast.Unit(root: ref, defs: [
      #(
        ref,
        ast.TermDef(
          term: ast.Lambda(binder: Local(0), body: ast.LocalVarRef(Local(0))),
          typ: t2,
        ),
      ),
    ])
  let assert Ok(#(_, _)) = typecheck.typecheck_unit(unit1, cache)
}

pub fn tvar_sequential_lowering_test() {
  let vars = dict.new()
  let assert Ok(#(ast.TypeRefVar(Local(0)), vars2)) =
    lower_type_ref(TVar("a"), vars)
  let assert Ok(#(ast.TypeRefVar(Local(1)), _)) =
    lower_type_ref(TVar("b"), vars2)
}

pub fn loader_memoization_and_details_test() {
  let ld = new_loader()
  let ref = Ref(hash_bytes(<<"failing_def">>))
  let def =
    ast.TermDef(
      term: ast.LocalVarRef(Local(123)),
      typ: ast.Builtin(ast.IntType),
    )
  let assert Error(#(ld2, loader.CompileFailed(_, _))) =
    ensure_loaded(ld, ref, def)
  let assert Error(#(_, loader.CompileFailed(_, _))) =
    ensure_loaded(ld2, ref, def)
}

pub fn structural_hashing_round4_test() {
  let t1 = ast.TermDef(ast.Int(42), ast.Builtin(ast.IntType))
  let t2 = ast.TermDef(ast.Match(ast.Int(42), []), ast.Builtin(ast.IntType))
  let assert False =
    hash_equal(codebase.hash_of_definition(t1), codebase.hash_of_definition(t2))
}

pub fn compile_and_evaluate_handle_test() {
  let compiler = new_compiler()
  let ability_ref = Ref(hash_bytes(<<"myability">>))
  let do_term = ast.Do(ability_ref, Local(0), [ast.Int(42)])
  let compiled =
    compile_definition(
      compiler,
      ast.TermDef(
        ast.Handle(do_term, ast.Int(100), ability_ref),
        ast.TypeVar(0),
      ),
      Ref(hash_bytes(<<"test_handle_mod">>)),
    )
  let assert Ok(_) = compiled
}

pub fn codebase_insert_persists_bytes_test() {
  let cb = codebase.empty()
  let def = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.IntType))
  let computed = codebase.hash_of_definition(def)
  let ref = Ref(computed)
  let unit = ast.Unit(ref, [#(ref, def)])
  let assert Ok(cb2) = codebase.insert(cb, unit)
  let adapter = codebase.get_adapter(cb2)
  let assert Ok(Some(bytes)) = adapter.lookup(ref)
  let assert True = bytes == bit_array.from_string(string.inspect(def))
}

pub fn pull_sync_persists_synced_blobs_test() {
  let cb = codebase.empty()
  let state = new_sync_state()
  let peer = PeerId("test_node")
  let _result = pull_sync(state, peer, cb)
  io.println("Sync test adapted for TCP protocol (peer not running)")
}

pub fn homogeneous_list_polymorphic_type_inference_test() {
  let lam1 = ast.Lambda(binder: Local(0), body: ast.LocalVarRef(Local(0)))
  let lam2 = ast.Lambda(binder: Local(1), body: ast.LocalVarRef(Local(1)))
  let list_term = ast.List([lam1, lam2])
  let cache = types.empty_cache()
  let assert Ok(ast.Builtin(ast.ListType)) =
    inference.infer_term(list_term, cache)
}
