import gleamunison/ast
import gleamunison/compile.{
  compile_definition, module_name_for, new as new_compiler,
}
import gleamunison/elab_ctx.{type ElabCtx}
import gleamunison/elab_types.{
  type SurfaceDef, type SurfaceTerm, SurfaceTermDef, SurfaceUnit,
}
import gleamunison/elaborate as elab
import gleamunison/identity.{type DefinitionRef}
import gleamunison/lexer.{type ParseError}
import gleamunison/loader_ffi.{eval_module, load_binary, unload_binary}
import gleamunison/parser
import gleamunison/types.{type TypeCache}

/// identity owns the name-to-ref bytes; still public because callers have
/// been able to reach the derivation through the pipeline.
pub fn ref_for_name(name: String) -> DefinitionRef {
  identity.name_ref(name)
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
    Error(e) -> {
      let compile.InternalError(reason) = e
      Error("Compile Error: " <> reason)
    }
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
