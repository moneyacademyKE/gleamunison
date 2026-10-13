import gleam/list
import gleam/string
import gleamunison/codebase_index
import gleamunison/elab_types.{
  SApply, SInt, SLambda, SLet, SText, SVar, SurfaceTermDef,
}
import gleamunison/mcp_session
import gleeunit/should

fn sample_defs() -> List(#(String, elab_types.SurfaceDef)) {
  [
    #("one", SurfaceTermDef(SInt(1))),
    #("inc", SurfaceTermDef(SLambda("x", SApply(SVar("one"), SVar("x"))))),
    #("two", SurfaceTermDef(SLet("a", SVar("inc"), SApply(SVar("a"), SInt(1))))),
  ]
}

/// The indexer emits datalog datoms per definition: name, hash, kind, and
/// one def/dep datom per referenced in-corpus name.
pub fn index_source_emits_datoms_per_def_test() {
  let src = codebase_index.index_source(sample_defs())
  string.contains(src, "def/name") |> should.be_true
  string.contains(src, "def/hash") |> should.be_true
  string.contains(src, "def/kind") |> should.be_true
  string.contains(src, "def/dep") |> should.be_true
  string.contains(src, "\"inc\"") |> should.be_true
}

/// Deps are surface names referenced by the body that exist in the corpus.
pub fn index_deps_are_in_corpus_refs_test() {
  let datoms = codebase_index.datoms_of(sample_defs())
  // inc depends on one; two depends on inc (via the let binding value).
  let deps =
    list.filter(datoms, fn(d) { d.attr == "def/dep" && d.value == "one" })
  list.length(deps) |> should.equal(1)
  let deps2 =
    list.filter(datoms, fn(d) { d.attr == "def/dep" && d.value == "inc" })
  list.length(deps2) |> should.equal(1)
}

/// Free vars that are NOT in the corpus (builtins like add) are not deps.
pub fn index_ignores_out_of_corpus_names_test() {
  let defs = [#("f", SurfaceTermDef(SApply(SVar("add"), SInt(1))))]
  let datoms = codebase_index.datoms_of(defs)
  list.filter(datoms, fn(d) { d.attr == "def/dep" })
  |> list.length
  |> should.equal(0)
}

/// End-to-end: generated source evaluates under the engine and a join
/// query answers "who calls one?" with the caller's name.
pub fn index_evaluates_under_engine_test() {
  let script =
    codebase_index.index_source(sample_defs())
    <> "\n(define q (list (pair (q-var \"?e\") (pair \"def/dep\" (q-val \"one\"))) (pair (q-var \"?e\") (pair \"def/name\" (q-var \"?n\")))))\n(binding-values (db-query db q) \"?n\")\n"
  let assert Ok(out) = codebase_index.eval_index_source(script)
  let lines = string.split(out, "\n")
  let assert Ok(last) = list.last(lines)
  string.contains(last, "inc") |> should.be_true
}
