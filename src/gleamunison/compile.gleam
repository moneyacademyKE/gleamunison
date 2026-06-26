import gleam/int
import gleam/float
import gleam/list
import gleam/string
import gleamunison/identity.{type DefinitionRef, Local, Ref, hash_to_debug_string}
import gleamunison/ast as ast

pub type Compiler { Compiler }
pub fn new() -> Compiler { Compiler }

pub type CompileError { InternalError(reason: String) }

@external(erlang, "gleamunison_ffi", "compile_source")
fn ffi_compile_source(source: String) -> Result(BitArray, String)

pub fn module_name_for(ref: DefinitionRef) -> String {
  let Ref(hash) = ref
  let full = hash_to_debug_string(hash)
  "m_" <> string.slice(full, string.length(full) - 8, 8)
}

fn emit_term(t: ast.Term) -> String {
  case t {
    ast.Int(n) -> int.to_string(n)
    ast.Float(f) -> float.to_string(f)
    ast.Text(b) -> string.inspect(b)
    ast.RefTo(ref) -> "'" <> module_name_for(ref) <> "':$eval()"
    ast.LocalVarRef(Local(i)) -> "V" <> int.to_string(i)
    ast.Apply(function: f, arg: a) -> "(" <> emit_term(f) <> ")(" <> emit_term(a) <> ")"
    ast.Lambda(binder: Local(i), body:) -> "fun(V" <> int.to_string(i) <> ") -> " <> emit_term(body) <> " end"
    ast.Let(binder: Local(i), value:, body:) ->
      "begin V" <> int.to_string(i) <> " = " <> emit_term(value) <> ", " <> emit_term(body) <> " end"
    ast.Match(scrutinee:, cases:) -> {
      let cls = list.map(cases, fn(c) { emit_pattern(c.pattern) <> " -> " <> emit_term(c.body) })
      "case (" <> emit_term(scrutinee) <> ") of " <> string.join(cls, "; ") <> " end"
    }
    ast.List(ts) -> "[" <> string.join(list.map(ts, emit_term), ", ") <> "]"
    ast.Do(ability:, operation: Local(op_i), args:) ->
      "gleamunison_effets:do_op('" <> module_name_for(ability) <> "', "
      <> int.to_string(op_i) <> ", ["
      <> string.join(list.map(args, emit_term), ", ") <> "], fun(R) -> R end)"
    ast.Handle(computation:, handler:) ->
      "gleamunison_effets:handle_comp(" <> emit_term(handler)
      <> ", fun() -> " <> emit_term(computation) <> " end)"
  }
}

fn emit_pattern(p: ast.Pattern) -> String {
  case p {
    ast.PatVar(Local(i)) -> "V" <> int.to_string(i)
    ast.PatInt(n) -> int.to_string(n)
    ast.PatText(b) -> string.inspect(b)
    ast.PatCons(head: Local(h), tail: Local(t)) -> "[V" <> int.to_string(h) <> "|V" <> int.to_string(t) <> "]"
    ast.PatEmptyList -> "[]"
    ast.PatAs(bound: Local(b), inner:) -> "V" <> int.to_string(b) <> " = " <> emit_pattern(inner)
  }
}

pub fn compile_definition(_c: Compiler, def: ast.Definition, ref: DefinitionRef) -> Result(BitArray, CompileError) {
  let m = module_name_for(ref)
  let body = case def {
    ast.TermDef(term:, typ: _) -> emit_term(term)
    ast.TypeDef(_) -> "ok"
    ast.AbilityDecl(_) -> "ok"
  }
  let #(exports, stubs) = case def {
    ast.AbilityDecl(ast.AbilityDeclaration(name: _, operations: ops)) -> {
      let indices = list.index_map(ops, fn(_, i) { i })
      let exp = list.map(indices, fn(i) { ", 'op_" <> int.to_string(i) <> "'/2" })
        |> string.join("")
      let stb = list.map(indices, fn(i) {
        "'op_" <> int.to_string(i) <> "'(_Args, _Cont) -> ok.\n"
      }) |> string.join("")
      #(exp, stb)
    }
    _ -> #("", "")
  }
  let src = "-module('" <> m <> "').\n"
    <> "-export(['$eval'/0" <> exports <> "]).\n"
    <> "'$eval'() -> " <> body <> ".\n"
    <> stubs
  case ffi_compile_source(src) {
    Ok(b) -> Ok(b)
    Error(e) -> Error(InternalError(e))
  }
}
