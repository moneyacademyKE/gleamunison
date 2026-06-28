import dogfood_meta as meta
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list

fn stub(n: Int) -> fn() -> Nil {
  fn() {
    io.println("--- Level " <> int.to_string(n) <> " [stub] ---")
    io.println("Level " <> int.to_string(n) <> ": stub (not yet implemented)")
  }
}

fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}

pub fn all_levels() -> Dict(String, fn() -> Nil) {
  let real = meta.real_levels_list()
  let real_keys = list.map(real, fn(p) { p.0 })
  let stubs =
    list.filter_map(range(1, 1051), fn(n) {
      let key = "level" <> int.to_string(n)
      case list.contains(real_keys, key) {
        True -> Error(Nil)
        False -> Ok(#(key, stub(n)))
      }
    })
  dict.from_list(list.append(real, stubs))
}
