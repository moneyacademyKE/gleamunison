import gleam/list
import gleam/result
import gleeunit/should
import simplifile

/// The engine ships in priv/datalog — the one directory a Hex package
/// carries — while gleamunison_datalog/src stays the editable source of
/// truth. Two copies that can drift are worse than one that is missing, so
/// this test fails the moment they disagree and a stale package cannot be
/// cut. build_escript.sh re-syncs the copy before packaging.
const engine_files = [
  "01_core.lisp",
  "02_index.lisp",
  "03_transact.lisp",
  "04_schema.lisp",
  "05_query.lisp",
  "06_aggregate.lisp",
  "07_pull.lisp",
  "08_temporal.lisp",
  "09_rules.lisp",
  "10_graph.lisp",
  "11_vector.lisp",
  "12_bm25.lisp",
  "13_actor.lisp",
]

pub fn shipped_engine_matches_source_test() {
  list.each(engine_files, fn(name) {
    let source = read_or_fail("gleamunison_datalog/src/" <> name)
    let shipped = read_or_fail("priv/datalog/" <> name)
    shipped |> should.equal(source)
  })
}

pub fn shipped_engine_carries_every_module_test() {
  engine_files
  |> list.filter(fn(name) {
    simplifile.read("priv/datalog/" <> name) |> result.is_ok
  })
  |> list.length
  |> should.equal(13)
}

fn read_or_fail(path: String) -> String {
  case simplifile.read(path) {
    Ok(content) -> content
    Error(_) -> panic as "cannot read " <> path
  }
}
