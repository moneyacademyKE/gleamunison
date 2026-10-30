import gleamunison/ast.{Apply, Int, Lambda, RefTo, TermDef}
import gleamunison/compile
import gleamunison/identity.{Local, Ref, hash_bytes, hash_from_bytes}
import gleamunison/loader_ffi
import gleeunit/should

pub fn stored_definition_wins_over_legacy_jet_hash_test() {
  let compiler = compile.new()

  // This hash belonged to the experimental Fibonacci jet. Its stored lambda,
  // not registry membership, must determine the module's behavior.
  let bytes = <<0:224, 123:32>>
  let stored_ref = Ref(hash_from_bytes(bytes))
  let stored_mod = compile.module_name_for(stored_ref)
  let stored_def =
    TermDef(
      term: Lambda(binder: Local(0), body: Int(42)),
      typ: ast.Fn(
        params: [ast.Builtin(ast.IntType)],
        result: ast.Builtin(ast.IntType),
        requires: ast.Required([]),
      ),
    )

  let assert Ok(stored_beam) =
    compile.compile_definition(compiler, stored_def, stored_ref)
  let _ = loader_ffi.unload_binary(stored_mod)
  let assert Ok(Nil) = loader_ffi.load_binary(stored_mod, stored_beam)

  let caller_ref = Ref(hash_bytes(<<"caller_of_stored_definition">>))
  let caller_mod = compile.module_name_for(caller_ref)
  let caller_term = Apply(function: RefTo(stored_ref), arg: Int(10))
  let caller_def = TermDef(term: caller_term, typ: ast.Builtin(ast.IntType))
  let assert Ok(caller_beam) =
    compile.compile_definition(compiler, caller_def, caller_ref)
  let _ = loader_ffi.unload_binary(caller_mod)
  let assert Ok(Nil) = loader_ffi.load_binary(caller_mod, caller_beam)

  let result = loader_ffi.eval_module(caller_mod)
  let _ = loader_ffi.unload_binary(stored_mod)
  let _ = loader_ffi.unload_binary(caller_mod)
  result |> should.equal(Ok("42"))
}
