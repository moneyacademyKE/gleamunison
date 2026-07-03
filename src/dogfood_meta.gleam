import dogfood_data
import dogfood_runner
import gleam/int
import gleam/io
import gleam/list

pub fn generic_hash_level(_n: Int) -> Nil {
  io.println("stub: hash")
}

pub fn generic_parse_level(_n: Int) -> Nil {
  io.println("stub: parse")
}

pub fn generic_eval_level(_n: Int) -> Nil {
  io.println("stub: eval")
}

pub fn generic_insert_level(_n: Int) -> Nil {
  io.println("stub: insert")
}

pub fn generic_infer_level(_n: Int) -> Nil {
  io.println("stub: infer")
}

pub fn level70() -> Nil {
  io.println("--- Level 70: Meta-test runner ---")
  case dogfood_data.load_levels("src/dogfood_data.json") {
    Ok(levels) -> {
      let total = list.length(levels)
      io.println("Loaded " <> int.to_string(total) <> " levels.")
      let certs =
        list.filter(levels, fn(lvl) {
          let n = case lvl {
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
          n % 50 == 0
        })
      list.each(certs, fn(lvl) { dogfood_runner.run_level(lvl) })
      io.println("All certification levels passed!")
      io.println("Level 70: OK")
    }
    Error(e) -> io.println("Failed to load levels: " <> e)
  }
}

pub fn real_levels_list() -> List(#(String, fn() -> Nil)) {
  case dogfood_data.load_levels("src/dogfood_data.json") {
    Ok(levels) -> {
      list.map(levels, fn(lvl) {
        let n = case lvl {
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
        #("level" <> int.to_string(n), fn() { dogfood_runner.run_level(lvl) })
      })
    }
    Error(_) -> []
  }
}
