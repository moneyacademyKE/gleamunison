import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/string
import gleamunison/dynamic_ffi.{from_dynamic, to_dynamic}
import gleamunison/effects.{type HandlerFrame, type OpHandler, HandlerFrame}
import gleamunison/json
import gleamunison/llm

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

/// Capture policy: the default redacts privacy-sensitive ability payloads
/// at capture time; CaptureAll is the explicit opt-in for deliberate
/// fixture recording (tape-to-test), whose artifacts are committed by hand.
pub type CapturePolicy {
  RedactPrivate
  CaptureAll
}

/// Opaque handle to one process-local recording log.
///
/// The token is the actual process-dictionary key, so two recorders in the
/// same process own separate tapes.
pub opaque type Recorder {
  Recorder(policy: CapturePolicy, token: Dynamic)
}

/// Opaque handle to one playback cursor over raw captured values.
///
/// The token is the actual process-dictionary cursor key, so two playbacks
/// in the same process cannot consume each other's entries.
pub opaque type Playback {
  Playback(token: Dynamic)
}

@external(erlang, "gleamunison_transcript", "new_token")
fn new_token() -> Dynamic

@external(erlang, "gleamunison_transcript", "log_start")
fn log_start(token: Dynamic) -> Nil

@external(erlang, "gleamunison_transcript", "log_append")
fn log_append(
  token: Dynamic,
  ability: String,
  op: Int,
  args: Dynamic,
  result: Dynamic,
) -> Nil

@external(erlang, "gleamunison_transcript", "log_entries")
fn log_entries(token: Dynamic) -> Dynamic

@external(erlang, "gleamunison_transcript", "log_stop")
fn log_stop(token: Dynamic) -> Nil

@external(erlang, "gleamunison_transcript", "pb_start")
fn pb_start(token: Dynamic, entries: Dynamic) -> Nil

@external(erlang, "gleamunison_transcript", "pb_next")
fn pb_next(token: Dynamic, ability: String, op: Int) -> Result(Dynamic, Dynamic)

@external(erlang, "gleamunison_transcript", "pb_remaining")
fn pb_remaining(token: Dynamic) -> Int

@external(erlang, "gleamunison_transcript", "pb_stop")
fn pb_stop(token: Dynamic) -> Nil

pub fn start() -> Recorder {
  start_with(RedactPrivate)
}

/// Deliberate full capture: fixture recording (tape-to-test) and replay
/// auditing. Artifacts contain whatever the recorded code sent — never run
/// this against prompts or sources you would not commit.
pub fn start_with(policy: CapturePolicy) -> Recorder {
  let token = new_token()
  log_start(token)
  Recorder(policy:, token:)
}

pub fn stop(rec: Recorder) -> Nil {
  log_stop(rec.token)
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
  rec: Recorder,
  key: String,
  op_idx: Int,
  inner: OpHandler,
) -> OpHandler {
  fn(args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
    inner(args, fn(result) {
      // Redaction boundary at capture: under the default policy,
      // privacy-sensitive abilities record that the call happened (ability,
      // op, sequence) but never their payload — prompts and completions
      // never reach a durable artifact.
      case rec.policy, is_private_ability(key) {
        RedactPrivate, True ->
          log_append(
            rec.token,
            key,
            op_idx,
            redacted_marker(),
            redacted_marker(),
          )
        _, _ -> log_append(rec.token, key, op_idx, to_dynamic(args), result)
      }
      cont(result)
    })
  }
}

/// The privacy set is named ability refs, computed the same way the runtime
/// keys frames. Today: exactly the LLM ability.
fn is_private_ability(key: String) -> Bool {
  key == effects.ability_key(llm.ability_ref())
}

fn redacted_marker() -> Dynamic {
  to_dynamic("[redacted:private-ability-payload]")
}

/// Entries recorded so far, in call order (inspect-rendered view).
pub fn entries(rec: Recorder) -> List(OpRecord) {
  tape_entries(capture(rec))
}

/// Capture the log as a Tape: serializable entries plus the raw values
/// needed for in-process replay.
pub fn capture(rec: Recorder) -> Tape {
  let raw = log_entries(rec.token)
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

/// Build a tape from entries plus their rebuilt raw payloads — the v2
/// reader's counterpart to from_entries (the Tape constructor is opaque,
/// so tape assembly stays inside this module).
pub fn from_entries_and_raw(entries: List(OpRecord), raw: Dynamic) -> Tape {
  Tape(entries: entries, raw: raw)
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
  let token = new_token()
  pb_start(token, tape.raw)
  Playback(token:)
}

pub fn stop_playback(pb: Playback) -> Nil {
  pb_stop(pb.token)
}

pub fn playback_remaining(pb: Playback) -> Int {
  pb_remaining(pb.token)
}

/// Frames whose handlers serve recorded results in order, never calling
/// the inner handler. A mismatch or exhausted tape raises: replay is for
/// verification, and silent drift must be loud.
pub fn replay_frames(
  pb: Playback,
  frames: List(HandlerFrame),
) -> List(HandlerFrame) {
  list.map(frames, fn(frame) {
    let key = effects.ability_key(frame.ability)
    HandlerFrame(
      ability: frame.ability,
      ops: dict.map_values(frame.ops, fn(op_idx, _inner) {
        fn(_args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic {
          case pb_next(pb.token, key, op_idx) {
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

/// Audit serialization: one JSON object per entry, in order.
@external(erlang, "gleamunison_transcript", "term_to_b64")
fn term_to_b64(term: Dynamic) -> String

@external(erlang, "gleamunison_transcript", "run_replay")
fn run_replay_ffi(token: Dynamic, entries: Dynamic, thunk: fn() -> a) -> a

/// Serialize a tape for audit AND replay: alongside the human-readable
/// reprs, each entry carries base64 term_to_binary blobs of the raw args
/// and result. A tape loaded back from this format replays for real.
/// Tapes built from_entries (no raw) serialize in the old audit-only shape.
pub fn to_json(tape: Tape) -> String {
  let raw_by_seq = raw_index(tape.raw)
  let body =
    list.map(tape.entries, fn(e) {
      let base =
        "{\"ability\":"
        <> json.json_quote(e.ability)
        <> ",\"op\":"
        <> int.to_string(e.op)
        <> ",\"args\":"
        <> json.json_quote(e.args_repr)
        <> ",\"result\":"
        <> json.json_quote(e.result_repr)
        <> ",\"seq\":"
        <> int.to_string(e.seq)
      case dict.get(raw_by_seq, e.seq) {
        Error(_) -> base <> "}"
        Ok(#(args, result)) ->
          base
          <> ",\"args_b64\":"
          <> json.json_quote(term_to_b64(args))
          <> ",\"result_b64\":"
          <> json.json_quote(term_to_b64(result))
          <> "}"
      }
    })
  "[" <> string.join(body, ",") <> "]"
}

fn raw_index(raw: Dynamic) -> dict.Dict(Int, #(Dynamic, Dynamic)) {
  let entries: List(#(String, Int, Dynamic, Dynamic, Int)) = from_dynamic(raw)
  list.fold(entries, dict.new(), fn(acc, entry) {
    dict.insert(acc, entry.4, #(entry.2, entry.3))
  })
}

/// True when the tape carries raw values and can drive a real replay.
/// A tape containing redacted entries is NOT replayable: their payloads
/// were removed at capture, so replay would return markers instead of
/// completions. Run those live. (CaptureAll tapes carry real payloads and
/// stay replayable.)
pub fn is_replayable(tape: Tape) -> Bool {
  let raw: List(Dynamic) = from_dynamic(tape.raw)
  raw != []
  && !list.any(tape_entries(tape), fn(e) {
    string.contains(e.args_repr, "redacted:private-ability-payload")
  })
}

/// Run a thunk under playback of the tape. Divergence from the recorded
/// call sequence raises; the tape must be replayable (is_replayable).
pub fn run_with_playback(tape: Tape, thunk: fn() -> a) -> a {
  let token = new_token()
  pb_start(token, tape.raw)
  let result = run_replay_ffi(token, tape.raw, thunk)
  pb_stop(token)
  result
}
