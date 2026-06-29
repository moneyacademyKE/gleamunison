import gleamunison/ast.{Apply, Int, RefTo, TermDef}
import gleamunison/compile
import gleamunison/identity.{Ref, hash_bytes, hash_from_bytes}
import gleamunison/repl_eval

pub fn jet_compilation_and_execution_test() {
  let compiler = compile.new()

  // 1. Define the jetted reference hash (123 padded to 256 bits)
  let bytes = <<0:224, 123:32>>
  let jet_ref = Ref(hash_from_bytes(bytes))
  let jet_mod = compile.module_name_for(jet_ref)

  // Pure representation of the fib function (the AST can be anything, e.g. Int(0), since it gets overridden by the jet)
  let jet_def = TermDef(term: Int(0), typ: ast.Builtin(ast.IntType))

  // 2. Compile the jet definition
  let assert Ok(jet_beam) =
    compile.compile_definition(compiler, jet_def, jet_ref)

  // 3. Load the jet module
  let _ = repl_eval.unload_binary(jet_mod)
  let assert Ok(Nil) = repl_eval.load_binary(jet_mod, jet_beam)

  // 4. Create a caller definition that applies the jetted fib to Int(10)
  // fib(10) = 55
  let caller_ref = Ref(hash_bytes(<<"caller_of_jet">>))
  let caller_mod = compile.module_name_for(caller_ref)
  let caller_term = Apply(function: RefTo(jet_ref), arg: Int(10))
  let caller_def = TermDef(term: caller_term, typ: ast.Builtin(ast.IntType))

  // 5. Compile the caller
  let assert Ok(caller_beam) =
    compile.compile_definition(compiler, caller_def, caller_ref)

  // 6. Load the caller module
  let _ = repl_eval.unload_binary(caller_mod)
  let assert Ok(Nil) = repl_eval.load_binary(caller_mod, caller_beam)

  // 7. Evaluate caller and assert we get the jetted fib(10) = 55
  let assert Ok(result) = repl_eval.eval_module(caller_mod)
  let assert "55" = result

  // Clean up
  let _ = repl_eval.unload_binary(jet_mod)
  let _ = repl_eval.unload_binary(caller_mod)
}
