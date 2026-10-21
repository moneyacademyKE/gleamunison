import dogfood_bench as bench
import dogfood_core as core
import dogfood_meta as meta
import gleam/dict.{type Dict}
import gleam/list

/// Every implemented level, keyed by command name.
///
/// There are no synthetic entries: a level that has no implementation is
/// absent, so dispatch reports "unknown command" instead of running a stub
/// that prints "stub: parse" and exits zero.
pub fn all_levels() -> Result(Dict(String, fn() -> Nil), String) {
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
  case meta.real_levels_list() {
    Ok(real) -> Ok(dict.from_list(list.append(real, hand_crafted)))
    Error(e) -> Error(e)
  }
}
