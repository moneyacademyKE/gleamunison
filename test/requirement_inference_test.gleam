import gleam/list
import gleamunison/ast
import gleamunison/identity.{type DefinitionRef, Local, Ref, hash_bytes}
import gleamunison/inference.{infer_term}
import gleamunison/types.{empty_cache}

fn fake_ref(tag: String) -> DefinitionRef {
  Ref(hash_bytes(<<tag:utf8>>))
}

fn in_requirements(reqs: List(ast.ReqElement), ability: DefinitionRef) -> Bool {
  list.any(reqs, fn(r) {
    case r {
      ast.Concrete(ast.AbilityRef(decl: d)) -> d == ability
      _ -> False
    }
  })
}

pub fn pure_lambda_has_empty_requirements_test() {
  let cache = empty_cache()
  let term = ast.Lambda(binder: Local(0), body: ast.Int(1))
  let assert Ok(ast.Fn(_, _, ast.Required([]))) = infer_term(term, cache)
}

pub fn do_ability_appears_in_requirements_test() {
  let cache = empty_cache()
  let console = fake_ref("Console")
  let term =
    ast.Lambda(binder: Local(0), body: ast.Do(console, Local(0), [ast.Int(1)]))
  let assert Ok(ast.Fn(_, _, ast.Required(reqs))) = infer_term(term, cache)
  let assert True = in_requirements(reqs, console)
}

pub fn handled_ability_is_subtracted_test() {
  let cache = empty_cache()
  let console = fake_ref("Console")
  let term =
    ast.Lambda(
      binder: Local(0),
      body: ast.Handle(
        computation: ast.Do(console, Local(0), []),
        handler: ast.Int(0),
        ability: console,
      ),
    )
  let assert Ok(ast.Fn(_, _, ast.Required(reqs))) = infer_term(term, cache)
  let assert False = in_requirements(reqs, console)
}

pub fn other_ability_survives_handle_test() {
  let cache = empty_cache()
  let console = fake_ref("Console")
  let fs = fake_ref("FS")
  let term =
    ast.Lambda(
      binder: Local(0),
      body: ast.Handle(
        computation: ast.List([
          ast.Do(console, Local(0), []),
          ast.Do(fs, Local(0), []),
        ]),
        handler: ast.Int(0),
        ability: console,
      ),
    )
  let assert Ok(ast.Fn(_, _, ast.Required(reqs))) = infer_term(term, cache)
  let assert False = in_requirements(reqs, console)
  let assert True = in_requirements(reqs, fs)
}
