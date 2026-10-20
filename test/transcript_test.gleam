import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/llm
import gleamunison/transcript.{OpRecord}
import gleeunit/should

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn unsafe_coerce(val: Dynamic) -> a

fn echo_handler() -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    let arg0: List(String) = unsafe_coerce(to_dynamic(args))
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
  let assert Ok(t2) = transcript.from_json(json)
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
  let assert Ok(loaded) = transcript.from_json(json)
  transcript.is_replayable(loaded) |> should.be_true
  let pb = transcript.playback(loaded)
  let replayed = transcript.replay_frames(pb, [llm_frame(boom_handler())])
  let assert [rframe] = replayed
  let assert Ok(rhandler) = dict.get(rframe.ops, 0)
  let result = rhandler([to_dynamic("hello")], fn(d) { d })
  let decoded: String = unsafe_coerce(result)
  decoded |> should.equal("handled:hello")
  transcript.stop_playback(pb)
  transcript.stop(rec)
}

pub fn v1_tape_loads_audit_only_test() {
  let v1 =
    "[{\"ability\":\"m_abcd1234\",\"op\":0,\"args\":\"x\",\"result\":\"y\",\"seq\":0}]"
  let assert Ok(tape) = transcript.from_json(v1)
  transcript.is_replayable(tape) |> should.be_false
}
