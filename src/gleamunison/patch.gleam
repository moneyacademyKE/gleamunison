//// Named update-propagation patches (Unison's `patch` entity, our shape).
////
//// A patch is a named, content-addressed set of replacements
//// old-ref → new-ref. Applying it rewrites every definition that
//// references a replaced ref and re-hashes the result: the "rewrite
//// dependents" wave, as data. Iterating to a fixpoint is the cascade.

import gleam/bit_array
import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/identity.{
  type DefinitionRef, type Hash, Ref, hash_bytes, hash_to_debug_string,
}

pub type Patch {
  Patch(name: String, replacements: List(#(DefinitionRef, DefinitionRef)))
}

pub type Rewrite {
  Rewrite(
    old_ref: DefinitionRef,
    new_ref: DefinitionRef,
    new_def: ast.Definition,
  )
}

pub type ApplyResult {
  ApplyResult(patch: Patch, rewritten: List(Rewrite))
}

pub fn new(name: String) -> Patch {
  Patch(name: name, replacements: [])
}

pub fn add(p: Patch, old: DefinitionRef, new_ref: DefinitionRef) -> Patch {
  Patch(..p, replacements: list.append(p.replacements, [#(old, new_ref)]))
}

pub fn lookup(p: Patch, ref: DefinitionRef) -> Result(DefinitionRef, Nil) {
  list.key_find(p.replacements, ref)
}

/// The patch is itself content-addressed: same replacements, same hash.
pub fn hash_of(p: Patch) -> Hash {
  let body =
    p.replacements
    |> list.map(fn(pair) {
      hash_to_debug_string(ref_hash(pair.0))
      <> "->"
      <> hash_to_debug_string(ref_hash(pair.1))
    })
    |> string.join(",")
  hash_bytes(bit_array.from_string("patch:" <> p.name <> ":" <> body))
}

fn ref_hash(r: DefinitionRef) -> Hash {
  let Ref(h) = r
  h
}

/// Which of these definitions reference `target`?
pub fn dependents(
  defs: List(#(DefinitionRef, ast.Definition)),
  target: DefinitionRef,
) -> List(DefinitionRef) {
  defs
  |> list.filter(fn(pair) { references_ref(pair.1, target) })
  |> list.map(fn(pair) { pair.0 })
}

/// One propagation wave: rewrite every definition that references a
/// replaced ref, re-hash each result. Idempotent for untouched defs.
pub fn apply_to_defs(
  p: Patch,
  defs: List(#(DefinitionRef, ast.Definition)),
) -> ApplyResult {
  let rewritten =
    list.filter_map(defs, fn(pair) {
      let #(ref, def) = pair
      let new_def = rewrite_definition(p, def)
      case new_def == def {
        True -> Error(Nil)
        False ->
          Ok(Rewrite(
            old_ref: ref,
            new_ref: Ref(codebase.hash_of_definition(new_def)),
            new_def: new_def,
          ))
      }
    })
  ApplyResult(patch: p, rewritten: rewritten)
}

pub fn rewrite_definition(p: Patch, def: ast.Definition) -> ast.Definition {
  case def {
    ast.TermDef(term, typ) -> ast.TermDef(rewrite_term(p, term), typ)
    _ -> def
  }
}

pub fn rewrite_term(p: Patch, term: ast.Term) -> ast.Term {
  case term {
    ast.RefTo(ref) ->
      case lookup(p, ref) {
        Ok(new_ref) -> ast.RefTo(new_ref)
        Error(_) -> term
      }
    ast.Apply(f, arg) -> ast.Apply(rewrite_term(p, f), rewrite_term(p, arg))
    ast.Lambda(binder, body) -> ast.Lambda(binder, rewrite_term(p, body))
    ast.Let(binder, value, body) ->
      ast.Let(binder, rewrite_term(p, value), rewrite_term(p, body))
    ast.List(items) -> ast.List(list.map(items, rewrite_term(p, _)))
    ast.Match(scrutinee, cases) ->
      ast.Match(
        rewrite_term(p, scrutinee),
        list.map(cases, fn(c) { ast.Case(..c, body: rewrite_term(p, c.body)) }),
      )
    ast.Do(ability, op, args) ->
      ast.Do(
        case lookup(p, ability) {
          Ok(new_ref) -> new_ref
          Error(_) -> ability
        },
        op,
        list.map(args, rewrite_term(p, _)),
      )
    ast.Handle(computation, handler, ability) ->
      ast.Handle(
        rewrite_term(p, computation),
        rewrite_term(p, handler),
        case lookup(p, ability) {
          Ok(new_ref) -> new_ref
          Error(_) -> ability
        },
      )
    ast.Construct(ctor_ref, args) ->
      ast.Construct(
        case lookup(p, ctor_ref) {
          Ok(new_ref) -> new_ref
          Error(_) -> ctor_ref
        },
        list.map(args, rewrite_term(p, _)),
      )
    ast.Use(binder, call, body) ->
      ast.Use(binder, rewrite_term(p, call), rewrite_term(p, body))
    ast.Located(inner, span) -> ast.Located(rewrite_term(p, inner), span)
    _ -> term
  }
}

fn references_ref(def: ast.Definition, target: DefinitionRef) -> Bool {
  case def {
    ast.TermDef(term, _) -> term_references_probe(term, target)
    _ -> False
  }
}

/// Walk a term once, reporting whether `target` appears anywhere in it.
/// A probe, not a rewrite: same shape as rewrite_term so they never drift.
fn term_references_probe(term: ast.Term, target: DefinitionRef) -> Bool {
  case term {
    ast.RefTo(ref) -> ref == target
    ast.Apply(f, arg) ->
      term_references_probe(f, target) || term_references_probe(arg, target)
    ast.Lambda(_, body) -> term_references_probe(body, target)
    ast.Let(_, value, body) ->
      term_references_probe(value, target)
      || term_references_probe(body, target)
    ast.List(items) -> list.any(items, term_references_probe(_, target))
    ast.Match(scrutinee, cases) ->
      term_references_probe(scrutinee, target)
      || list.any(cases, fn(c) { term_references_probe(c.body, target) })
    ast.Do(ability, _, args) ->
      ability == target || list.any(args, term_references_probe(_, target))
    ast.Handle(computation, handler, ability) ->
      ability == target
      || term_references_probe(computation, target)
      || term_references_probe(handler, target)
    ast.Construct(ctor_ref, args) ->
      ctor_ref == target || list.any(args, term_references_probe(_, target))
    ast.Use(_, call, body) ->
      term_references_probe(call, target) || term_references_probe(body, target)
    ast.Located(inner, _) -> term_references_probe(inner, target)
    _ -> False
  }
}
