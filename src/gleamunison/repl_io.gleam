import gleam/string

@external(erlang, "gleamunison_repl_ffi", "read_line")
pub fn read_line(prompt: String) -> Result(String, Nil)

pub fn count_brackets(str: String, in_string: Bool, depth: Int) -> Int {
  case string.pop_grapheme(str) {
    Ok(#("(", rest)) -> case in_string {
      True -> count_brackets(rest, True, depth)
      False -> count_brackets(rest, False, depth + 1)
    }
    Ok(#(")", rest)) -> case in_string {
      True -> count_brackets(rest, True, depth)
      False -> count_brackets(rest, False, depth - 1)
    }
    Ok(#("\"", rest)) -> count_brackets(rest, !in_string, depth)
    Ok(#("'", rest)) -> {
      case in_string {
        True -> count_brackets(rest, True, depth)
        False -> count_brackets(rest, False, depth)
      }
    }
    Ok(#("\\", rest)) -> {
      case string.pop_grapheme(rest) {
        Ok(#(_, rest2)) -> count_brackets(rest2, in_string, depth)
        Error(Nil) -> depth
      }
    }
    Ok(#(_, rest)) -> count_brackets(rest, in_string, depth)
    Error(Nil) -> depth
  }
}

pub fn read_expression() -> Result(String, Nil) {
  case read_line("gleamunison> ") {
    Error(_) -> Error(Nil)
    Ok(first) -> accumulate_expr(string.trim(first))
  }
}

fn accumulate_expr(acc: String) -> Result(String, Nil) {
  case count_brackets(acc, False, 0) {
    0 -> Ok(acc)
    _ -> {
      case read_line("...> ") {
        Error(_) -> Ok(acc)
        Ok(next) -> accumulate_expr(acc <> "\n" <> next)
      }
    }
  }
}
