//// Schema-Aligned Parsing (gap analysis concept B).
////
//// Liberal-in-what-you-accept repair of near-miss model output: fences,
//// yapping, comments, trailing commas, single quotes, unquoted keys, Python
//// literals — then strict decode, then validation against a JSON-native
//// Schema (bridged from core ast.Type). Pure Gleam, no FFI.

import gleam/bit_array
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import gleamunison/ast
import gleamunison/json

pub type Schema {
  SAny
  SInt
  SFloat
  SText
  SBool
  SList(of: Schema)
  SObj(fields: List(#(String, Schema)), required: List(String))
  SEnum(values: List(String))
}

pub type SapError {
  NoJsonFound
  StrictError(reason: String)
  ValidationFailed(paths: List(String))
}

/// Repair near-miss model output into strict JSON text.
pub fn parse(text: String) -> Result(String, SapError) {
  let unfenced = strip_fences(text)
  case extract_span(unfenced) {
    Error(e) -> Error(e)
    Ok(span) -> {
      let repaired = repair(span)
      case json.decode(bit_array.from_string(repaired)) {
        Ok(_) -> Ok(repaired)
        Error(e) -> Error(StrictError(bit_to_string(e)))
      }
    }
  }
}

/// Repair, decode, and validate against a schema.
pub fn decode_as(text: String, schema: Schema) -> Result(Dynamic, SapError) {
  case parse(text) {
    Error(e) -> Error(e)
    Ok(repaired) ->
      case json.decode(bit_array.from_string(repaired)) {
        Error(e) -> Error(StrictError(bit_to_string(e)))
        Ok(dyn) ->
          case validate(schema, dyn, "$") {
            [] -> Ok(dyn)
            paths -> Error(ValidationFailed(paths))
          }
      }
  }
}

/// Bridge from core types; unresolved constructors degrade to SAny.
pub fn schema_from_type(t: ast.Type) -> Schema {
  case t {
    ast.Builtin(ast.IntType) -> SInt
    ast.Builtin(ast.FloatType) -> SFloat
    ast.Builtin(ast.TextType) -> SText
    ast.Builtin(ast.BoolType) -> SBool
    ast.Builtin(ast.ListType) -> SList(SAny)
    _ -> SAny
  }
}

// ---------------------------------------------------------------------------
// Stage 1: fences

fn strip_fences(text: String) -> String {
  text
  |> string.split("\n")
  |> list.filter(fn(line) {
    !string.starts_with(string.trim_start(line), "```")
  })
  |> string.join("\n")
}

// ---------------------------------------------------------------------------
// Stage 2: span isolation (first balanced {..} or [..], strings respected)

fn extract_span(text: String) -> Result(String, SapError) {
  let chars = string.to_graphemes(text)
  case take_until_open(chars) {
    [] -> Error(NoJsonFound)
    span_start -> {
      case scan_balanced(span_start, 0, False, False, []) {
        Error(_) -> Error(NoJsonFound)
        Ok(collected) -> Ok(string.concat(list.reverse(collected)))
      }
    }
  }
}

fn take_until_open(chars: List(String)) -> List(String) {
  case chars {
    [] -> []
    [c, ..rest] as all ->
      case c {
        "{" | "[" -> all
        _ -> take_until_open(rest)
      }
  }
}

fn scan_balanced(
  chars: List(String),
  depth: Int,
  in_str: Bool,
  escaped: Bool,
  acc: List(String),
) -> Result(List(String), Nil) {
  case chars {
    [] -> Error(Nil)
    [c, ..rest] ->
      case in_str {
        True ->
          case escaped {
            True -> scan_balanced(rest, depth, True, False, [c, ..acc])
            False ->
              case c {
                "\\" -> scan_balanced(rest, depth, True, True, [c, ..acc])
                "\"" -> scan_balanced(rest, depth, False, False, [c, ..acc])
                _ -> scan_balanced(rest, depth, True, False, [c, ..acc])
              }
          }
        False ->
          case c {
            "\"" -> scan_balanced(rest, depth, True, False, [c, ..acc])
            "{" | "[" ->
              scan_balanced(rest, depth + 1, False, False, [c, ..acc])
            "}" | "]" ->
              case depth - 1 {
                0 -> Ok([c, ..acc])
                d -> scan_balanced(rest, d, False, False, [c, ..acc])
              }
            _ -> scan_balanced(rest, depth, False, False, [c, ..acc])
          }
      }
  }
}

// ---------------------------------------------------------------------------
// Stage 3: repair scanner (explicit recursion — lookahead needs it)

type Mode {
  Normal
  InDouble
  InSingle
}

fn repair(text: String) -> String {
  let out = repair_run(string.to_graphemes(text), Normal, [], [])
  string.concat(list.reverse(out))
}

fn repair_run(
  chars: List(String),
  mode: Mode,
  out: List(String),
  word: List(String),
) -> List(String) {
  case mode {
    InDouble ->
      case chars {
        [] -> out
        ["\\", next, ..rest] ->
          repair_run(rest, InDouble, [next, "\\", ..out], word)
        ["\"", ..rest] -> repair_run(rest, Normal, ["\"", ..out], word)
        [c, ..rest] -> repair_run(rest, InDouble, [c, ..out], word)
      }
    InSingle ->
      case chars {
        [] -> out
        ["\\", "'", ..rest] -> repair_run(rest, InSingle, ["'", ..out], word)
        ["\\", next, ..rest] ->
          repair_run(rest, InSingle, [next, "\\", ..out], word)
        ["'", ..rest] -> repair_run(rest, Normal, ["\"", ..out], word)
        ["\"", ..rest] -> repair_run(rest, InSingle, ["\\\"", ..out], word)
        [c, ..rest] -> repair_run(rest, InSingle, [c, ..out], word)
      }
    Normal ->
      case chars {
        [] -> flush_word(out, word)
        ["/", "/", ..rest] ->
          repair_run(skip_line_comment(rest), Normal, flush_word(out, word), [])
        ["/", "*", ..rest] ->
          repair_run(
            skip_block_comment(rest),
            Normal,
            flush_word(out, word),
            [],
          )
        ["\"", ..rest] ->
          repair_run(rest, InDouble, ["\"", ..flush_word(out, word)], [])
        ["'", ..rest] ->
          repair_run(rest, InSingle, ["\"", ..flush_word(out, word)], [])
        [",", ..rest] ->
          repair_run(rest, Normal, [",", ..flush_word(out, word)], [])
        [c, ..rest] if c == "{" || c == "[" ->
          repair_run(rest, Normal, [c, ..flush_word(out, word)], [])
        [c, ..rest] if c == "}" || c == "]" -> {
          let out1 = flush_word(out, word) |> drop_trailing_comma
          repair_run(rest, Normal, [c, ..out1], [])
        }
        [":", ..rest] -> {
          // a word directly before ':' is an unquoted key
          let out1 = flush_key(out, word)
          repair_run(rest, Normal, [":", ..out1], [])
        }
        [c, ..rest] ->
          case is_word_char(c) {
            True -> repair_run(rest, Normal, out, [c, ..word])
            False -> repair_run(rest, Normal, [c, ..flush_word(out, word)], [])
          }
      }
  }
}

fn is_ws_chunk(c: String) -> Bool {
  c == " " || c == "\n" || c == "\t" || c == "\r"
}

/// out is reversed (head = most recent); drop the last significant chunk if
/// it is a comma — that is exactly the trailing-comma repair.
fn drop_trailing_comma(out: List(String)) -> List(String) {
  case out {
    [] -> out
    [c, ..rest] ->
      case is_ws_chunk(c) {
        True -> [c, ..drop_trailing_comma(rest)]
        False ->
          case c {
            "," -> rest
            _ -> out
          }
      }
  }
}

fn is_word_char(c: String) -> Bool {
  string.contains(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.$-",
    c,
  )
}

fn flush_word(out: List(String), word: List(String)) -> List(String) {
  case word {
    [] -> out
    _ -> {
      let w = string.concat(list.reverse(word))
      [literal_fix(w), ..out]
    }
  }
}

fn flush_key(out: List(String), word: List(String)) -> List(String) {
  case word {
    [] -> out
    _ -> {
      let w = string.concat(list.reverse(word))
      ["\"", w, "\"", ..out]
    }
  }
}

fn literal_fix(w: String) -> String {
  case w {
    "True" -> "true"
    "False" -> "false"
    "None" -> "null"
    other -> other
  }
}

fn skip_line_comment(chars: List(String)) -> List(String) {
  case chars {
    [] -> []
    ["\n", ..] as all -> all
    [_, ..rest] -> skip_line_comment(rest)
  }
}

fn skip_block_comment(chars: List(String)) -> List(String) {
  case chars {
    [] -> []
    ["*", "/", ..rest] -> rest
    [_, ..rest] -> skip_block_comment(rest)
  }
}

// ---------------------------------------------------------------------------
// Stage 4: validation

fn validate(schema: Schema, value: Dynamic, path: String) -> List(String) {
  case schema {
    SAny -> []
    SInt ->
      case decode.run(value, decode.int) {
        Ok(_) -> []
        Error(_) -> [path <> ": expected Int"]
      }
    SFloat ->
      case decode.run(value, decode.float) {
        Ok(_) -> []
        Error(_) ->
          case decode.run(value, decode.int) {
            Ok(_) -> []
            Error(_) -> [path <> ": expected Float"]
          }
      }
    SText ->
      case decode.run(value, decode.string) {
        Ok(_) -> []
        Error(_) -> [path <> ": expected Text"]
      }
    SBool ->
      case decode.run(value, decode.bool) {
        Ok(_) -> []
        Error(_) -> [path <> ": expected Bool"]
      }
    SEnum(values) ->
      case decode.run(value, decode.string) {
        Ok(s) ->
          case list.contains(values, s) {
            True -> []
            False -> [path <> ": not one of " <> string.join(values, "|")]
          }
        Error(_) -> [path <> ": expected enum string"]
      }
    SList(inner) ->
      case decode.run(value, decode.list(decode.dynamic)) {
        Error(_) -> [path <> ": expected List"]
        Ok(items) -> {
          let indexed = list.index_map(items, fn(d, i) { #(i, d) })
          list.flat_map(indexed, fn(pair) {
            validate(inner, pair.1, path <> "[" <> int_str(pair.0) <> "]")
          })
        }
      }
    SObj(fields, required) ->
      case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
        Error(_) -> [path <> ": expected Object"]
        Ok(map) -> {
          list.flat_map(fields, fn(field) {
            let #(name, subschema) = field
            case dict.get(map, name) {
              Ok(sub) -> validate(subschema, sub, path <> "." <> name)
              Error(_) ->
                case list.contains(required, name) {
                  True -> [path <> "." <> name <> ": missing required field"]
                  False -> []
                }
            }
          })
        }
      }
  }
}

fn int_str(i: Int) -> String {
  int.to_string(i)
}

fn bit_to_string(b: BitArray) -> String {
  case bit_array.to_string(b) {
    Ok(s) -> s
    Error(_) -> "<non-utf8>"
  }
}
