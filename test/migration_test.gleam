import gleamunison/ast
import gleamunison/compile
import gleamunison/identity.{Ref, hash_bytes}
import gleamunison/repl_eval

pub fn live_process_migration_test() {
  let compiler = compile.new()
  // Define a simple term: Int(42)
  // We'll compile it under a unique ref
  let ref = Ref(hash_bytes(<<"migration_test_ref">>))
  let mod_name = compile.module_name_for(ref)
  let term = ast.Int(42)
  let def = ast.TermDef(term: term, typ: ast.Builtin(ast.IntType))

  // 1. Compile to BEAM binary
  let assert Ok(beam) = compile.compile_definition(compiler, def, ref)

  // 2. Load it
  let _ = repl_eval.unload_binary(mod_name)
  let assert Ok(Nil) = repl_eval.load_binary(mod_name, beam)

  // 3. Create a closure that evaluates to calling the module
  // In Erlang FFI, we can just call it via '$eval'
  let assert Ok(res_str) = repl_eval.eval_module(mod_name)
  let assert "42" = res_str

  // 4. Unload the module (simulating remote node not having the code yet)
  let assert Ok(Nil) = repl_eval.unload_binary(mod_name)

  // 5. Verify it fails now (module is unloaded)
  let assert Error(_) = repl_eval.eval_module(mod_name)

  // 6. Reload the module (simulating pull sync code shipping)
  let assert Ok(Nil) = repl_eval.load_binary(mod_name, beam)

  // 7. Verify execution succeeds again
  let assert Ok("42") = repl_eval.eval_module(mod_name)

  // Clean up
  let _ = repl_eval.unload_binary(mod_name)
}
