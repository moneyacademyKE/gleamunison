import gleam/io
import gleam/list
import gleam/string
import gleamunison/identity.{Local, Ref, hash_to_debug_string}
import gleamunison/ast as ast
import gleamunison/codebase.{empty as new_codebase, insert, hash_of_definition}
import gleamunison/compile.{new as new_compiler, compile_definition}
import gleamunison/loader.{new_loader, ensure_loaded}
import gleamunison/types.{empty_cache}
import gleamunison/inference.{infer_term}
import gleamunison/elaborate as elab
import gleamunison/elab_types as elab_types
import gleamunison/effects.{RuntimeConfig}
import gleamunison/sync.{new_sync_state}

fn demo_term(compiler, loader, codebase, label, term, typ) {
  io.println("--- " <> label <> " ---")
  let def = ast.TermDef(term:, typ:)
  let hash = hash_of_definition(def)
  let ref = Ref(hash)
  io.println("Hash: " <> hash_to_debug_string(hash))
  let unit = ast.Unit(root: ref, defs: [#(ref, def)])
  case insert(codebase, unit) {
    Ok(cb) -> {
      let _ = compile_definition(compiler, def, ref)
      case ensure_loaded(loader, ref, def) {
        Ok(ld) -> {
          io.println("Load: OK")
          #(cb, ld)
        }
        Error(_) -> #(cb, loader)
      }
    }
    Error(_) -> #(codebase, loader)
  }
}

pub fn main() -> Nil {
  io.println("=== Gleamunison ===")
  let compiler = new_compiler()
  let loader = new_loader()
  let codebase = new_codebase()
  let int_type = ast.Builtin(ast.IntType)

  let #(cb, ld) = demo_term(compiler, loader, codebase, "Int(42)", ast.Int(42), int_type)
  let lam = ast.Lambda(binder: Local(0), body: ast.LocalVarRef(Local(0)))
  let #(cb, ld) = demo_term(compiler, ld, cb, "Lambda(id)", lam, ast.TypeVar(0))
  let app = ast.Apply(function: lam, arg: ast.Int(99))
  let #(cb, ld) = demo_term(compiler, ld, cb, "Apply(id, 99)", app, int_type)
  let letterm = ast.Let(binder: Local(0), value: ast.Int(42), body: ast.LocalVarRef(Local(0)))
  let #(cb, ld) = demo_term(compiler, ld, cb, "Let(V0=42, V0)", letterm, int_type)
  let #(cb, ld) = demo_term(compiler, ld, cb, "Text(hello)", ast.Text(<<"hello">>), ast.Builtin(ast.TextType))
  let #(cb, ld) = demo_term(compiler, ld, cb, "List([1,2,3])", ast.List([ast.Int(1), ast.Int(2), ast.Int(3)]), ast.TypeVar(0))

  let m = ast.Match(ast.Int(42), [
    ast.Case(pattern: ast.PatInt(42), body: ast.Text(<<"forty-two">>)),
    ast.Case(pattern: ast.PatVar(Local(0)), body: ast.Text(<<"other">>)),
  ])
  let #(_, _) = demo_term(compiler, ld, cb, "Match(42, cases)", m, ast.Builtin(ast.TextType))

  io.println("--- Type Inference ---")
  let cache = empty_cache()
  let _ = infer_term(ast.Int(42), cache)
  let _ = infer_term(ast.Float(3.14), cache)
  let _ = infer_term(ast.Text(<<"hi">>), cache)
  let _ = infer_term(ast.List([ast.Int(1), ast.Int(2)]), cache)
  io.println("Typecheck: OK")

  io.println("--- Elaboration ---")
  let surface = elab_types.SurfaceUnit(root: Ref(hash_of_definition(ast.TermDef(ast.Int(0), int_type))),
    defs: [#("test", elab_types.SurfaceTermDef(elab_types.SInt(99)))])
  case elab.elaborate_unit(surface, cache) {
    Ok(#(u, _)) -> {
      let ast.Unit(root: Ref(rh), defs: ds) = u
      io.println("Elaborated: " <> hash_to_debug_string(rh) <> " with " <> string.inspect(list.length(ds)) <> " defs")
    }
    Error(e) -> io.println("Elaborate: " <> string.inspect(e))
  }

  let _ = RuntimeConfig(ambient_handlers: [])
  let _ = new_sync_state()
  io.println("=== Done ===")
}
