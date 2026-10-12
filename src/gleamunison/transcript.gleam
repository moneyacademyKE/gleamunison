import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}

/// One recorded effect call. args/result are inspect-renderings: faithful
/// for the JSON-at-the-boundary abilities (LLM, HTTP), best-effort for
/// opaque values. Live replay uses the raw captured values, not these.
pub type OpRecord {
  OpRecord(
    ability: String,
    op: Int,
    args_repr: String,
    result_repr: String,
    seq: Int,
  )
}

/// One divergence between two transcripts.
pub type DiffEntry {
  DiffEntry(seq: Int, left: OpRecord, right: OpRecord)
}

/// The serializable artifact: what gets stored in the DAG for audit.
pub opaque type Tape {
  Tape(entries: List(OpRecord), raw: Dynamic)
}

/// Opaque handle to the process-local recording log.
pub opaque type Recorder {
  Recorder
}

/// Opaque handle to a playback cursor over raw captured values.
pub opaque type Playback {
  Playback
}

@external(erlang, "gleamunison_ffi", "to_dynamic")
fn to_dynamic(val: a) -> Dynamic

@external(erlang, "gleamunison_ffi", "from_dynamic")
fn from_dynamic(val: Dynamic) -> a

@external(erlang, "gleamunison_transcript", "log_start")
fn log_start() -> Nil

@external(erlang, "gleamunison_transcript", "log_append")
fn log_append(ability: String, op: Int, args: Dynamic, result: Dynamic) -> Nil

@external(erlang, "gleamunison_transcript", "log_entries")
fn log_entries() -> Dynamic

@external(erlang, "gleamunison_transcript", "log_stop")
fn log_stop() -> Nil

@external(erlang, "gleamunison_transcript", "pb_start")
fn pb_start(entries: Dynamic) -> Nil

@external(erlang, "gleamunison_transcript", "pb_next")
fn pb_next(ability: String, op: Int) -> Result(Dynamic, Dynamic)

@external(erlang, "gleamunison_transcript", "pb_remaining")
fn pb_remaining() -> Int

@external(erlang, "gleamunison_transcript", "pb_stop")
fn pb_stop() -> Nil

pub fn start() -> Recorder {
  log_start()
  Recorder
}

pub fn stop(_rec: Recorder) -> Nil {
  log_stop()
}

/// Wrap every op handler in every frame: each call is appended to the log
/// with its ability key, op index, raw args and raw result. The recorded
/// result is what the inner handler passes to the continuation.
pub fn wrap_frames(
  rec: Recorder,
  frames: List(HandlerFrame),
) -> List(HandlerFrame) {
  list.map(frames, fn(frame) {
    let key = effects.ability_key(frame.ability)
    HandlerFrame(
      ability: frame.ability,
      ops: dict.map_values(frame.ops, fn(op_idx, inner) {
        wrap_op(rec, key, op_idx, inner)
      }),
    )
  })
}

fn wrap_op(
  _rec: Recorder,
  key: String,
  op_idx: Int,
  inner: OpHandler,
) -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    inner(args, fn(result) {
      log_append(key, op_idx, to_dynamic(args), result)
      cont(result)
    })
  }
}

/// Entries recorded so far, in call order (inspect-rendered view).
pub fn entries(rec: Recorder) -> List(OpRecord) {
  tape_entries(capture(rec))
}

/// Capture the log as a Tape: serializable entries plus the raw values
/// needed for in-process replay.
pub fn capture(_rec: Recorder) -> Tape {
  let raw = log_entries()
  Tape(entries: decode_entries(raw), raw: raw)
}

/// Entries of a tape in call order.
pub fn tape_entries(tape: Tape) -> List(OpRecord) {
  tape.entries
}

/// Build a tape from bare entries (no raw values: audit/diff only,
/// playback from it is empty by construction).
pub fn from_entries(entries: List(OpRecord)) -> Tape {
  Tape(entries: entries, raw: to_dynamic([]))
}

fn decode_entries(raw: Dynamic) -> List(OpRecord) {
  from_dynamic(raw)
  |> list.map(fn(entry) {
    let #(ability, op, args, result, seq) = entry
    OpRecord(
      ability: ability,
      op: op,
      args_repr: string.inspect(args),
      result_repr: string.inspect(result),
      seq: seq,
    )
  })
}

/// Start replaying a tape. Replay consumes raw captured values in order;
/// a tape built from JSON or from_entries has no raw values and replays
/// as exhausted.
pub fn playback(tape: Tape) -> Playback {
  pb_start(tape.raw)
  Playback
}

pub fn stop_playback(_pb: Playback) -> Nil {
  pb_stop()
}

pub fn playback_remaining(_pb: Playback) -> Int {
  pb_remaining()
}

/// Frames whose handlers serve recorded results in order, never calling
/// the inner handler. A mismatch or exhausted tape raises: replay is for
/// verification, and silent drift must be loud.
pub fn replay_frames(
  _pb: Playback,
  frames: List(HandlerFrame),
) -> List(HandlerFrame) {
  list.map(frames, fn(frame) {
    let key = effects.ability_key(frame.ability)
    HandlerFrame(
      ability: frame.ability,
      ops: dict.map_values(frame.ops, fn(op_idx, _inner) {
        fn(_args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
          case pb_next(key, op_idx) {
            Ok(recorded) -> cont(recorded)
            Error(_) -> panic as "transcript replay: no recorded op"
          }
        }
      }),
    )
  })
}

/// First-divergence diff between two tapes, aligned by seq.
pub fn diff(a: Tape, b: Tape) -> List(DiffEntry) {
  list.zip(a.entries, b.entries)
  |> list.filter_map(fn(pair) {
    let #(l, r) = pair
    case
      l.ability == r.ability
      && l.op == r.op
      && l.args_repr == r.args_repr
      && l.result_repr == r.result_repr
    {
      True -> Error(Nil)
      False -> Ok(DiffEntry(seq: l.seq, left: l, right: r))
    }
  })
}

fn jstr(s: String) -> String {
  let escaped =
    s
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\n")
  "\"" <> escaped <> "\""
}

/// Audit serialization: one JSON object per entry, in order.
pub fn to_json(tape: Tape) -> String {
  let body =
    list.map(tape.entries, fn(e) {
      "{\"ability\":"
      <> jstr(e.ability)
      <> ",\"op\":"
      <> int.to_string(e.op)
      <> ",\"args\":"
      <> jstr(e.args_repr)
      <> ",\"result\":"
      <> jstr(e.result_repr)
      <> ",\"seq\":"
      <> int.to_string(e.seq)
      <> "}"
    })
  "[" <> string.join(body, ",") <> "]"
}

/// Parse an audit JSON tape. Entry fields decode as strings; a malformed
/// payload is an Error, never a partial tape.
pub fn from_json(json: String) -> Result(Tape, String) {
  use entries <- result.try(parse_entries(json, []))
  Ok(from_entries(entries))
}

fn parse_entries(
  json: String,
  acc: List(OpRecord),
) -> Result(List(OpRecord), String) {
  let trimmed = string.trim(json)
  case trimmed {
    "[]" -> Ok(list.reverse(acc))
    "[" <> rest -> parse_entry_list(string.trim(rest), acc)
    _ -> Error("transcript.from_json: expected a JSON array")
  }
}

fn parse_entry_list(
  s: String,
  acc: List(OpRecord),
) -> Result(List(OpRecord), String) {
  case s {
    "]" -> Ok(list.reverse(acc))
    _ -> {
      use #(entry, rest) <- result.try(parse_one_entry(s, ""))
      let next = string.trim(rest)
      case next {
        "," <> more -> parse_entry_list(string.trim(more), [entry, ..acc])
        "]" -> Ok(list.reverse([entry, ..acc]))
        _ -> Error("transcript.from_json: expected ',' or ']'")
      }
    }
  }
}

fn parse_one_entry(
  s: String,
  _acc: String,
) -> Result(#(OpRecord, String), String) {
  use #(ability, r1) <- result.try(field_string(s, "ability"))
  use #(op, r2) <- result.try(field_int(r1, "op"))
  use #(args, r3) <- result.try(field_string(r2, "args"))
  use #(result_repr, r4) <- result.try(field_string(r3, "result"))
  use #(seq, r5) <- result.try(field_int(r4, "seq"))
  let rest = case string.trim(r5) {
    "}" <> tail -> tail
    other -> other
  }
  Ok(#(OpRecord(ability, op, args, result_repr, seq), rest))
}

fn skip_to_field(s: String, name: String) -> Result(String, String) {
  let needle = "\"" <> name <> "\":"
  case string.split_once(s, needle) {
    Ok(#(_, after)) -> Ok(after)
    Error(_) -> Error("transcript.from_json: missing field " <> name)
  }
}

fn field_string(s: String, name: String) -> Result(#(String, String), String) {
  use after <- result.try(skip_to_field(s, name))
  parse_json_string(string.trim(after))
}

fn field_int(s: String, name: String) -> Result(#(Int, String), String) {
  use after <- result.try(skip_to_field(s, name))
  let trimmed = string.trim(after)
  let digits =
    string.to_graphemes(trimmed)
    |> list.take_while(fn(c) {
      case int.parse(c) {
        Ok(_) -> True
        Error(_) -> False
      }
    })
    |> string.concat
  case int.parse(digits) {
    Ok(n) -> Ok(#(n, string.drop_start(trimmed, string.length(digits))))
    Error(_) -> Error("transcript.from_json: bad int for " <> name)
  }
}

fn parse_json_string(s: String) -> Result(#(String, String), String) {
  case s {
    "\"" <> rest -> scan_string(rest, "")
    _ -> Error("transcript.from_json: expected string")
  }
}

fn scan_string(s: String, acc: String) -> Result(#(String, String), String) {
  case string.pop_grapheme(s) {
    Ok(#("\\", rest)) -> {
      case string.pop_grapheme(rest) {
        Ok(#("n", r2)) -> scan_string(r2, acc <> "\n")
        Ok(#("\"", r2)) -> scan_string(r2, acc <> "\"")
        Ok(#("\\", r2)) -> scan_string(r2, acc <> "\\")
        Ok(#(c, r2)) -> scan_string(r2, acc <> c)
        Error(_) -> Error("transcript.from_json: unterminated escape")
      }
    }
    Ok(#("\"", rest)) -> Ok(#(acc, rest))
    Ok(#(c, rest)) -> scan_string(rest, acc <> c)
    Error(_) -> Error("transcript.from_json: unterminated string")
  }
}
