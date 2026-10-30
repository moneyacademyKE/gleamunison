//// Audit tape reader: the from_json half of the transcript serialization
//// contract. transcript.gleam owns capture/playback and the writer
//// (to_json); this module owns parsing tape files back into Tape values.
//// Split so both halves stay under the LOC ceiling and each has one job:
//// JSON text in, all-or-nothing Tape out.
////
//// The writer escapes via json.json_quote, so this reader understands every
//// escape the JSON boundary can emit — \r, \t, and C0 controls as \uXXXX —
//// and stays lenient about raw control characters: legacy audit files
//// written before the escaper fix contain them, and a tape that loads is a
//// tape that can replay.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleamunison/dynamic_ffi.{to_dynamic}
import gleamunison/json
import gleamunison/transcript.{
  type OpRecord, type Tape, OpRecord, from_entries, from_entries_and_raw,
}

@external(erlang, "gleamunison_transcript", "b64_to_term")
fn b64_to_term(b64: String) -> Dynamic

/// Parse a tape file. Entry fields decode as strings; a malformed payload
/// is an Error, never a partial tape. When every entry carries v2 base64
/// blobs, the raw values are rebuilt and the tape replays for real;
/// otherwise it loads audit-only (all-or-nothing: a half-raw tape is a
/// lie about which run it records).
pub fn from_json(text: String) -> Result(Tape, String) {
  use parsed <- result.try(parse_entries(text, []))
  let entries = list.map(parsed, fn(pair) { pair.0 })
  let blobs = list.map(parsed, fn(pair) { pair.1 })
  case list.all(blobs, fn(b) { b != option.None }) {
    False -> Ok(from_entries(entries))
    True -> {
      let raw =
        list.map(list.zip(entries, blobs), fn(pair) {
          let assert option.Some(#(args_b64, result_b64)) = pair.1
          #(
            pair.0.ability,
            pair.0.op,
            b64_to_term(args_b64),
            b64_to_term(result_b64),
            pair.0.seq,
          )
        })
      Ok(from_entries_and_raw(entries, to_dynamic(raw)))
    }
  }
}

fn parse_entries(
  text: String,
  acc: List(#(OpRecord, Option(#(String, String)))),
) -> Result(List(#(OpRecord, Option(#(String, String)))), String) {
  let trimmed = string.trim(text)
  case trimmed {
    "[]" -> Ok(list.reverse(acc))
    "[" <> rest -> parse_entry_list(string.trim(rest), acc)
    _ -> Error("transcript.from_json: expected a JSON array")
  }
}

fn parse_entry_list(
  s: String,
  acc: List(#(OpRecord, Option(#(String, String)))),
) -> Result(List(#(OpRecord, Option(#(String, String)))), String) {
  case s {
    "]" -> Ok(list.reverse(acc))
    _ -> {
      use #(entry, b64, rest) <- result.try(parse_one_entry(s, ""))
      let next = string.trim(rest)
      case next {
        "," <> more ->
          parse_entry_list(string.trim(more), [#(entry, b64), ..acc])
        "]" -> Ok(list.reverse([#(entry, b64), ..acc]))
        _ -> Error("transcript.from_json: expected ',' or ']'")
      }
    }
  }
}

fn parse_one_entry(
  s: String,
  _acc: String,
) -> Result(#(OpRecord, Option(#(String, String)), String), String) {
  use #(ability, r1) <- result.try(field_string(s, "ability"))
  use #(op, r2) <- result.try(field_int(r1, "op"))
  use #(args, r3) <- result.try(field_string(r2, "args"))
  use #(result_repr, r4) <- result.try(field_string(r3, "result"))
  use #(seq, r5) <- result.try(field_int(r4, "seq"))
  let trimmed = string.trim(r5)
  // v2 tapes carry base64 term_to_binary blobs of the raw args/result
  // after seq; v1 (audit-only) entries end the object there.
  case string.starts_with(trimmed, ",") {
    False -> {
      let rest = case trimmed {
        "}" <> tail -> tail
        other -> other
      }
      Ok(#(OpRecord(ability, op, args, result_repr, seq), option.None, rest))
    }
    True -> {
      use #(args_b64, r6) <- result.try(field_string(trimmed, "args_b64"))
      use #(result_b64, r7) <- result.try(field_string(r6, "result_b64"))
      let rest = case string.trim(r7) {
        "}" <> tail -> tail
        other -> other
      }
      Ok(#(
        OpRecord(ability, op, args, result_repr, seq),
        option.Some(#(args_b64, result_b64)),
        rest,
      ))
    }
  }
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

/// Scan one JSON string body (after the opening quote) to its closing
/// quote, unescaping as it goes. Handles every escape the writer can emit:
/// \r and \t directly, C0 controls as \uXXXX. Unknown escapes keep their
/// character (lenient), and raw control characters pass through untouched:
/// legacy audit files written before the escaper fix contain them, and
/// refusing to load a readable tape helps no one.
fn scan_string(s: String, acc: String) -> Result(#(String, String), String) {
  case string.pop_grapheme(s) {
    Ok(#("\\", rest)) -> {
      case string.pop_grapheme(rest) {
        Ok(#("n", r2)) -> scan_string(r2, acc <> "\n")
        Ok(#("r", r2)) -> scan_string(r2, acc <> "\r")
        Ok(#("t", r2)) -> scan_string(r2, acc <> "\t")
        Ok(#("b", r2)) -> scan_string(r2, acc <> "\u{8}")
        Ok(#("f", r2)) -> scan_string(r2, acc <> "\u{c}")
        Ok(#("\"", r2)) -> scan_string(r2, acc <> "\"")
        Ok(#("\\", r2)) -> scan_string(r2, acc <> "\\")
        Ok(#("u", r2)) -> {
          use #(hex4, r3) <- result.try(take_graphemes(r2, 4, ""))
          use ch <- result.try(decode_unicode_escape(hex4))
          scan_string(r3, acc <> ch)
        }
        Ok(#(c, r2)) -> scan_string(r2, acc <> c)
        Error(_) -> Error("transcript.from_json: unterminated escape")
      }
    }
    Ok(#("\"", rest)) -> Ok(#(acc, rest))
    Ok(#(c, rest)) -> scan_string(rest, acc <> c)
    Error(_) -> Error("transcript.from_json: unterminated string")
  }
}

fn take_graphemes(
  s: String,
  n: Int,
  acc: String,
) -> Result(#(String, String), String) {
  case n <= 0 {
    True -> Ok(#(acc, s))
    False ->
      case string.pop_grapheme(s) {
        Ok(#(c, rest)) -> take_graphemes(rest, n - 1, acc <> c)
        Error(_) -> Error("transcript.from_json: truncated \\u escape")
      }
  }
}

/// \uXXXX decoding delegates to the JSON codec instead of re-deriving
/// UTF-8 here: one owner for JSON string semantics, reader included.
fn decode_unicode_escape(hex4: String) -> Result(String, String) {
  let quoted = "\"\\u" <> hex4 <> "\""
  case json.decode(bit_array.from_string(quoted)) {
    Error(_) -> Error("transcript.from_json: bad \\u escape")
    Ok(dyn) ->
      case decode.run(dyn, decode.string) {
        Ok(ch) -> Ok(ch)
        Error(_) -> Error("transcript.from_json: bad \\u escape")
      }
  }
}
