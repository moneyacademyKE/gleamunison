import gleeunit
import gleamunison/identity.{Local, Ref, builtin_int_add, builtin_io_read_line, hash_equal}
import gleamunison/ast.{Apply, Int, Lambda, TermDef, TypeVar, Builtin, IntType, LocalVarRef}
import gleamunison/codebase.{hash_of_definition}
import gleamunison/types.{empty_cache}
import gleamunison/inference.{infer_term}

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

pub fn infer_lambda_test() {
  let lam = Lambda(binder: Local(0), body: Int(42))
  let cache = empty_cache()
  let assert Ok(ast.Fn([TypeVar(0)], Builtin(IntType), _)) = infer_term(lam, cache)
}

pub fn infer_apply_test() {
  let lam = Lambda(binder: Local(0), body: LocalVarRef(Local(0)))
  let app = Apply(function: lam, arg: Int(42))
  let cache = empty_cache()
  let assert Ok(Builtin(IntType)) = infer_term(app, cache)
}
