import gleam/dict.{type Dict}
import gleam/set.{type Set}
import gleam/list
import gleamunison/identity.{type DefinitionRef}
import gleamunison/ast.{type Definition}
import gleamunison/compile.{type Compiler, new as new_compiler, compile_definition, module_name_for}

@external(erlang, "gleamunison_ffi", "load_binary")
fn load_binary(mod_name: String, beam: BitArray) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi", "unload_binary")
fn unload_binary(mod_name: String) -> Result(Nil, String)

pub type LoaderError {
  CompileFailed(DefinitionRef, message: String)
  LoadFailed(DefinitionRef, message: String)
}

pub opaque type Loader {
  Loader(
    compiler: Compiler,
    loaded: Set(DefinitionRef),
    failed: Dict(DefinitionRef, LoaderError),
    order: List(DefinitionRef),
    max_size: Int,
  )
}

pub fn new_loader() -> Loader {
  Loader(
    compiler: new_compiler(),
    loaded: set.new(),
    failed: dict.new(),
    order: [],
    max_size: 1000,
  )
}

pub fn new_loader_with_limit(limit: Int) -> Loader {
  Loader(
    compiler: new_compiler(),
    loaded: set.new(),
    failed: dict.new(),
    order: [],
    max_size: limit,
  )
}

pub fn is_loaded(ld: Loader, ref: DefinitionRef) -> Bool {
  set.contains(ld.loaded, ref)
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
    True -> {
      let next_order = [ref, ..list.filter(ld.order, fn(r) { r != ref })]
      Ok(Loader(..ld, order: next_order))
    }
    False -> {
      case dict.get(ld.failed, ref) {
        Ok(e) -> Error(#(ld, e))
        Error(_) -> {
          case compile_and_load(ref, def, ld.compiler) {
            Ok(beam) -> {
              let mod_name = module_name_for(ref)
              case load_binary(mod_name, beam) {
                Ok(_) -> {
                  let next_order = [ref, ..ld.order]
                  case list.length(next_order) > ld.max_size {
                    True -> {
                      let #(keep, evict) = list.split(next_order, ld.max_size)
                      list.each(evict, fn(evicted_ref) {
                        let evicted_mod = module_name_for(evicted_ref)
                        let _ = unload_binary(evicted_mod)
                        Nil
                      })
                      let next_loaded = list.fold(evict, set.insert(ld.loaded, ref), set.delete)
                      Ok(Loader(..ld, loaded: next_loaded, order: keep))
                    }
                    False -> {
                      Ok(Loader(..ld, loaded: set.insert(ld.loaded, ref), order: next_order))
                    }
                  }
                }
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
