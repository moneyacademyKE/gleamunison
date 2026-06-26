import gleeunit
import gleam/dict
import gleamunison/identity.{Local, Ref, builtin_int_add, builtin_io_read_line, hash_equal, hash_bytes}
import gleamunison/ast.{Apply, Int, Lambda, TermDef, TypeVar, Builtin, IntType, LocalVarRef, Fn, Required}
import gleamunison/codebase.{hash_of_definition}
import gleamunison/types.{empty_cache}
import gleamunison/inference.{infer_term}
import gleamunison/compile.{module_name_for}

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

pub fn module_name_prefix_test() {
  let ref1 = Ref(hash_bytes(<<"abc">>))
  let ref2 = Ref(hash_bytes(<<"def">>))
  let m1 = module_name_for(ref1)
  let m2 = module_name_for(ref2)
  let assert False = m1 == m2
}

pub fn infer_list_homogeneous_test() {
  let list_term = ast.List([Int(1), Int(2), Int(3)])
  let cache = empty_cache()
  let assert Ok(Builtin(ast.ListType)) = infer_term(list_term, cache)
}

pub fn infer_apply_multiarg_test() {
  let lam_typ = Fn([TypeVar(0), TypeVar(1)], TypeVar(0), Required([]))
  let ref = Ref(hash_bytes(<<"dummy">>))
  let cache = types.TypeCache(entries: dict.from_list([#(ref, types.CTTerm(lam_typ))]))
  let app = Apply(function: ast.RefTo(ref), arg: Int(42))
  let assert Ok(Fn([TypeVar(1)], Builtin(IntType), _)) = infer_term(app, cache)
}
