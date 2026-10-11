import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/identity.{Ref, hash_bytes, hash_to_debug_string}
import gleamunison/patch

fn ref_of(s: String) -> identity.DefinitionRef {
  Ref(hash_bytes(<<s:utf8>>))
}

fn int_def(n: Int) -> ast.Definition {
  ast.TermDef(term: ast.Int(n), typ: ast.Builtin(ast.IntType))
}

// caller = RefTo(callee) applied to 0
fn caller_def(callee: identity.DefinitionRef) -> ast.Definition {
  ast.TermDef(
    term: ast.Apply(ast.RefTo(callee), ast.Int(0)),
    typ: ast.Builtin(ast.IntType),
  )
}

pub fn patch_lookup_test() {
  let old = ref_of("old")
  let new = ref_of("new")
  let p = patch.new("fix-answer") |> patch.add(old, new)
  let assert Ok(found) = patch.lookup(p, old)
  let assert True = found == new
  let assert Error(Nil) = patch.lookup(p, ref_of("other"))
}

pub fn rewrite_term_replaces_refs_test() {
  let old = ref_of("callee-v1")
  let new = ref_of("callee-v2")
  let p = patch.new("p") |> patch.add(old, new)
  let term =
    ast.Apply(ast.RefTo(old), ast.Lambda(identity.Local(0), ast.RefTo(old)))
  let rewritten = patch.rewrite_term(p, term)
  let assert ast.Apply(ast.RefTo(r1), ast.Lambda(_, ast.RefTo(r2))) = rewritten
  let assert True = r1 == new
  let assert True = r2 == new
}

pub fn rewrite_touches_type_and_ctor_refs_test() {
  let old_t = ref_of("type-v1")
  let new_t = ref_of("type-v2")
  let p = patch.new("p") |> patch.add(old_t, new_t)
  let term = ast.Construct(old_t, [ast.Int(1)])
  let assert ast.Construct(r, _) = patch.rewrite_term(p, term)
  let assert True = r == new_t
}

pub fn dependents_finds_referrers_test() {
  // callee is stored under its content hash; caller references that hash
  let callee_def = int_def(42)
  let callee_ref = Ref(codebase.hash_of_definition(callee_def))
  let caller = caller_def(callee_ref)
  let caller_ref = Ref(codebase.hash_of_definition(caller))
  let defs = [#(callee_ref, callee_def), #(caller_ref, caller)]
  let assert [found] = patch.dependents(defs, callee_ref)
  let assert True = found == caller_ref
}

pub fn apply_propagates_and_rehashes_test() {
  // callee lives under its content hash
  let callee_def = int_def(42)
  let callee_ref = Ref(codebase.hash_of_definition(callee_def))
  // caller points at the callee's content hash
  let caller = caller_def(callee_ref)
  let caller_ref = Ref(codebase.hash_of_definition(caller))
  let defs = [#(callee_ref, callee_def), #(caller_ref, caller)]

  let new_callee_def = int_def(43)
  let new_callee_ref = Ref(codebase.hash_of_definition(new_callee_def))
  let p = patch.new("bump-callee") |> patch.add(callee_ref, new_callee_ref)

  let result = patch.apply_to_defs(p, defs)
  // The caller was rewritten to point at the new callee; its hash changed.
  let assert [rewrite] = result.rewritten
  let assert True = rewrite.old_ref == caller_ref
  let assert False = rewrite.new_ref == caller_ref
  // The rewritten caller references the NEW callee
  let assert ast.TermDef(ast.Apply(ast.RefTo(pointed), _), _) = rewrite.new_def
  let assert True = pointed == new_callee_ref
  // The callee itself was not rewritten (nothing inside it references old)
  let assert True = list.length(result.rewritten) == 1
}

pub fn patch_hash_is_content_addressed_test() {
  let a = ref_of("a")
  let b = ref_of("b")
  let p1 = patch.new("p") |> patch.add(a, b)
  let p2 = patch.new("p") |> patch.add(a, b)
  let p3 = patch.new("p") |> patch.add(b, a)
  let assert True = patch.hash_of(p1) == patch.hash_of(p2)
  let assert False = patch.hash_of(p1) == patch.hash_of(p3)
  let assert True = string.length(hash_to_debug_string(patch.hash_of(p1))) == 64
}
