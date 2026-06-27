import gleam/dict.{type Dict}
import gleam/set.{type Set}
import gleam/list
import gleamy/bimap
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
    module_names: bimap.Bimap(DefinitionRef, String),
    failed: Dict(DefinitionRef, LoaderError),
    order: List(DefinitionRef),
    max_size: Int,
    pending_purge: Set(DefinitionRef),
  )
}

pub fn new_loader() -> Loader {
  Loader(
    compiler: new_compiler(),
    module_names: bimap.new(),
    failed: dict.new(),
    order: [],
    max_size: 1000,
    pending_purge: set.new(),
  )
}

pub fn new_loader_with_limit(limit: Int) -> Loader {
  Loader(
    compiler: new_compiler(),
    module_names: bimap.new(),
    failed: dict.new(),
    order: [],
    max_size: limit,
    pending_purge: set.new(),
  )
}

pub fn is_loaded(ld: Loader, ref: DefinitionRef) -> Bool {
  bimap.has_key(ld.module_names, ref)
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
  let next_module_names = set.fold(successful_purges, ld.module_names, fn(bm, ref) {
    bimap.delete_by_key(bm, ref)
  })
  Loader(..ld, module_names: next_module_names, pending_purge: still_pending)
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
  case bimap.has_key(ld.module_names, ref) {
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
                      let #(next_module_names, next_pending) = list.fold(
                        evict,
                        #(bimap.insert(ld.module_names, ref, mod_name), ld.pending_purge),
                        fn(acc, evicted_ref) {
                          let #(bm, pending_set) = acc
                          let evicted_mod = module_name_for(evicted_ref)
                          case soft_purge_binary(evicted_mod) {
                            Ok(True) -> #(bimap.delete_by_key(bm, evicted_ref), pending_set)
                            _ -> #(bm, set.insert(pending_set, evicted_ref))
                          }
                        },
                      )
                      Ok(Loader(..ld, module_names: next_module_names, order: keep, pending_purge: next_pending))
                    }
                    False -> {
                      Ok(Loader(..ld, module_names: bimap.insert(ld.module_names, ref, mod_name), order: next_order))
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
