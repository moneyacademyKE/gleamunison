import dogfood_meta as meta
import gleam/dict.{type Dict}
import gleam/int
import gleam/list

fn generic_computation(n: Int) -> fn() -> Nil {
  fn() {
    case n % 5 {
      0 -> meta.generic_parse_level(n)
      1 -> meta.generic_hash_level(n)
      2 -> meta.generic_insert_level(n)
      3 -> meta.generic_infer_level(n)
      4 -> meta.generic_eval_level(n)
      _ -> meta.generic_hash_level(n)
    }
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
    list.filter_map(range(1, 6697), fn(n) {
      let key = "level" <> int.to_string(n)
      case list.contains(real_keys, key) || key == "level70" {
        True -> Error(Nil)
        False -> Ok(#(key, generic_computation(n)))
      }
    })
  dict.from_list(list.append(real, stubs))
}
