import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/cli_datalog
import gleamunison/elab_types.{
  type SCase, type SurfaceDef, type SurfaceTerm, SApply, SConstruct, SDo, SFloat,
  SGuardGuard, SHandle, SHole, SInt, SLabeledFn, SLambda, SLet, SList, SLoc,
  SMatch, SRef, SText, SUse, SVar, SurfaceAbilityDef, SurfacePubTypeAlias,
  SurfaceTermDef, SurfaceTypeAlias, SurfaceTypeDef,
}
import gleamunison/identity.{type DefinitionRef, Ref, hash_to_debug_string}
import gleamunison/repl_eval

/// A datalog datom for the codebase index: entity is a stable per-def int,
/// value is always a string (hashes, names, kinds) so q-val joins work.
pub type Datom {
  Datom(entity: Int, attr: String, value: String)
}

/// The definition kind as the index reports it.
pub fn kind_of(def: SurfaceDef) -> String {
  case def {
    SurfaceTermDef(_) -> "term"
    SurfaceTypeDef(_) -> "type"
    SurfaceAbilityDef(_, _) -> "ability"
    SurfaceTypeAlias(_, _) -> "type-alias"
    SurfacePubTypeAlias(_, _) -> "type-alias"
  }
}

/// The ref hex for a definition: the genesis ref for builtins, the
/// name-hash for surface defs. Single source of ref identity for the
/// index, MCP search, and graph tools.
pub fn ref_hex(name: String, def: SurfaceDef) -> String {
  case def {
    SurfaceTermDef(SRef(r)) -> ref_to_hex(r)
    _ -> ref_to_hex(repl_eval.ref_for_name(name))
  }
}

fn ref_to_hex(r: DefinitionRef) -> String {
  let Ref(h) = r
  hash_to_debug_string(h)
}

/// The index schema: one entity per definition, carrying name/hash/kind,
/// plus one def/dep datom per in-corpus name the body references.
pub fn datoms_of(defs: List(#(String, SurfaceDef))) -> List(Datom) {
  let names = list.map(defs, fn(p) { p.0 })
  list.index_fold(defs, [], fn(acc, pair, i) {
    let e = i + 1
    let base = [
      Datom(e, "def/name", pair.0),
      Datom(e, "def/hash", ref_hex(pair.0, pair.1)),
      Datom(e, "def/kind", kind_of(pair.1)),
    ]
    let deps =
      surface_deps(pair.1)
      |> list.unique
      |> list.filter(fn(n) { list.contains(names, n) })
      |> list.map(fn(n) { Datom(e, "def/dep", n) })
    list.append(acc, list.append(base, deps))
  })
}

/// Names a definition's body references (free vars at the surface level).
/// Out-of-corpus filtering happens in datoms_of.
fn surface_deps(def: SurfaceDef) -> List(String) {
  case def {
    SurfaceTermDef(term) -> term_refs(term)
    _ -> []
  }
}

fn term_refs(term: SurfaceTerm) -> List(String) {
  case term {
    SLoc(inner, _) -> term_refs(inner)
    SVar(name) -> [name]
    SRef(_) -> []
    SInt(_) | SFloat(_) | SText(_) | SHole -> []
    SList(items) -> list.flat_map(items, term_refs)
    SApply(f, a) -> list.append(term_refs(f), term_refs(a))
    // The param is bound, not a reference.
    SLambda(_, body) -> term_refs(body)
    SLet(_, value, body) -> list.append(term_refs(value), term_refs(body))
    SMatch(scrutinee, cases) ->
      list.append(term_refs(scrutinee), list.flat_map(cases, case_refs))
    SDo(_, _, args) -> list.flat_map(args, term_refs)
    SHandle(comp, handler, _) ->
      list.append(term_refs(comp), term_refs(handler))
    SConstruct(_, args) -> list.flat_map(args, term_refs)
    SLabeledFn(params, body) ->
      list.append(
        list.flat_map(params, fn(p) { term_refs(p.1) }),
        term_refs(body),
      )
    SGuardGuard(guard) -> term_refs(guard)
    SUse(_, call, body) -> list.append(term_refs(call), term_refs(body))
  }
}

fn case_refs(c: SCase) -> List(String) {
  let guard_refs = case c.guard {
    option.Some(g) -> term_refs(g)
    option.None -> []
  }
  list.append(guard_refs, term_refs(c.body))
}

/// The generated index script: engine-agnostic prelude (bindings extraction
/// helper) followed by one db-assert chain building `db`.
pub fn index_source(defs: List(#(String, SurfaceDef))) -> String {
  let asserts =
    list.map(datoms_of(defs), fn(d) {
      "(db-assert db "
      <> int.to_string(d.entity)
      <> " \""
      <> d.attr
      <> "\" \""
      <> d.value
      <> "\")"
    })
  // Chronological threading: (let db db-empty (let db A1 (let db A2 db))).
  // Reversed fold builds innermost-last; the seed binds db-empty.
  let chain =
    "(let db db-empty "
    <> list.fold(list.reverse(asserts), "db", fn(acc, a) {
      "(let db " <> a <> " " <> acc <> ")"
    })
    <> ")"
  prelude_source <> "\n(define db " <> chain <> ")\n"
}

/// Helper available to index scripts: extract one var's values from a
/// db-query result set.
const prelude_source =
  "(define binding-values (lam results (lam name (list-fold (lam acc (lam b (list-append acc (list (bindings-get b name))))) (list) results))))
"

/// Evaluate an index script under the native datalog engine. The engine
/// sources are prepended (same path the datalog CLI uses).
pub fn eval_index_source(script: String) -> Result(String, String) {
  use engine_src <- result.try(cli_datalog.read_engine())
  cli_datalog.eval_source(engine_src <> "\n" <> script)
}
