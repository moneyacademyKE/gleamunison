import gleam/dict.{type Dict}
import gleam/set.{type Set}
import gleam/list
import gleamunison/identity.{type DefinitionRef}
import gleamunison/ast.{type Definition}
import gleamunison/compile.{type Compiler, new as new_compiler, compile_definition, module_name_for}

@external(erlang, "gleamunison_ffi", "load_binary")
fn load_binary(mod_name: String, beam: BitArray) -> Result(Nil, String)

@external(erlang, "gleamunison_ffi", "soft_purge_binary")
fn soft_purge_binary(mod_name: String) -> Result(Bool, String)

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
    pending_purge: Set(DefinitionRef),
  )
}

pub fn new_loader() -> Loader {
  Loader(
    compiler: new_compiler(),
    loaded: set.new(),
    failed: dict.new(),
    order: [],
    max_size: 1000,
    pending_purge: set.new(),
  )
}

pub fn new_loader_with_limit(limit: Int) -> Loader {
  Loader(
    compiler: new_compiler(),
    loaded: set.new(),
    failed: dict.new(),
    order: [],
    max_size: limit,
    pending_purge: set.new(),
  )
}

pub fn is_loaded(ld: Loader, ref: DefinitionRef) -> Bool {
  set.contains(ld.loaded, ref)
}

fn retry_pending_purges(ld: Loader) -> Loader {
  let #(still_pending, successful_purges) = set.fold(
    ld.pending_purge,
    #(set.new(), set.new()),
    fn(acc, ref) {
      let #(pending, success) = acc
      let mod_name = module_name_for(ref)
      case soft_purge_binary(mod_name) {
        Ok(True) -> #(pending, set.insert(success, ref))
        _ -> #(set.insert(pending, ref), success)
      }
    },
  )
  let next_loaded = set.fold(successful_purges, ld.loaded, set.delete)
  Loader(..ld, loaded: next_loaded, pending_purge: still_pending)
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
  let ld = retry_pending_purges(ld)
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
                      let #(next_loaded, next_pending) = list.fold(
                        evict,
                        #(set.insert(ld.loaded, ref), ld.pending_purge),
                        fn(acc, evicted_ref) {
                          let #(loaded_set, pending_set) = acc
                          let evicted_mod = module_name_for(evicted_ref)
                          case soft_purge_binary(evicted_mod) {
                            Ok(True) -> #(set.delete(loaded_set, evicted_ref), pending_set)
                            _ -> #(loaded_set, set.insert(pending_set, evicted_ref))
                          }
                        },
                      )
                      Ok(Loader(..ld, loaded: next_loaded, order: keep, pending_purge: next_pending))
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
