import dogfood_bench as bench
import dogfood_core as core
import dogfood_meta as meta
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleamunison/util.{range}

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

pub fn all_levels() -> Dict(String, fn() -> Nil) {
  let hand_crafted = [
    #("level21", core.level21),
    #("level22", core.level22),
    #("level23", core.level23),
    #("level24", core.level24),
    #("level25", core.level25),
    #("level31", core.level31),
    #("level32", core.level32),
    #("level33", core.level33),
    #("level34", core.level34),
    #("level38", core.level38),
    #("level41", core.level41),
    #("level47", core.level47),
    #("level48", bench.level48),
    #("level49", bench.level49),
    #("level50", bench.level50),
    #("level51", bench.level51),
    #("level52", bench.level52),
    #("level53", bench.level53),
    #("level54", bench.level54),
    #("level55", bench.level55),
    #("level70", meta.level70),
  ]
  let real = list.append(meta.real_levels_list(), hand_crafted)
  let real_keys = list.map(real, fn(p) { p.0 })
  let stubs =
    list.filter_map(range(1, 6697), fn(n) {
      let key = "level" <> int.to_string(n)
      case list.contains(real_keys, key) {
        True -> Error(Nil)
        False -> Ok(#(key, generic_computation(n)))
      }
    })
  dict.from_list(list.append(real, stubs))
}
