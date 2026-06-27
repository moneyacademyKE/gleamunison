import gleam/string
import gleamunison/parser
import gleamunison/lexer.{type ParseError}
import gleamunison/elab_types.{type SurfaceTerm, type SurfaceDef, SurfaceUnit, SurfaceTermDef}
import gleamunison/elaborate as elab
import gleamunison/elab_ctx.{type ElabCtx}
import gleamunison/compile.{module_name_for, compile_definition, new as new_compiler}
import gleamunison/types.{type TypeCache}
import gleamunison/identity.{type DefinitionRef, Ref, hash_bytes}
import gleamunison/ast

@external(erlang, "gleamunison_ffi", "string_to_binary")
fn string_to_binary(s: String) -> BitArray

@external(erlang, "gleamunison_ffi", "load_binary")
fn load_binary(mod_name: String, beam: BitArray) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi", "unload_binary")
fn unload_binary(mod_name: String) -> Result(Nil, String)

@external(erlang, "gleamunison_repl_ffi", "eval_module")
fn eval_module(mod_name: String) -> Result(String, String)

pub fn ref_for_name(name: String) -> DefinitionRef {
  Ref(hash_bytes(string_to_binary(name)))
}

pub fn parse_only(source: String) -> Result(SurfaceTerm, ParseError) {
  parser.parse_string(source)
}

pub fn elaborate_only(
  term: SurfaceTerm,
  name: String,
  cache: TypeCache,
  prev_defs: List(#(String, SurfaceDef)),
) -> Result(#(ast.Unit, TypeCache, ElabCtx), elab_types.ElaborateError) {
  let expr_ref = ref_for_name(name)
  let defs = [#(name, SurfaceTermDef(term)), ..prev_defs]
  elab.elaborate_unit(SurfaceUnit(expr_ref, defs), cache)
}

pub fn compile_only(
  def: ast.Definition,
  ref: DefinitionRef,
) -> Result(BitArray, String) {
  let mod_name = module_name_for(ref)
  let _ = unload_binary(mod_name)
  case compile_definition(new_compiler(), def, ref) {
    Ok(beam) -> Ok(beam)
    Error(e) -> Error(string.inspect(e))
  }
}

pub fn load_and_eval(
  mod_name: String,
  beam: BitArray,
) -> Result(String, String) {
  case load_binary(mod_name, beam) {
    Ok(_) -> eval_module(mod_name)
    Error(err) -> Error(err)
  }
}
