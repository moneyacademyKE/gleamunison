import dogfood_data
import dogfood_runner
import gleam/int
import gleam/io
import gleam/list

@external(erlang, "gleamunison_ffi", "halt_failure")
fn halt_failure() -> Nil

/// Level 70 runs every certification level (n % 50 == 0). A missing data
/// file is a failure, not an empty run: this used to print
/// "All certification levels passed!" after loading nothing.
pub fn level70() -> Nil {
  io.println("--- Level 70: Meta-test runner ---")
  case dogfood_data.load_levels_resolved() {
    Ok(levels) -> {
      io.println("Loaded " <> int.to_string(list.length(levels)) <> " levels.")
      let certs = list.filter(levels, fn(lvl) { level_number(lvl) % 50 == 0 })
      list.each(certs, fn(lvl) { dogfood_runner.run_level(lvl) })
      io.println("All certification levels passed!")
      io.println("Level 70: OK")
    }
    Error(e) -> {
      io.println("Failed to load levels: " <> e)
      halt_failure()
    }
  }
}

/// The implemented levels, in dispatch order. Error rather than an empty
/// list when the data file cannot be read.
pub fn real_levels_list() -> Result(List(#(String, fn() -> Nil)), String) {
  case dogfood_data.load_levels_resolved() {
    Ok(levels) ->
      Ok(
        list.map(levels, fn(lvl) {
          #("level" <> int.to_string(level_number(lvl)), fn() {
            dogfood_runner.run_level(lvl)
          })
        }),
      )
    Error(e) -> Error(e)
  }
}

fn level_number(lvl: dogfood_data.LevelData) -> Int {
  case lvl {
    dogfood_data.CompileInt(n, _) -> n
    dogfood_data.CompileFloat(n, _) -> n
    dogfood_data.CompileText(n, _) -> n
    dogfood_data.LambdaApply(n, _) -> n
    dogfood_data.CompileLet(n, _) -> n
    dogfood_data.CompileList(n, _) -> n
    dogfood_data.Elaborate(n, _) -> n
    dogfood_data.LoaderLimit(n, _, _) -> n
    dogfood_data.CodebaseInsert(n, _, _) -> n
    dogfood_data.StorageStress(n, _) -> n
    dogfood_data.CrossRef(n, _) -> n
    dogfood_data.EffectsHandle(n, _) -> n
    dogfood_data.ElabUnitAbilities(n, _) -> n
    dogfood_data.Typecheck(n, _, _) -> n
    dogfood_data.LoaderLoaded(n, _) -> n
    dogfood_data.HashDistinct(n, _, _) -> n
    dogfood_data.InsertRaw(n) -> n
    dogfood_data.ReplEval(n, _) -> n
    dogfood_data.Serialize(n, _) -> n
    dogfood_data.EmptyList(n) -> n
    dogfood_data.ElabError(n, _) -> n
    dogfood_data.CompileConstruct(n) -> n
    dogfood_data.TypePretty(n, _, _) -> n
    dogfood_data.InferTerm(n, _, _) -> n
  }
}
