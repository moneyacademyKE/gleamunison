//// Whether a definition is effectful — the fact the evidence gate turns on.
////
//// A pure definition must be tested; an effectful one may instead carry a human
//// `io` attestation, because a suite cannot drive real IO. That decision needs
//// one answer to "is this effectful?", and it belongs to the term, not to the
//// command asking: `publish` and `run` must agree, or a definition gets admitted
//// by one gate and refused by the other.
////
//// The term is the honest source. A top-level value type carries no requirement
//// row, but an ability call is right there as a `Do` node.

import gleam/list
import gleam/option
import gleamunison/ast
import gleamunison/bootstrap_terms
import gleamunison/identity.{ref_hex}

pub fn definition_is_effectful(definition: ast.Definition) -> Bool {
  case definition {
    ast.TermDef(term:, ..) -> term_is_effectful(term)
    _ -> False
  }
}

fn term_is_effectful(term: ast.Term) -> Bool {
  case term {
    ast.Do(..) -> True
    ast.RefTo(ref) -> bootstrap_terms.is_host_ref(ref)
    ast.LocalVarRef(_) | ast.Int(_) | ast.Float(_) | ast.Text(_) | ast.Hole ->
      False
    ast.List(items) -> list.any(items, term_is_effectful)
    ast.Apply(f, a) -> term_is_effectful(f) || term_is_effectful(a)
    ast.Lambda(_, body) -> term_is_effectful(body)
    ast.Let(_, value, body) ->
      term_is_effectful(value) || term_is_effectful(body)
    ast.Match(scrutinee, cases) ->
      term_is_effectful(scrutinee) || list.any(cases, case_is_effectful)
    ast.Handle(comp, handler, _) ->
      term_is_effectful(comp) || term_is_effectful(handler)
    ast.Construct(_, args) -> list.any(args, term_is_effectful)
    ast.Use(_, call, body) -> term_is_effectful(call) || term_is_effectful(body)
    ast.Located(inner, _) -> term_is_effectful(inner)
  }
}

fn case_is_effectful(c: ast.Case) -> Bool {
  let guard_has = case c.guard {
    option.Some(ast.GuardTerm(t)) -> term_is_effectful(t)
    option.None -> False
  }
  guard_has || term_is_effectful(c.body)
}

/// One elaborated definition in a publication batch.
pub type BatchEntry {
  BatchEntry(name: String, content_ref: String, term: ast.Term)
}

/// Names in the batch that must carry effect evidence.
///
/// A definition is effectful when its own term performs an ability op, or when
/// it transitively references another batch definition that does. This is
/// conservative: a `Do` sitting under a `Handle` still counts, matching the
/// original single-definition check extended across the batch graph.
pub fn batch_effectful(entries: List(BatchEntry)) -> List(String) {
  let initial =
    list.filter_map(entries, fn(entry) {
      case term_is_effectful(entry.term) {
        True -> Ok(entry.name)
        False -> Error(Nil)
      }
    })
  expand_batch(entries, initial)
}

fn expand_batch(
  entries: List(BatchEntry),
  known: List(String),
) -> List(String) {
  let newly =
    list.filter_map(entries, fn(entry) {
      case list.contains(known, entry.name) {
        True -> Error(Nil)
        False -> {
          let dep_names =
            list.filter_map(term_deps(entry.term), fn(hash) {
              name_of_content_ref(entries, hash)
            })
          case list.any(dep_names, fn(name) { list.contains(known, name) }) {
            True -> Ok(entry.name)
            False -> Error(Nil)
          }
        }
      }
    })
  case newly {
    [] -> known
    _ -> expand_batch(entries, list.append(known, newly))
  }
}

/// Elaboration wires intra-batch references by *name* (`ref_for_name` = hash
/// of the name), while evidence identity is the *content* hash. A term's dep
/// refs are therefore keyed on name hashes; resolve them back to batch names.
fn name_of_content_ref(
  entries: List(BatchEntry),
  hash: String,
) -> Result(String, Nil) {
  case
    list.find(entries, fn(entry) {
      ref_hex(identity.name_ref(entry.name)) == hash
    })
  {
    Ok(entry) -> Ok(entry.name)
    Error(_) -> Error(Nil)
  }
}

fn term_deps(t: ast.Term) -> List(String) {
  do_term_deps(t, [])
}

fn do_term_deps(t: ast.Term, acc: List(String)) -> List(String) {
  case t {
    ast.RefTo(ref) -> [ref_hex(ref), ..acc]
    ast.LocalVarRef(_) | ast.Int(_) | ast.Float(_) | ast.Text(_) | ast.Hole ->
      acc
    ast.List(items) -> list.fold(items, acc, fn(a, x) { do_term_deps(x, a) })
    ast.Apply(f, a) -> do_term_deps(a, do_term_deps(f, acc))
    ast.Lambda(_, body) -> do_term_deps(body, acc)
    ast.Let(_, value, body) -> do_term_deps(body, do_term_deps(value, acc))
    ast.Match(scrutinee, cases) -> {
      let acc2 = do_term_deps(scrutinee, acc)
      list.fold(cases, acc2, fn(a, c) {
        let a2 = case c.guard {
          option.Some(ast.GuardTerm(gt)) -> do_term_deps(gt, a)
          option.None -> a
        }
        do_term_deps(c.body, a2)
      })
    }
    ast.Do(_, _, args) -> list.fold(args, acc, fn(a, x) { do_term_deps(x, a) })
    ast.Handle(comp, handler, _) ->
      do_term_deps(handler, do_term_deps(comp, acc))
    ast.Construct(_, args) ->
      list.fold(args, acc, fn(a, x) { do_term_deps(x, a) })
    ast.Use(_, call, body) -> do_term_deps(body, do_term_deps(call, acc))
    ast.Located(inner, _) -> do_term_deps(inner, acc)
  }
}
