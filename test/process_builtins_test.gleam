import gleam/string
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/types
import gleamunison/verify
import gleeunit/should

fn boot() {
  repl_eval.bootstrap_defs(verify.get_init_defs(), types.empty_cache())
}

fn eval_source(source: String) {
  let #(cache, defs) = boot()
  let assert Ok(term) = parser.parse_string(source)
  repl_eval.do_eval(term, "process_builtin_regression", cache, defs)
}

pub fn self_send_recv_round_trip_through_evaluator_test() {
  let result =
    eval_source("(let ignored (send self \"jet-removal:round-trip\") recv)")
  let assert Ok(#(value, _, _)) = result
  value |> should.equal("<<\"jet-removal:round-trip\">>")
}

pub fn spawn_remains_available_through_evaluator_test() {
  let result = eval_source("(spawn (lam ignored 42))")
  let assert Ok(#(value, _, _)) = result
  string.starts_with(value, "<0.") |> should.be_true
}
