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

fn boom_handler() -> OpHandler {
  fn(_args, _cont) { panic as "playback must never call the inner handler" }
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

pub fn replay_returns_recorded_results_without_inner_test() {
  let rec = transcript.start_with(transcript.CaptureAll)
  let frames = transcript.wrap_frames(rec, [llm_frame(echo_handler())])
  let assert [frame] = frames
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let recorded = handler([to_dynamic("live")], fn(d) { d })
  let t = transcript.capture(rec)
  transcript.stop(rec)

  // Replay against a handler that panics: proof the result came from the tape.
  let pb = transcript.playback(t)
  let pb_frames = transcript.replay_frames(pb, [llm_frame(boom_handler())])
  let assert [pb_frame] = pb_frames
  let assert Ok(pb_handler) = dict.get(pb_frame.ops, 0)
  let replayed = pb_handler([to_dynamic("ignored")], fn(d) { d })
  replayed |> should.equal(recorded)
  transcript.playback_remaining(pb) |> should.equal(0)
  transcript.stop_playback(pb)
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
  let rec = transcript.start_with(transcript.CaptureAll)
  let frames = transcript.wrap_frames(rec, [llm_frame(echo_handler())])
  let assert [frame] = frames
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let _ = handler([to_dynamic("hello")], fn(d) { d })
  let tape = transcript.capture(rec)
  let json = transcript.to_json(tape)
  let assert Ok(loaded) = transcript_json.from_json(json)
  transcript.is_replayable(loaded) |> should.be_true
  let pb = transcript.playback(loaded)
  let replayed = transcript.replay_frames(pb, [llm_frame(boom_handler())])
  let assert [rframe] = replayed
  let assert Ok(rhandler) = dict.get(rframe.ops, 0)
  let result = rhandler([to_dynamic("hello")], fn(d) { d })
  let decoded: String = from_dynamic(result)
  decoded |> should.equal("handled:hello")
  transcript.stop_playback(pb)
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

pub fn interleaved_playbacks_keep_separate_cursors_test() {
  let recorded = record_one_tape("cursor-a")
  let other = record_one_tape("cursor-b")

  let first = transcript.playback(recorded)
  let second = transcript.playback(other)
  let assert [first_frame] =
    transcript.replay_frames(first, [llm_frame(boom_handler())])
  let assert [second_frame] =
    transcript.replay_frames(second, [llm_frame(boom_handler())])
  let assert Ok(first_handler) = dict.get(first_frame.ops, 0)
  let assert Ok(second_handler) = dict.get(second_frame.ops, 0)

  let first_result: String =
    from_dynamic(first_handler([to_dynamic("ignored")], fn(d) { d }))
  let second_result: String =
    from_dynamic(second_handler([to_dynamic("ignored")], fn(d) { d }))

  first_result |> should.equal("handled:cursor-a")
  second_result |> should.equal("handled:cursor-b")
  transcript.playback_remaining(first) |> should.equal(0)
  transcript.playback_remaining(second) |> should.equal(0)

  transcript.stop_playback(first)
  transcript.stop_playback(second)
}

fn record_one_tape(tag: String) -> transcript.Tape {
  let rec = transcript.start_with(transcript.CaptureAll)
  let assert [frame] = transcript.wrap_frames(rec, [llm_frame(echo_handler())])
  let assert Ok(handler) = dict.get(frame.ops, 0)
  let _ = handler([to_dynamic(tag)], fn(d) { d })
  let tape = transcript.capture(rec)
  transcript.stop(rec)
  tape
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
