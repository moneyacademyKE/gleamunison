import gleam/list
import gleam/string

pub opaque type Path {
  Path(parts: List(String), absolute: Bool)
}

pub fn root() -> Path {
  Path([], True)
}

pub fn from_string(input: String) -> Path {
  case string.starts_with(input, "/") {
    True -> {
      let rest = string.slice(input, 1, string.length(input) - 1)
      Path(normalize_parts(rest), True)
    }
    False -> Path(normalize_parts(input), False)
  }
}

pub fn to_string(path: Path) -> String {
  let joined = string.join(list.reverse(path.parts), "/")
  case path.absolute {
    True -> "/" <> joined
    False -> joined
  }
}

pub fn join(path: Path, segment: String) -> Path {
  case path {
    Path([], abs) -> Path(normalize_parts(segment), abs)
    Path(parts, abs) -> {
      let new_parts = list.append(list.reverse(normalize_parts(segment)), parts)
      Path(new_parts, abs)
    }
  }
}

pub fn parent(path: Path) -> Path {
  case path.parts {
    [] | [_] -> Path([], path.absolute)
    [_, ..rest] -> Path(rest, path.absolute)
  }
}

pub fn file_name(path: Path) -> String {
  case path.parts {
    [] -> ""
    [name, ..] -> name
  }
}

pub fn extension(path: Path) -> String {
  let name = file_name(path)
  case string.contains(name, ".") {
    True -> {
      let parts = string.split(name, ".")
      case list.last(parts) {
        Ok(ext) -> ext
        Error(_) -> ""
      }
    }
    False -> ""
  }
}

pub fn has_extension(path: Path, ext: String) -> Bool {
  extension(path) == ext
}

fn normalize_parts(input: String) -> List(String) {
  input
  |> string.split("/")
  |> list.filter(fn(s) { s != "" && s != "." })
}

pub fn is_absolute(path: Path) -> Bool {
  path.absolute
}

pub fn with_extension(path: Path, new_ext: String) -> Path {
  let name = file_name(path)
  let base = case string.contains(name, ".") {
    True -> {
      let parts = string.split(name, ".")
      case parts {
        [first, ..] -> first
        [] -> name
      }
    }
    False -> name
  }
  case path.parts {
    [] -> Path([base <> "." <> new_ext], path.absolute)
    [_, ..rest] -> Path([base <> "." <> new_ext, ..rest], path.absolute)
  }
}
