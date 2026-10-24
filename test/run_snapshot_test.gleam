import gleamunison/ast
import gleamunison/codebase
import gleamunison/genesis
import gleamunison/identity.{Ref}
import gleamunison/namespace
import gleamunison/repl_eval
import gleamunison/run_ref
import gleamunison/storage
import gleeunit/should

@external(erlang, "gleamunison_ffi_test", "pd_counter_inc")
fn increment(key: BitArray) -> Int

@external(erlang, "gleamunison_ffi_test", "pd_counter_get")
fn count(key: BitArray) -> Int

pub fn two_named_dependencies_read_the_selected_namespace_once_test() {
  let cb = codebase.empty()
  let a = ast.TermDef(ast.Int(400), ast.Builtin(ast.IntType))
  let b = ast.TermDef(ast.Int(40), ast.Builtin(ast.IntType))
  let a_ref = Ref(codebase.hash_of_definition(a))
  let b_ref = Ref(codebase.hash_of_definition(b))
  let root =
    ast.TermDef(
      ast.Apply(
        ast.Apply(
          ast.RefTo(genesis.builtin_int_add()),
          ast.RefTo(repl_eval.ref_for_name("snapshot-a")),
        ),
        ast.RefTo(repl_eval.ref_for_name("snapshot-b")),
      ),
      ast.Builtin(ast.IntType),
    )
  let ref = Ref(codebase.hash_of_definition(root))
  let assert Ok(_) =
    codebase.insert(cb, ast.Unit(ref, [#(a_ref, a), #(b_ref, b), #(ref, root)]))
  let adapter = codebase.get_adapter(cb)
  let ns =
    namespace.empty()
    |> namespace.set("snapshot-a", a_ref)
    |> namespace.set("snapshot-b", b_ref)
  let assert Ok(_) = namespace.commit(adapter, "selected", ns)
  let observed =
    storage.StorageAdapter(..adapter, lookup: fn(ref) {
      case ref == namespace.branch_pointer_ref("selected") {
        True -> {
          let _ = increment(<<"namespace-per-run">>)
          Nil
        }
        False -> Nil
      }
      adapter.lookup(ref)
    })
  run_ref.run_on_branch(observed, ref, "selected", [])
  |> should.equal(Ok("440"))
  count(<<"namespace-per-run">>) |> should.equal(1)
}
