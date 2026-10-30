import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/capability
import gleamunison/codebase
import gleamunison/effects.{HandlerFrame}
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/identity.{Ref}
import gleamunison/parser
import gleamunison/publication
import gleamunison/repl_eval
import gleamunison/run_ref
import gleamunison/test_runner
import gleamunison/types.{CTAbility}
import gleamunison/verify
import gleeunit/should
import simplifile

@external(erlang, "gleamunison_app_db", "with_path")
fn with_db_path(path: String, work: fn() -> a) -> a

@external(erlang, "gleamunison_runtime_sup", "stop_db")
fn stop_db() -> Dynamic

@external(erlang, "gleamunison_ffi_test", "rescue")
fn rescue(work: fn() -> Dynamic) -> Result(Dynamic, String)

pub fn db_operations_have_concrete_signatures_test() {
  let #(cache, _) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), types.empty_cache())
  let assert Ok(CTAbility(operations)) =
    dict.get(cache.entries, repl_eval.ref_for_name("Db"))
  list.map(operations, fn(operation) {
    #(list.length(operation.inputs), operation.output)
  })
  |> should.equal([
    #(2, ast.Builtin(ast.IntType)),
    #(2, ast.Builtin(ast.ListType)),
    #(2, ast.Builtin(ast.ListType)),
  ])
}

pub fn db_rejects_wrong_argument_types_test() {
  let #(cache, defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), types.empty_cache())
  let assert Ok(term) =
    parser.parse_string("(do Db transact \"not-a-list\" (list))")
  repl_eval.handle_define("bad-db", term, cache, defs) |> should.be_error
}

pub fn db_call_is_effectful_for_publication_test() {
  let #(cache, defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), types.empty_cache())
  let assert Ok(term) = parser.parse_string("(do Db get \"person:1\" \"name\")")
  let user_defs = [#("db-read", SurfaceTermDef(term)), ..defs]
  let assert Ok([#(_, _, effectful)]) =
    publication.hash_defs(["db-read"], user_defs, cache)
  effectful |> should.be_true
}

pub fn db_transactions_survive_owner_restart_test() {
  with_temp_db(fn(_) {
    let #(cb, write, retract, read, find, status) = definitions()
    let assert Ok("1") = run_ref.run(codebase.get_adapter(cb), write, [])
    stop_db()
    let assert Ok(reading) = run_ref.run(codebase.get_adapter(cb), read, [])
    string.contains(reading, "Moe") |> should.be_true
    let assert Ok(found) = run_ref.run(codebase.get_adapter(cb), find, [])
    string.contains(found, "person:1") |> should.be_true
    let assert Ok(before_retract) =
      run_ref.run(codebase.get_adapter(cb), status, [])
    string.contains(before_retract, "new") |> should.be_true
    let assert Ok("2") = run_ref.run(codebase.get_adapter(cb), retract, [])
    stop_db()
    let assert Ok(after_retract) =
      run_ref.run(codebase.get_adapter(cb), status, [])
    string.contains(after_retract, "new") |> should.be_false
    let assert Ok("3") = run_ref.run(codebase.get_adapter(cb), write, [])
  })
}

pub fn denied_db_frame_never_opens_the_application_store_test() {
  with_temp_db(fn(path) {
    let handler = fn(_args, _cont) {
      panic as "a denied Db operation reached its storage handler"
    }
    let frame =
      HandlerFrame(
        ability: repl_eval.ref_for_name("Db"),
        ops: dict.from_list([#(0, handler)]),
      )
    let assert [denied] = capability.guard_frames(capability.allow([]), [frame])
    let assert Ok(operation) = dict.get(denied.ops, 0)
    let assert Error(reason) =
      rescue(fn() { operation([], fn(value) { value }) })
    string.contains(reason, "capability_denied") |> should.be_true
    simplifile.is_file(path) |> should.equal(Ok(False))
  })
}

fn with_temp_db(work: fn(String) -> a) -> a {
  let path = "/tmp/gleamunison-db-ability-test.dets"
  let _ = stop_db()
  let _ = simplifile.delete(path)
  let result = with_db_path(path, fn() { work(path) })
  let _ = stop_db()
  let _ = simplifile.delete(path)
  result
}

fn definitions() {
  let source = "/tmp/gleamunison-db-ability-test.lisp"
  let text =
    "(define db-write (do Db transact (list (pair \"person:1\" (pair \"name\" \"Moe\")) (pair \"person:1\" (pair \"status\" \"new\"))) (list)))\n"
    <> "(define db-retract (do Db transact (list) (list (pair \"person:1\" (pair \"status\" \"new\")))))\n"
    <> "(define db-read (do Db get \"person:1\" \"name\"))\n"
    <> "(define db-find (do Db find \"name\" \"Moe\"))\n"
    <> "(define db-status (do Db get \"person:1\" \"status\"))\n"
  let assert Ok(_) = simplifile.write(source, text)
  let assert Ok(#(cache, defs)) = verify.load_defs_file(source)
  let #(cb, write) = insert(codebase.empty(), "db-write", defs, cache)
  let #(cb, retract) = insert(cb, "db-retract", defs, cache)
  let #(cb, read) = insert(cb, "db-read", defs, cache)
  let #(cb, find) = insert(cb, "db-find", defs, cache)
  let #(cb, status) = insert(cb, "db-status", defs, cache)
  let assert Ok(_) = simplifile.delete(source)
  #(cb, write, retract, read, find, status)
}

fn insert(cb, name, defs, cache) {
  let assert Ok(definition) = test_runner.elaborated_def_for(name, defs, cache)
  let ref = Ref(codebase.hash_of_definition(definition))
  let assert Ok(next) = codebase.insert(cb, ast.Unit(ref, [#(ref, definition)]))
  #(next, ref)
}
