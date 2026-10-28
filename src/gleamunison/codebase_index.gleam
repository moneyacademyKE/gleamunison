import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string
import gleamunison/agent_read_model
import gleamunison/ast
import gleamunison/bootstraps
import gleamunison/cli_datalog
import gleamunison/definition_refs
import gleamunison/elab_types.{
  type SCase, type SurfaceDef, type SurfaceTerm, SApply, SConstruct, SDo, SFloat,
  SGuardGuard, SHandle, SHole, SInt, SLabeledFn, SLambda, SLet, SList, SLoc,
  SMatch, SRef, SText, SUse, SVar, SurfaceAbilityDef, SurfacePubTypeAlias,
  SurfaceTermDef, SurfaceTypeAlias, SurfaceTypeDef,
}
import gleamunison/identity.{type DefinitionRef, ref_hex as canonical_ref_hex}
import gleamunison/lisp_literal
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
    // A builtin's definition is stored under a synthetic handle, not a content
    // hash. Printing that handle as a hash told a caller `list-map` lives at
    // `#000000000000` — a ref nothing can resolve. The name ref is what the
    // elaborator emits and what a caller can actually reference.
    SurfaceTermDef(SRef(r)) ->
      case bootstraps.builtin_name_for(r) {
        Ok(builtin) -> ref_to_hex(repl_eval.ref_for_name(builtin))
        Error(_) -> ref_to_hex(r)
      }
    _ -> ref_to_hex(repl_eval.ref_for_name(name))
  }
}

pub fn kind_of_entry(entry: agent_read_model.Entry) -> String {
  case entry {
    agent_read_model.Source(definition:, ..) -> kind_of(definition)
    agent_read_model.Stored(definition:, ..) ->
      case definition {
        ast.TermDef(..) -> "term"
        ast.TypeDef(_) -> "type"
        ast.AbilityDecl(_) -> "ability"
      }
  }
}

pub fn ref_hex_entry(entry: agent_read_model.Entry) -> String {
  case entry {
    agent_read_model.Source(name:, definition:, ..) -> ref_hex(name, definition)
    agent_read_model.Stored(name:, ..) ->
      ref_to_hex(repl_eval.ref_for_name(name))
  }
}

fn ref_to_hex(r: DefinitionRef) -> String {
  canonical_ref_hex(r)
}

/// The index schema: one entity per definition, carrying name/hash/kind,
/// plus one def/dep datom per in-corpus name the body references.
pub fn datoms_of(defs: List(#(String, SurfaceDef))) -> List(Datom) {
  let entries =
    list.map(defs, fn(pair) {
      agent_read_model.Source(pair.0, pair.1, agent_read_model.Scratch)
    })
  datoms_of_entries(entries)
}

pub fn datoms_of_entries(entries: List(agent_read_model.Entry)) -> List(Datom) {
  let names = list.map(entries, agent_read_model.name) |> set.from_list
  let ref_names =
    list.fold(entries, dict.new(), fn(acc, entry) {
      let with_name =
        dict.insert(
          acc,
          repl_eval.ref_for_name(agent_read_model.name(entry)),
          agent_read_model.name(entry),
        )
      case entry {
        agent_read_model.Stored(name:, ref:, ..) ->
          dict.insert(with_name, ref, name)
        _ -> with_name
      }
    })
  list.index_fold(entries, [], fn(acc, entry, i) {
    let e = i + 1
    let base = [
      Datom(e, "def/name", agent_read_model.name(entry)),
      Datom(e, "def/hash", ref_hex_entry(entry)),
      Datom(e, "def/kind", kind_of_entry(entry)),
    ]
    let deps = case entry {
      agent_read_model.Source(definition:, ..) ->
        surface_deps(definition)
        |> list.filter(fn(name) { set.contains(names, name) })
      agent_read_model.Stored(definition:, ..) ->
        definition_refs.refs_of_definition(definition)
        |> list.filter_map(fn(ref) { dict.get(ref_names, ref) })
    }
    let dep_datoms =
      deps
      |> list.unique
      |> list.map(fn(name) { Datom(e, "def/dep", name) })
    list.fold(list.append(base, dep_datoms), acc, fn(acc, datom) {
      [datom, ..acc]
    })
  })
  |> list.reverse
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

/// Build index data as a flat list of triples, not a nested let per datom.
/// The native engine folds the data; generated source obeys normal admission.
pub fn index_source(defs: List(#(String, SurfaceDef))) -> String {
  render_index(datoms_of(defs))
}

fn render_index(datoms: List(Datom)) -> String {
  let triples =
    list.map(datoms, fn(d) {
      "(pair "
      <> int.to_string(d.entity)
      <> " (pair "
      <> lisp_literal.text(d.attr)
      <> " "
      <> lisp_literal.text(d.value)
      <> "))"
    })
  prelude_source
  <> "\n(define db (db-assert-many db-empty (list "
  <> string.join(triples, " ")
  <> ")))\n"
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
