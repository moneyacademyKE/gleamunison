import gleam/dict
import gleam/option
import gleamunison/ast.{Apply, Int, Lambda, LocalVarRef, TermDef, TypeVar}
import gleamunison/codebase.{hash_of_definition}
import gleamunison/compile.{module_name_for}
import gleamunison/identity.{
  Local, Ref, builtin_int_add, builtin_io_read_line, hash_bytes, hash_equal,
}
import gleamunison/inference.{infer_term}
import gleamunison/repl_eval
import gleamunison/types.{empty_cache}
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn hello_world_test() {
  let name = "Joe"
  let greeting = "Hello, " <> name <> "!"
  let assert "Hello, Joe!" = greeting
}

pub fn builtins_distinct_test() {
  let Ref(h1) = builtin_int_add()
  let Ref(h2) = builtin_io_read_line()
  let assert False = hash_equal(h1, h2)
}

pub fn hash_term_distinct_test() {
  let t1 = Lambda(binder: Local(0), body: LocalVarRef(Local(0)))
  let t2 = Apply(function: t1, arg: Int(42))
  let def1 = TermDef(term: t1, typ: TypeVar(0))
  let def2 = TermDef(term: t2, typ: TypeVar(0))
  let h1 = hash_of_definition(def1)
  let h2 = hash_of_definition(def2)
  let assert False = hash_equal(h1, h2)
}

pub fn hash_term_canonical_test() {
  let m1 = ast.Match(ast.Int(1), [ast.Case(ast.PatInt(1), ast.Int(42))])
  let m2 = ast.Match(ast.Int(1), [ast.Case(ast.PatInt(2), ast.Int(42))])
  let def1 = TermDef(m1, ast.Builtin(ast.IntType))
  let def2 = TermDef(m2, ast.Builtin(ast.IntType))
  let h1 = hash_of_definition(def1)
  let h2 = hash_of_definition(def2)
  let assert False = hash_equal(h1, h2)
}

pub fn type_inference_match_test() {
  let m = ast.Match(ast.Int(1), [ast.Case(ast.PatInt(1), ast.Int(42))])
  let assert Ok(ast.Builtin(ast.IntType)) = infer_term(m, empty_cache())
}

pub fn type_inference_do_test() {
  let ability_ref = Ref(hash_bytes(<<"console">>))
  let cache =
    types.TypeCache(
      entries: dict.from_list([
        #(
          ability_ref,
          types.CTAbility([
            types.OperationType(
              name: option.Some("print"),
              inputs: [ast.Builtin(ast.TextType)],
              output: ast.Builtin(ast.IntType),
            ),
          ]),
        ),
      ]),
    )
  let do_term = ast.Do(ability_ref, Local(0), [ast.Text(<<"hello">>)])
  let assert Ok(ast.Builtin(ast.IntType)) = infer_term(do_term, cache)
}

pub fn compiler_output_correctness_test() {
  let compiler = compile.new()
  let lam = Lambda(binder: Local(0), body: LocalVarRef(Local(0)))
  let def = TermDef(term: lam, typ: TypeVar(0))
  let ref = Ref(hash_bytes(<<"identity">>))
  let assert Ok(beam) = compile.compile_definition(compiler, def, ref)
  let mod_name = module_name_for(ref)
  let _ = repl_eval.unload_binary(mod_name)
  let assert Ok(Nil) = repl_eval.load_binary(mod_name, beam)
  let assert Ok(val) = repl_eval.eval_module(mod_name)
  let _ = repl_eval.unload_binary(mod_name)
  let assert True = val != ""
}
