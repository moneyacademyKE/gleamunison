import gleamunison/cli_publish
import gleamunison/elab_types.{SApply, SDo, SLambda, SText, SVar, SurfaceTermDef}
import gleamunison/repl_eval
import gleamunison/types.{empty_cache}
import gleamunison/verify

fn boot() {
  repl_eval.bootstrap_defs(verify.get_init_defs(), empty_cache())
}

pub fn hash_defs_flags_console_def_effectful_test() {
  let #(cache, defs) = boot()
  // (do Console print "hi") goes through the Console ability: the
  // requirement row is non-empty and the turnstile flag must say so.
  let user = [
    #("main", SurfaceTermDef(SDo("Console", "print", [SText(<<"hi">>)]))),
  ]
  let all_defs = list_append(defs, user)
  let assert Ok(triples) = cli_publish.hash_defs(["main"], all_defs, cache, [])
  let assert [#("main", _, effectful)] = triples
  case effectful {
    True -> Nil
    False -> panic as "a print caller must be flagged effectful"
  }
}

pub fn hash_defs_marks_pure_defs_clean_test() {
  let #(cache, defs) = boot()
  let assert Ok(triples) = cli_publish.hash_defs(["add"], defs, cache, [])
  let assert [#("add", _, effectful)] = triples
  case effectful {
    False -> Nil
    True -> panic as "add is pure"
  }
}

pub fn hash_defs_flags_transitive_effectful_test() {
  let #(cache, defs) = boot()
  // main calls greet; greet does Console print. main never writes `do`
  // itself — the flag must flow through the reference.
  let user = [
    #(
      "greet",
      SurfaceTermDef(SLambda(
        "m",
        elab_types.SDo("Console", "print", [elab_types.SVar("m")]),
      )),
    ),
    #("main", SurfaceTermDef(SApply(SVar("greet"), SText(<<"hi">>)))),
  ]
  let all_defs = list_append(defs, user)
  let assert Ok(triples) =
    cli_publish.hash_defs(["greet", "main"], all_defs, cache, [])
  let assert [#("greet", _, True), #("main", _, True)] = triples
  Nil
}

fn list_append(a, b) {
  case a {
    [] -> b
    [x, ..rest] -> [x, ..list_append(rest, b)]
  }
}
