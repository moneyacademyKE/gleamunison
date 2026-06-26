import gleam/dict.{type Dict}
import gleam/set.{type Set}
import gleamunison/identity.{type DefinitionRef}
import gleamunison/ast.{type Definition}
import gleamunison/compile.{type Compiler, new as new_compiler, compile_definition, module_name_for}

@external(erlang, "gleamunison_ffi", "load_binary")
fn load_binary(mod_name: String, beam: BitArray) -> Result(Nil, String)

pub type LoaderError {
  CompileFailed(DefinitionRef, message: String)
  LoadFailed(DefinitionRef, message: String)
}

pub opaque type Loader {
  Loader(
    compiler: Compiler,
    loaded: Set(DefinitionRef),
    failed: Dict(DefinitionRef, LoaderError),
  )
}

pub fn new_loader() -> Loader {
  Loader(compiler: new_compiler(), loaded: set.new(), failed: dict.new())
}

fn compile_and_load(ref: DefinitionRef, def: Definition, compiler: Compiler) -> Result(BitArray, String) {
  case compile_definition(compiler, def, ref) {
    Ok(beam) -> Ok(beam)
    Error(e) -> Error(e.reason)
  }
}

pub fn ensure_loaded(
  ld: Loader,
  ref: DefinitionRef,
  def: Definition,
) -> Result(Loader, #(Loader, LoaderError)) {
  case set.contains(ld.loaded, ref) {
    True -> Ok(ld)
    False -> {
      case dict.get(ld.failed, ref) {
        Ok(e) -> Error(#(ld, e))
        Error(_) -> {
          case compile_and_load(ref, def, ld.compiler) {
            Ok(beam) -> {
              let mod_name = module_name_for(ref)
              case load_binary(mod_name, beam) {
                Ok(_) -> Ok(Loader(..ld, loaded: set.insert(ld.loaded, ref)))
                Error(msg) -> {
                  let err = LoadFailed(ref, msg)
                  let next_ld = Loader(..ld, failed: dict.insert(ld.failed, ref, err))
                  Error(#(next_ld, err))
                }
              }
            }
            Error(msg) -> {
              let err = CompileFailed(ref, msg)
              let next_ld = Loader(..ld, failed: dict.insert(ld.failed, ref, err))
              Error(#(next_ld, err))
            }
          }
        }
      }
    }
  }
}
