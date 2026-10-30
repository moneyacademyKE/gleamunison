import gleam/bit_array
import gleam/dynamic/decode
import gleam/list
import gleam/option.{Some}
import gleamunison/ast
import gleamunison/codebase
import gleamunison/elab_types.{SurfaceTermDef}
import gleamunison/identity.{Ref, hash_to_debug_string, parse_ref_hex}
import gleamunison/json
import gleamunison/mcp
import gleamunison/mcp_session
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/test_runner
import gleamunison/types.{empty_cache}
import gleamunison/verify
import gleeunit/should
import run_support
import simplifile

pub fn mcp_content_ref_is_distinct_from_name_ref_and_runs_test() {
  let path = "/tmp/mcp_content_ref_roundtrip.lisp"
  let name = "mcp-forty-two"
  let assert Ok(Nil) = simplifile.write(path, "(define " <> name <> " 42)\n")
  let assert Ok(surface) = parser.parse_string("42")
  let #(cache, defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
  let all_defs = [#(name, SurfaceTermDef(surface)), ..defs]
  let assert Ok(definition) =
    test_runner.elaborated_def_for(name, all_defs, cache)
  let expected_content =
    hash_to_debug_string(codebase.hash_of_definition(definition))
  let expected_name = case repl_eval.ref_for_name(name) {
    Ref(hash) -> hash_to_debug_string(hash)
  }

  let assert Ok(state) = mcp_session.load_file(mcp_session.boot(), path)
  let body =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_definition\",\"arguments\":{\"name\":\""
    <> name
    <> "\"}}}"
  let assert mcp.Respond(response) = mcp_session.handle_rpc(state, body)
  let content_hex = response_field(response, "ref")
  let name_hex = response_field(response, "name_ref")
  content_hex |> should.equal(expected_content)
  name_hex |> should.equal(expected_name)
  { content_hex != name_hex } |> should.be_true

  let assert Ok(hit) =
    list.find(mcp_session.search(state, name), fn(hit) { hit.name == name })
  hit.content_ref_hex |> should.equal(Some(content_hex))
  hit.ref_hex |> should.equal(name_hex)

  let assert Ok(ref) = parse_ref_hex(content_hex)
  let assert Ok(cb) =
    codebase.insert(codebase.empty(), ast.Unit(ref, [#(ref, definition)]))
  run_support.run_raw(codebase.get_adapter(cb), ref, [])
  |> should.be_ok
  simplifile.delete(path)
}

fn response_field(response: String, field: String) -> String {
  let text_decoder = {
    use text <- decode.field("text", decode.string)
    decode.success(text)
  }
  let result_decoder = {
    use items <- decode.field("content", decode.list(text_decoder))
    decode.success(items)
  }
  let envelope_decoder = {
    use texts <- decode.field("result", result_decoder)
    decode.success(texts)
  }
  let assert Ok(envelope) = json.decode(bit_array.from_string(response))
  let assert Ok([text]) = decode.run(envelope, envelope_decoder)
  let assert Ok(definition) = json.decode(bit_array.from_string(text))
  let field_decoder = {
    use value <- decode.field(field, decode.string)
    decode.success(value)
  }
  let assert Ok(value) = decode.run(definition, field_decoder)
  value
}
