import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/elab_types.{
  type SurfaceTerm, SCase, SFloat, SHole, SInt, SLambda, SLet, SList, SMatch,
  SPConstructor, SPInt, SPText, SPVar, SUse, SVar,
}
import gleamunison/lexer.{
  type ParseError, type Token, type TokenInfo, FloatVal, IntVal, LParen,
  ParseError, Quote, RParen, Symbol,
}

@external(erlang, "gleamunison_ffi", "string_to_binary")
fn string_to_binary(s: String) -> BitArray

pub type SExpr {
  SAtom(Token, line: Int, col: Int)
  SListExpr(List(SExpr), line: Int, col: Int)
}

pub fn parse_sexpr(
  tokens: List(TokenInfo),
) -> Result(#(SExpr, List(TokenInfo)), ParseError) {
  case tokens {
    [] -> Error(ParseError("Unexpected EOF", 1, 1))
    [lexer.TokenInfo(LParen, l, c), ..rest] -> {
      use #(exprs, rest2) <- result.try(parse_list(rest, []))
      Ok(#(SListExpr(exprs, l, c), rest2))
    }
    [lexer.TokenInfo(RParen, l, c), ..] ->
      Error(ParseError("Unexpected )", l, c))
    [lexer.TokenInfo(Quote, l, c), ..rest] -> {
      case parse_sexpr(rest) {
        Ok(#(expr, rest2)) ->
          Ok(#(SListExpr([SAtom(Symbol("quote"), l, c), expr], l, c), rest2))
        Error(e) -> Error(e)
      }
    }
    [lexer.TokenInfo(lexer.UnterminatedString(_), l, c), ..] ->
      Error(ParseError("Unterminated string literal", l, c))
    [lexer.TokenInfo(other, l, c), ..rest] -> Ok(#(SAtom(other, l, c), rest))
  }
}

fn parse_list(tokens, acc) {
  case tokens {
    [] -> Error(ParseError("Unclosed (", 1, 1))
    [lexer.TokenInfo(RParen, _, _), ..rest] -> Ok(#(list.reverse(acc), rest))
    _ -> {
      use #(expr, rest) <- result.try(parse_sexpr(tokens))
      parse_list(rest, [expr, ..acc])
    }
  }
}

pub fn sexpr_to_term(sexpr: SExpr) -> Result(SurfaceTerm, ParseError) {
  case sexpr {
    SAtom(IntVal(n), _, _) -> Ok(SInt(n))
    SAtom(FloatVal(f), _, _) -> Ok(SFloat(f))
    SAtom(Symbol("?"), _, _) -> Ok(SHole)
    SAtom(Symbol(name), l, c) -> {
      case string.starts_with(name, "\"") && string.ends_with(name, "\"") {
        True -> {
          let inner = string.slice(name, 1, string.length(name) - 2)
          Ok(elab_types.SText(string_to_binary(inner)))
        }
        False -> Ok(elab_types.SLoc(SVar(name), elab_types.Span(l, c)))
      }
    }
    SAtom(lexer.UnterminatedString(_), l, c) ->
      Error(ParseError("Unterminated string literal", l, c))
    SAtom(_, l, c) -> Error(ParseError("Invalid atom", l, c))
    SListExpr(exprs, l, c) -> {
      case exprs {
        [SAtom(Symbol("let"), _, _), SAtom(Symbol(name), _, _), val, body] -> {
          use val_t <- result.try(sexpr_to_term(val))
          use body_t <- result.try(sexpr_to_term(body))
          Ok(elab_types.SLoc(SLet(name, val_t, body_t), elab_types.Span(l, c)))
        }
        [SAtom(Symbol("lam"), _, _), SAtom(Symbol(name), _, _), body] -> {
          use body_t <- result.try(sexpr_to_term(body))
          Ok(elab_types.SLoc(SLambda(name, body_t), elab_types.Span(l, c)))
        }
        // Standard-lisp sugar: (lam (x y ...) body) == (lam x (lam y ... body))
        [SAtom(Symbol("lam"), _, _), SListExpr(params, _, _), body] -> {
          use names <- result.try(param_names(params, l, c))
          use body_t <- result.try(sexpr_to_term(body))
          Ok(curry_lams(names, body_t, elab_types.Span(l, c)))
        }
        [SAtom(Symbol("fn*"), _, _), params_list, body] -> {
          use parsed_params <- result.try(parse_labeled_params(params_list))
          use body_t <- result.try(sexpr_to_term(body))
          Ok(elab_types.SLoc(
            elab_types.SLabeledFn(parsed_params, body_t),
            elab_types.Span(l, c),
          ))
        }
        [SAtom(Symbol("define"), _, _), SAtom(Symbol(name), _, _), val] -> {
          use val_t <- result.try(sexpr_to_term(val))
          Ok(SList([SVar("define"), SVar(name), val_t]))
        }
        // Standard-lisp sugar: (define (f x y ...) body) keeps the bare
        // SList([define, name, value]) loader shape, value = nested lams.
        [
          SAtom(Symbol("define"), _, _),
          SListExpr([SAtom(Symbol(name), _, _), ..params], _, _),
          body,
        ] -> {
          use names <- result.try(param_names(params, l, c))
          use body_t <- result.try(sexpr_to_term(body))
          Ok(
            SList([
              SVar("define"),
              SVar(name),
              curry_lams(names, body_t, elab_types.Span(l, c)),
            ]),
          )
        }
        [SAtom(Symbol("if"), _, _), cond, then_expr, else_expr] -> {
          use cond_t <- result.try(sexpr_to_term(cond))
          use then_t <- result.try(sexpr_to_term(then_expr))
          use else_t <- result.try(sexpr_to_term(else_expr))
          Ok(elab_types.SLoc(
            elab_types.SMatch(cond_t, [
              elab_types.SCase(elab_types.SPInt(1), option.None, then_t),
              elab_types.SCase(elab_types.SPVar("_"), option.None, else_t),
            ]),
            elab_types.Span(l, c),
          ))
        }
        [
          SAtom(Symbol("do"), _, _),
          SAtom(Symbol(ab), _, _),
          SAtom(Symbol(op), _, _),
          ..args
        ] -> {
          use parsed_args <- result.try(list.try_map(args, sexpr_to_term))
          Ok(elab_types.SLoc(
            elab_types.SDo(ab, op, parsed_args),
            elab_types.Span(l, c),
          ))
        }
        [SAtom(Symbol("handle"), _, _), comp, handler, SAtom(Symbol(ab), _, _)] -> {
          use comp_t <- result.try(sexpr_to_term(comp))
          use handler_t <- result.try(sexpr_to_term(handler))
          Ok(elab_types.SLoc(
            elab_types.SHandle(comp_t, handler_t, ab),
            elab_types.Span(l, c),
          ))
        }
        [SAtom(Symbol("type"), _, _), SAtom(Symbol(type_name), _, _), ..ctors] -> {
          use ctor_terms <- result.try(list.try_map(ctors, sexpr_to_term))
          Ok(SList([SVar("type"), SVar(type_name), ..ctor_terms]))
        }
        [SAtom(Symbol("list"), _, _), ..rest] -> {
          case list.try_map(rest, sexpr_to_term) {
            Ok(terms) -> Ok(SList(terms))
            Error(e) -> Error(e)
          }
        }
        [SAtom(Symbol("match"), _, _), scrutinee, ..cases] -> {
          use scrutinee_t <- result.try(sexpr_to_term(scrutinee))
          use parsed_cases <- result.try(
            list.try_map(cases, fn(case_expr) {
              case case_expr {
                SListExpr([pat_expr, body_expr], _, _) -> {
                  use pat <- result.try(sexpr_to_pattern(pat_expr))
                  use body <- result.try(sexpr_to_term(body_expr))
                  Ok(SCase(pattern: pat, guard: option.None, body: body))
                }
                SListExpr([pat_expr, guard_expr, body_expr], _, _) -> {
                  use pat <- result.try(sexpr_to_pattern(pat_expr))
                  use guard_t <- result.try(sexpr_to_term(guard_expr))
                  use body <- result.try(sexpr_to_term(body_expr))
                  Ok(SCase(
                    pattern: pat,
                    guard: option.Some(guard_t),
                    body: body,
                  ))
                }
                _ -> {
                  let #(l, c) = sexpr_span(case_expr)
                  Error(ParseError("Invalid match case", l, c))
                }
              }
            }),
          )
          Ok(elab_types.SLoc(
            SMatch(scrutinee_t, parsed_cases),
            elab_types.Span(l, c),
          ))
        }
        [SAtom(Symbol("use"), _, _), binder, call_expr, body_expr] -> {
          case binder {
            SAtom(Symbol(name), _, _) -> {
              use call_t <- result.try(sexpr_to_term(call_expr))
              use body_t <- result.try(sexpr_to_term(body_expr))
              Ok(elab_types.SLoc(
                SUse(name, call_t, body_t),
                elab_types.Span(l, c),
              ))
            }
            SListExpr([SAtom(Symbol(name), _, _), rest], _, _) -> {
              use call_t <- result.try(sexpr_to_term(call_expr))
              use body_t <- result.try(sexpr_to_term(body_expr))
              use rest_t <- result.try(sexpr_to_term(rest))
              Ok(elab_types.SLoc(
                SLet(name, rest_t, SUse(name, call_t, body_t)),
                elab_types.Span(l, c),
              ))
            }
            _ -> {
              let #(l, c) = sexpr_span(binder)
              Error(ParseError("Invalid use binder", l, c))
            }
          }
        }
        // (let* ((x e1) (y e2) ...) body) → nested SLet (pure sequencing).
        [SAtom(Symbol("let*"), _, _), SListExpr(bindings, _, _), body] -> {
          use pairs <- result.try(parse_binding_pairs(bindings, "let*"))
          use body_t <- result.try(sexpr_to_term(body))
          fold_let_pairs(pairs, body_t)
        }
        // (chain ((x e1) (y e2) ...) body) → nested SUse: monadic bind
        // sequencing. Each step's computation receives the rest of the
        // chain as its continuation (ast.Use compiles to nested lambdas).
        [SAtom(Symbol("chain"), _, _), SListExpr(bindings, _, _), body] -> {
          use pairs <- result.try(parse_binding_pairs(bindings, "chain"))
          use body_t <- result.try(sexpr_to_term(body))
          fold_chain_pairs(pairs, body_t)
        }
        // Wrong-arity let*/chain must error, not fall through to application.
        [SAtom(Symbol("let*"), l, c), ..] ->
          Error(ParseError("let* expects (let* ((name value) ...) body)", l, c))
        [SAtom(Symbol("chain"), l, c), ..] ->
          Error(ParseError(
            "chain expects (chain ((name computation) ...) body)",
            l,
            c,
          ))
        [first, ..rest] -> {
          use f_term <- result.try(sexpr_to_term(first))
          use folded <- result.try(
            list.try_fold(rest, f_term, fn(acc, arg) {
              use arg_term <- result.try(sexpr_to_term(arg))
              Ok(elab_types.SApply(acc, arg_term))
            }),
          )
          // The application form itself carries the call-site span; args and
          // nested calls carry their own from their own recursion.
          Ok(elab_types.SLoc(folded, elab_types.Span(l, c)))
        }
        [] -> Ok(SList([]))
      }
    }
  }
}

/// Position of any SExpr, for error messages.
fn sexpr_span(s: SExpr) -> #(Int, Int) {
  case s {
    SAtom(_, l, c) -> #(l, c)
    SListExpr(_, l, c) -> #(l, c)
  }
}

/// Parse `((name val) ...)` binding lists for `let*`/`chain`.
fn parse_binding_pairs(
  bindings: List(SExpr),
  form: String,
) -> Result(List(#(String, SurfaceTerm)), ParseError) {
  list.try_map(bindings, fn(b) {
    case b {
      SListExpr([SAtom(Symbol(name), _, _), val], _, _) -> {
        use val_t <- result.try(sexpr_to_term(val))
        Ok(#(name, val_t))
      }
      _ -> {
        let #(l, c) = sexpr_span(b)
        Error(ParseError(
          "Invalid " <> form <> " binding: expected (name value)",
          l,
          c,
        ))
      }
    }
  })
}

fn fold_let_pairs(
  pairs: List(#(String, SurfaceTerm)),
  body: SurfaceTerm,
) -> Result(SurfaceTerm, ParseError) {
  Ok(list.fold_right(pairs, body, fn(acc, pair) { SLet(pair.0, pair.1, acc) }))
}

fn fold_chain_pairs(
  pairs: List(#(String, SurfaceTerm)),
  body: SurfaceTerm,
) -> Result(SurfaceTerm, ParseError) {
  Ok(list.fold_right(pairs, body, fn(acc, pair) { SUse(pair.0, pair.1, acc) }))
}

fn sexpr_to_pattern(sexpr: SExpr) -> Result(elab_types.SPattern, ParseError) {
  case sexpr {
    SAtom(IntVal(n), _, _) -> Ok(SPInt(n))
    SAtom(Symbol(name), _, _) -> {
      case string.starts_with(name, "\"") && string.ends_with(name, "\"") {
        True -> {
          let inner = string.slice(name, 1, string.length(name) - 2)
          Ok(SPText(string_to_binary(inner)))
        }
        False -> Ok(SPVar(name))
      }
    }
    SListExpr([SAtom(Symbol(ctor_name), _, _), ..args], _, _) -> {
      use parsed_args <- result.try(list.try_map(args, sexpr_to_pattern))
      Ok(SPConstructor(ctor_name, parsed_args))
    }
    _ -> {
      let #(l, c) = sexpr_span(sexpr)
      Error(ParseError("Invalid pattern", l, c))
    }
  }
}

fn parse_labeled_params(
  sexpr: SExpr,
) -> Result(List(#(String, SurfaceTerm)), ParseError) {
  case sexpr {
    SListExpr([], _, _) -> Ok([])
    SListExpr(params, _, _) ->
      list.try_map(params, fn(p) {
        case p {
          SListExpr([SAtom(Symbol(name), _, _), default_val], _, _) -> {
            use default_t <- result.try(sexpr_to_term(default_val))
            Ok(#(name, default_t))
          }
          _ -> {
            let #(l, c) = sexpr_span(p)
            Error(ParseError("Invalid labeled parameter", l, c))
          }
        }
      })
    _ -> {
      let #(l, c) = sexpr_span(sexpr)
      Error(ParseError("Expected parameter list for fn*", l, c))
    }
  }
}

/// Params of the `(lam (x y ...) ...)` / `(define (f x y ...) ...)` sugar
/// must all be bare symbols.
fn param_names(
  params: List(SExpr),
  l: Int,
  c: Int,
) -> Result(List(String), ParseError) {
  list.try_map(params, fn(p) {
    case p {
      SAtom(Symbol(name), _, _) -> Ok(name)
      _ -> Error(ParseError("lambda parameters must be symbols", l, c))
    }
  })
}

/// Curry a param list into nested one-arg lambdas. Zero params = the body
/// itself (a thunk spelled without its `lam`).
fn curry_lams(
  names: List(String),
  body: SurfaceTerm,
  span: elab_types.Span,
) -> SurfaceTerm {
  case names {
    [] -> body
    [name, ..rest] ->
      elab_types.SLoc(SLambda(name, curry_lams(rest, body, span)), span)
  }
}

pub fn parse_string(input: String) -> Result(SurfaceTerm, ParseError) {
  let tokens = lexer.tokenize(input)
  case tokens {
    [] -> Error(ParseError("Empty input", 0, 0))
    _ ->
      case parse_sexpr(tokens) {
        Ok(#(sexpr, [])) -> sexpr_to_term(sexpr)
        Ok(#(_, [lexer.TokenInfo(_, l, c), ..])) ->
          Error(ParseError("Extra tokens after expression", l, c))
        Error(e) -> Error(e)
      }
  }
}
