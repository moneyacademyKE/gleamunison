import gleam/bit_array
import gleam/list
import gleam/option
import gleam/string
import gleamunison/agent_read_model
import gleamunison/ast
import gleamunison/codebase
import gleamunison/identity.{Local, Ref, hash_to_debug_string}
import gleamunison/mcp
import gleamunison/mcp_session
import gleamunison/namespace
import gleamunison/repl_eval
import gleamunison/storage
import gleeunit/should

@external(erlang, "gleamunison_ffi_test", "pd_counter_inc")
fn pd_counter_inc(key: BitArray) -> Int

@external(erlang, "gleamunison_ffi_test", "pd_counter_get")
fn pd_counter_get(key: BitArray) -> Int

/// One read model, one immutable view: the branch pointer is read once per
/// load. A second read doubles namespace I/O on the hot path (mcp_session,
/// generation_loop) and can diverge from the first under a concurrent write.
pub fn load_reads_branch_namespace_once_test() {
  let #(adapter, _, _, _) = seeded_branches()
  let pointer = namespace.branch_pointer_ref("main")
  let key = bit_array.from_string("read-model-head-lookups")
  let counting =
    storage.StorageAdapter(..adapter, lookup: fn(ref) {
      case ref == pointer {
        True -> {
          let _ = pd_counter_inc(key)
          adapter.lookup(ref)
        }
        False -> adapter.lookup(ref)
      }
    })
  let before = pd_counter_get(key)
  let assert Ok(_) = agent_read_model.load(counting, "main")
  pd_counter_get(key) - before |> should.equal(1)
}

/// A store that cannot answer is still an error, not an empty namespace: one
/// load failing must surface exactly as it did when there were two.
pub fn load_surfaces_a_broken_branch_pointer_test() {
  let #(adapter, _, _, _) = seeded_branches()
  let broken =
    storage.StorageAdapter(..adapter, lookup: fn(_) {
      Error(storage.IoError("store unavailable"))
    })
  agent_read_model.load(broken, "main") |> should.be_error
}

pub fn selected_branch_controls_stored_dependencies_test() {
  let #(adapter, caller_ref, base_main, base_other) = seeded_branches()
  let assert Ok(main) = mcp_session.from_store(adapter, "main")
  let assert Ok(#(main_value, _)) = mcp_session.eval_source(main, "answer")
  string.contains(main_value, "40") |> should.be_true
  let assert Ok(#(main_sum, _)) =
    mcp_session.eval_source(main, "(add answer 2)")
  string.contains(main_sum, "42") |> should.be_true

  let assert Ok(other) = mcp_session.from_store(adapter, "other")
  let assert Ok(#(other_value, _)) = mcp_session.eval_source(other, "answer")
  string.contains(other_value, "41") |> should.be_true
  definition_field(main, "base", ref_hex(base_main))
  definition_field(other, "base", ref_hex(base_other))

  mcp_session.deps_of(main, "answer") |> should.equal(Ok(["base"]))
  let assert Ok(callers) = mcp_session.callers_of(main, "base")
  list.contains(callers, "answer") |> should.be_true
  let assert Ok(hit) =
    list.find(mcp_session.search(main, "answer"), fn(hit) {
      hit.name == "answer"
    })
  hit.content_ref_hex
  |> should.equal(option.Some(ref_hex(caller_ref)))
}

pub fn scratch_shadows_branch_without_mutating_cas_test() {
  let #(adapter, caller_ref, _, _) = seeded_branches()
  let assert Ok(_) = mcp_session.from_store(adapter, "main")
  // A second durable boot reloads the same generated modules. Scratch must
  // still replace the name cleanly when an old BEAM version exists.
  let assert Ok(published) = mcp_session.from_store(adapter, "main")
  definition_field(published, "answer", ref_hex(caller_ref))
  definition_field(published, "answer", "\\\"origin\\\":\\\"branch")

  let assert Ok(#(_, scratched)) =
    mcp_session.define_source(published, "answer", "7")
  let assert Ok(#(value, _)) = mcp_session.eval_source(scratched, "answer")
  string.contains(value, "7") |> should.be_true
  definition_field(scratched, "answer", "\\\"origin\\\":\\\"scratch")
  let assert Ok(hit) =
    list.find(mcp_session.search(scratched, "answer"), fn(hit) {
      hit.name == "answer"
    })
  { hit.content_ref_hex != option.Some(ref_hex(caller_ref)) }
  |> should.be_true

  codebase.get(codebase.with_adapter(adapter), caller_ref)
  |> should.be_ok
}

pub fn stored_type_survives_scratch_overlay_test() {
  let #(adapter, _, _, _) = seeded_branches()
  let assert Ok(published) = mcp_session.from_store(adapter, "main")
  mcp_session.defs_by_kind(published, "type")
  |> should.equal(Ok(["AnswerType"]))
  let assert Ok(#(_, scratched)) =
    mcp_session.define_source(published, "unrelated", "7")
  mcp_session.defs_by_kind(scratched, "type")
  |> should.equal(Ok(["AnswerType"]))
  definition_field(scratched, "AnswerType", "\\\"origin\\\":\\\"branch")
}

fn seeded_branches() {
  let adapter = storage.inmemory()
  let base_main_def = ast.TermDef(ast.Int(40), ast.Builtin(ast.IntType))
  let base_other_def = ast.TermDef(ast.Int(41), ast.Builtin(ast.IntType))
  let caller_def =
    ast.TermDef(
      ast.RefTo(repl_eval.ref_for_name("base")),
      ast.Builtin(ast.IntType),
    )
  let base_main = content_ref(base_main_def)
  let base_other = content_ref(base_other_def)
  let caller = content_ref(caller_def)
  let answer_type = ast.TypeDef(ast.Structural(Local(0), [], []))
  let answer_type_ref = content_ref(answer_type)
  let unit =
    ast.Unit(caller, [
      #(base_main, base_main_def),
      #(base_other, base_other_def),
      #(caller, caller_def),
      #(answer_type_ref, answer_type),
    ])
  let assert Ok(_) = codebase.insert(codebase.with_adapter(adapter), unit)
  let main_ns =
    namespace.empty()
    |> namespace.set("base", base_main)
    |> namespace.set("answer", caller)
    |> namespace.set("AnswerType", answer_type_ref)
  let other_ns =
    namespace.empty()
    |> namespace.set("base", base_other)
    |> namespace.set("answer", caller)
    |> namespace.set("AnswerType", answer_type_ref)
  let assert Ok(_) = namespace.commit(adapter, "main", main_ns)
  let assert Ok(_) = namespace.commit(adapter, "other", other_ns)
  #(adapter, caller, base_main, base_other)
}

fn content_ref(definition) {
  Ref(codebase.hash_of_definition(definition))
}

fn ref_hex(ref) {
  let Ref(hash) = ref
  hash_to_debug_string(hash)
}

fn definition_field(state, name, expected) {
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_definition\",\"arguments\":{\"name\":\""
    <> name
    <> "\"}}}"
  let assert mcp.Respond(response) = mcp_session.handle_rpc(state, body)
  string.contains(response, expected) |> should.be_true
}
