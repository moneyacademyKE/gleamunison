import gleamunison/cli_replay
import gleeunit/should
import simplifile

/// The flagship: `chain` over continuation-invoking handlers is real
/// do-notation. A `use` compiles to `(handler)(fun(x) -> body end)`, so a
/// plain function that receives and invokes its argument IS a monadic bind.
///
/// One honest wrinkle of raw-CPS `use`: the chain body sits inside the
/// innermost continuation, so it must be a monadic value — each monad
/// writes its `return` explicitly (`(just v)` for Maybe, `(state-returns v)`
/// for State). Monad-agnostic desugaring cannot inject it.
pub fn chain_state_monad_threads_state_test() {
  let path = "/tmp/monad_state_test.lisp"
  let assert Ok(_) =
    simplifile.write(
      // State computation = fn s -> result. Handlers thread state by
      // applying the continuation's result to the (possibly new) state.
      "(define (state-get k) (lam (s) ((k s) s)))\n"
        <> "(define (state-put new) (lam (k) (lam (s) ((k 0) new))))\n"
        <> "(define (state-returns v) (lam (s) v))\n"
        <> "(define (run-state m s0) (m s0))\n"
        <> "(define prog (chain ((a state-get) (_ (state-put (add a 1))) (b state-get)) (state-returns b)))\n"
        <> "(define main (run-state prog 10))",
      to: path,
    )
  let assert Ok(result) = cli_replay.run_definition(path, "main", [])
  result |> should.equal("11")
}

/// A short-circuiting handler: `Maybe` where Nothing never invokes the
/// continuation. The chain must collapse to Nothing without running the
/// later steps.
pub fn chain_maybe_short_circuits_test() {
  let path = "/tmp/monad_maybe_test.lisp"
  let assert Ok(_) =
    simplifile.write(
      // Maybe values: (just v) = lam j. lam n. j v ; nothing = lam j. lam n. n
      "(define (just v) (lam (j) (lam (n) (j v))))\n"
        <> "(define nothing (lam (j) (lam (n) n)))\n"
        // maybe-bind: handler receives continuation k; invokes it only on Just.
        <> "(define (maybe-bind m) (lam (k) ((m (lam (v) (k v))) nothing)))\n"
        <> "(define (from-maybe default m) ((m (lam (v) v)) default))\n"
        <> "(define prog (chain ((a (maybe-bind (just 20))) (b (maybe-bind nothing)) (c (maybe-bind (just 2)))) (just (add a c))))\n"
        <> "(define main (from-maybe 0 prog))",
      to: path,
    )
  let assert Ok(result) = cli_replay.run_definition(path, "main", [])
  // b is Nothing: the chain short-circuits, from-maybe yields the default.
  result |> should.equal("0")
}

/// The same Maybe chain with no Nothing in it must run every step.
pub fn chain_maybe_all_just_runs_all_steps_test() {
  let path = "/tmp/monad_maybe_just_test.lisp"
  let assert Ok(_) =
    simplifile.write(
      "(define (just v) (lam (j) (lam (n) (j v))))\n"
        <> "(define nothing (lam (j) (lam (n) n)))\n"
        <> "(define (maybe-bind m) (lam (k) ((m (lam (v) (k v))) nothing)))\n"
        <> "(define (from-maybe default m) ((m (lam (v) v)) default))\n"
        <> "(define prog (chain ((a (maybe-bind (just 20))) (b (maybe-bind (just 2)))) (just (add a b))))\n"
        <> "(define main (from-maybe 0 prog))",
      to: path,
    )
  let assert Ok(result) = cli_replay.run_definition(path, "main", [])
  result |> should.equal("22")
}

/// State with multiple puts: later state must win, and the initial state
/// must be invisible after the first put.
pub fn chain_state_put_shadows_initial_test() {
  let path = "/tmp/monad_state_put_test.lisp"
  let assert Ok(_) =
    simplifile.write(
      "(define (state-get k) (lam (s) ((k s) s)))\n"
        <> "(define (state-put new) (lam (k) (lam (s) ((k 0) new))))\n"
        <> "(define (state-returns v) (lam (s) v))\n"
        <> "(define (run-state m s0) (m s0))\n"
        <> "(define prog (chain ((_ (state-put 5)) (_ (state-put 7)) (b state-get)) (state-returns b)))\n"
        <> "(define main (run-state prog 0))",
      to: path,
    )
  let assert Ok(result) = cli_replay.run_definition(path, "main", [])
  result |> should.equal("7")
}
