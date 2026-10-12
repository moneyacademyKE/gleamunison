import gleam/dict
import gleam/option
import gleamunison/ast
import gleamunison/elab_ctx
import gleamunison/elab_def
import gleamunison/elab_types
import gleamunison/parser
import gleamunison/repl_eval
import gleamunison/types
import gleamunison/verify

/// Bootstrap term builtins must carry their declared types into the type
/// cache: `(add 1 greeting)` with greeting: Text is a type error, and it
/// must cite the argument's span (col 8).
pub fn bootstrap_add_is_typed_and_error_is_located_test() {
  let #(cache, _defs) =
    repl_eval.bootstrap_defs(verify.get_init_defs(), types.empty_cache())
  let add_ref = repl_eval.ref_for_name("add")
  // The name binding points at the def; the def body is RefTo(genesis_ref).
  let assert Ok(types.CTTerm(add_typ)) = dict.get(cache.entries, add_ref)
  // Not the "unknown" sentinel: a real function type Int -> Int -> Int.
  let assert ast.Fn(_, _, _) = add_typ
  let greeting_ref = repl_eval.ref_for_name("greeting")
  let ctx =
    elab_ctx.ElabCtx(
      names: dict.from_list([
        #("add", add_ref),
        #("greeting", greeting_ref),
      ]),
      bindings: dict.new(),
      next_local: 0,
      abilities: dict.new(),
      ops: dict.new(),
    )
  let cache2 =
    types.TypeCache(
      dict.insert(
        cache.entries,
        greeting_ref,
        types.CTTerm(ast.Builtin(ast.TextType)),
      ),
    )
  let assert Ok(term) = parser.parse_string("(add 1 greeting)")
  let result =
    elab_def.elab_term_def(term, ctx, repl_eval.ref_for_name("bad"), cache2)
  let assert Error(elab_types.At(elab_types.InferFailed(msg), span)) = result
  let assert elab_types.Span(1, 8) = span
  let assert True = msg != ""
}
