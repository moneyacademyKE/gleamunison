import gleam/io
import gleam/list
import gleam/string

import dogfood_bench as bench
import dogfood_core as core

// Meta-test runner — executes all real levels in sequence.
// Stub levels are tracked separately via all_levels() Dict.
pub fn level70() -> Nil {
  io.println("--- Level 70: Meta-test runner ---")
  let tests: List(#(String, fn() -> Nil)) = [
    #("Level 51 (10K inserts)", bench.level51),
    #("Level 52 (DETS persist)", bench.level52),
    #("Level 53 (Partitioned DETS)", bench.level53),
    #("Level 54 (Serialization)", bench.level54),
    #("Level 55 (Large unit)", bench.level55),
    #("Level 21 (Term API)", core.level21),
    #("Level 22 (Compile & Load)", core.level22),
    #("Level 23 (Codebase round-trip)", core.level23),
    #("Level 24 (Effects runtime)", core.level24),
    #("Level 25 (/eval endpoint)", core.level25),
    #("Level 31 (Process dict state)", core.level31),
    #("Level 32 (Float parsing)", core.level32),
    #("Level 33 (Loader capacity)", core.level33),
    #("Level 34 (Concurrent access)", core.level34),
    #("Level 38 (Compiler shadowing)", core.level38),
    #("Level 41 (REPL as library)", core.level41),
    #("Level 47 (File I/O)", core.level47),
    #("Level 48 (Benchmark)", bench.level48),
    #("Level 50 (Dashboard)", bench.level50),
  ]
  let total = list.length(tests)
  io.println("Running " <> string.inspect(total) <> " real tests...")
  list.each(tests, fn(t) {
    io.print(t.0 <> "... ")
    t.1()
  })
  io.println("All " <> string.inspect(total) <> " real levels passed!")
  io.println("Level 70: OK")
}

// Expose real levels map for the Dict-based dispatch in dogfood.gleam
pub fn real_levels_list() -> List(#(String, fn() -> Nil)) {
  [
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
    #("level70", level70),
  ]
}
