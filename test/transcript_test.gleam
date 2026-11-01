import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/string
import gleamunison/dynamic_ffi.{from_dynamic, to_dynamic}
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/json
import gleamunison/llm
import gleamunison/transcript.{OpRecord}
import gleamunison/transcript_json
import gleeunit/should

fn echo_handler() -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    let arg0: List(String) = from_dynamic(to_dynamic(args))
    let head = case arg0 {
      [x, ..] -> x
      _ -> "no-args"
    }
    cont(to_dynamic("handled:" <> head))
  }
}

fn llm_frame(handler: OpHandler) -> HandlerFrame {
  HandlerFrame(ability: llm.ability_ref(), ops: dict.from_list([#(0, handler)]))
}

pub fn record_captures_ops_in_order_test() {
  let rec = transcript.start_with(transcript.CaptureAll)
  let frames = transcript.wrap_frames(rec, [llm_frame(echo_handler())])
  let assert [frame] = frames
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let _ = handler([to_dynamic("first")], fn(d) { d })
  let _ = handler([to_dynamic("second")], fn(d) { d })
  let entries = transcript.entries(rec)
  list.length(entries) |> should.equal(2)
  let assert [e1, e2] = entries
  e1.seq |> should.equal(0)
  e2.seq |> should.equal(1)
  e1.op |> should.equal(0)
  string.contains(e1.args_repr, "first") |> should.be_true
  string.contains(e1.result_repr, "handled:first") |> should.be_true
  string.contains(e2.result_repr, "handled:second") |> should.be_true
  transcript.stop(rec)
}

pub fn json_roundtrip_preserves_entries_test() {
  let rec = transcript.start_with(transcript.CaptureAll)
  let frames = transcript.wrap_frames(rec, [llm_frame(echo_handler())])
  let assert [frame] = frames
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let _ = handler([to_dynamic("json-me")], fn(d) { d })
  let t = transcript.capture(rec)
  transcript.stop(rec)

  let json = transcript.to_json(t)
  let assert Ok(t2) = transcript_json.from_json(json)
  transcript.to_json(t2) |> should.equal(json)
  let assert [entry] = transcript.tape_entries(t2)
  entry.op |> should.equal(0)
  string.contains(entry.result_repr, "handled:json-me") |> should.be_true
}

pub fn diff_reports_first_divergence_test() {
  let mk = fn(tag: String) {
    transcript.from_entries([
      OpRecord(
        ability: "m_deadbeef",
        op: 0,
        args_repr: "\"a\"",
        result_repr: tag,
        seq: 0,
      ),
    ])
  }
  let assert [] = transcript.diff(mk("same"), mk("same"))
  let assert [d] = transcript.diff(mk("left"), mk("right"))
  d.seq |> should.equal(0)
}

pub fn json_round_trip_preserves_replay_test() {
  // Replay consumption is covered end-to-end through the live path in
  // cli_replay_test (record → tape file → replay_from_file); this keeps the
  // pure half: a v2 tape round-tripped through JSON stays replayable.
  let rec = transcript.start_with(transcript.CaptureAll)
  let frames = transcript.wrap_frames(rec, [llm_frame(echo_handler())])
  let assert [frame] = frames
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let _ = handler([to_dynamic("hello")], fn(d) { d })
  let tape = transcript.capture(rec)
  let json = transcript.to_json(tape)
  let assert Ok(loaded) = transcript_json.from_json(json)
  transcript.is_replayable(loaded) |> should.be_true
  transcript.stop(rec)
}

pub fn v1_tape_loads_audit_only_test() {
  let v1 =
    "[{\"ability\":\"m_abcd1234\",\"op\":0,\"args\":\"x\",\"result\":\"y\",\"seq\":0}]"
  let assert Ok(tape) = transcript_json.from_json(v1)
  transcript.is_replayable(tape) |> should.be_false
}

pub fn interleaved_recorders_keep_separate_tapes_test() {
  let first = transcript.start_with(transcript.CaptureAll)
  let second = transcript.start_with(transcript.CaptureAll)

  let assert [first_frame] =
    transcript.wrap_frames(first, [llm_frame(echo_handler())])
  let assert [second_frame] =
    transcript.wrap_frames(second, [llm_frame(echo_handler())])
  let assert Ok(first_handler) = dict.get(first_frame.ops, 0)
  let assert Ok(second_handler) = dict.get(second_frame.ops, 0)

  let _ = first_handler([to_dynamic("first-a")], fn(d) { d })
  let _ = second_handler([to_dynamic("second-a")], fn(d) { d })
  let _ = first_handler([to_dynamic("first-b")], fn(d) { d })

  let assert [f1, f2] = transcript.entries(first)
  let assert [s1] = transcript.entries(second)
  f1.seq |> should.equal(0)
  f2.seq |> should.equal(1)
  s1.seq |> should.equal(0)
  string.contains(f1.args_repr, "first-a") |> should.be_true
  string.contains(f2.args_repr, "first-b") |> should.be_true
  string.contains(s1.args_repr, "second-a") |> should.be_true

  transcript.stop(first)
  transcript.stop(second)
}

pub fn to_json_escapes_control_characters_test() {
  // Term reprs routinely contain tabs; audit JSONL must stay valid JSON —
  // and round-trip through both the standard codec and the module's own
  // reader, which learned \r, \t and \uXXXX when the writer was fixed.
  let nasty = "cr\r tab\t nul\u{0} us\u{1f} quote\" back\\"
  let tape =
    transcript.from_entries([
      OpRecord(
        ability: "m_deadbeef",
        op: 0,
        args_repr: nasty,
        result_repr: nasty,
        seq: 0,
      ),
    ])
  let encoded = transcript.to_json(tape)
  let assert Ok(dyn) = json.decode(bit_array.from_string(encoded))
  let decoder =
    decode.list({
      use args <- decode.field("args", decode.string)
      use res <- decode.field("result", decode.string)
      decode.success(#(args, res))
    })
  let assert Ok([#(args, res)]) = decode.run(dyn, decoder)
  args |> should.equal(nasty)
  res |> should.equal(nasty)
  let assert Ok(loaded) = transcript_json.from_json(encoded)
  let assert [entry] = transcript.tape_entries(loaded)
  entry.args_repr |> should.equal(nasty)
  entry.result_repr |> should.equal(nasty)
}

pub fn from_json_still_reads_legacy_raw_control_characters_test() {
  // Pre-fix tapes carry raw tabs (the old escaper missed them); the reader
  // stays lenient so old audit files still load and replay.
  let legacy =
    "[{\"ability\":\"m_abcd1234\",\"op\":0,\"args\":\"a\tb\",\"result\":\"y\",\"seq\":0}]"
  let assert Ok(tape) = transcript_json.from_json(legacy)
  let assert [entry] = transcript.tape_entries(tape)
  entry.args_repr |> should.equal("a\tb")
}
