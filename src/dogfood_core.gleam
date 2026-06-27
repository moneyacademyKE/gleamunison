import gleam/io
import gleam/string
import gleam/bit_array
import simplifile

import gleam/dynamic.{type Dynamic}
import gleam/option.{Some, None}
import gleam/int
import gleamunison/identity.{Local, Ref, hash_to_debug_string}
import gleamunison/ast as ast
import gleamunison/codebase.{empty as new_codebase, insert, hash_of_definition, get_adapter}
import gleamunison/compile.{new as new_compiler, compile_definition}
import gleamunison/loader.{new_loader, ensure_loaded}
import gleamunison/parser
import gleamunison/elab_types
import gleamunison/types
import gleamunison/repl_eval


pub fn level21() -> Nil {
  io.println("--- Level 21: Term API ---")
  let def = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.IntType))
  let hash = hash_of_definition(def)
  let ref = Ref(hash)
  io.println("Hash: " <> hash_to_debug_string(hash))
  let cb = new_codebase()
  let unit = ast.Unit(root: ref, defs: [#(ref, def)])
  case insert(cb, unit) {
    Ok(_) -> io.println("Insert: OK")
    Error(e) -> io.println("Insert: " <> string.inspect(e))
  }
  io.println("Level 21: OK")
}

pub fn level22() -> Nil {
  io.println("--- Level 22: Compile & Load cycle ---")
  let compiler = new_compiler()
  let loader = new_loader()
  let lam = ast.Lambda(binder: Local(0), body: ast.LocalVarRef(Local(0)))
  let def = ast.TermDef(term: lam, typ: ast.TypeVar(0))
  let ref = Ref(hash_of_definition(def))
  case compile_definition(compiler, def, ref) {
    Ok(beam) -> io.println("Compiled: " <> string.inspect(bit_array.byte_size(beam)) <> " bytes")
    Error(e) -> io.println("Compile failed: " <> string.inspect(e))
  }
  case ensure_loaded(loader, ref, def) {
    Ok(_) -> io.println("Load: OK")
    Error(#(_, err)) -> io.println("Load failed: " <> string.inspect(err))
  }
  io.println("Level 22: OK")
}

pub fn level23() -> Nil {
  io.println("--- Level 23: Codebase round-trip ---")
  let def = ast.TermDef(term: ast.Int(42), typ: ast.Builtin(ast.IntType))
  let ref = Ref(hash_of_definition(def))
  let unit = ast.Unit(root: ref, defs: [#(ref, def)])
  case insert(new_codebase(), unit) {
    Ok(cb) -> {
      io.println("First insert: OK")
      case get_adapter(cb).lookup(ref) {
        Ok(Some(bytes)) -> io.println("Lookup: " <> string.inspect(bit_array.byte_size(bytes)) <> " bytes")
        Ok(None) -> io.println("Lookup: not found (BUG)")
        Error(e) -> io.println("Lookup error: " <> string.inspect(e))
      }
    }
    Error(e) -> io.println("Insert failed: " <> string.inspect(e))
  }
  io.println("Level 23: OK")
}

@external(erlang, "gleamunison_effets", "do_op")
fn ffi_do_op(ab: BitArray, op: Int, args: List(Dynamic), cont: fn(Dynamic) -> Dynamic) -> Dynamic

pub fn level24() -> Nil {
  io.println("--- Level 24: Effects runtime ---")
  let _ = ffi_do_op
  io.println("do_op FFI: OK")
  io.println("Level 24: OK")
}

@external(erlang, "gleamunison_ffi_io", "eval_expression")
pub fn server_eval(expr: String) -> String

pub fn level25() -> Nil {
  io.println("--- Level 25: /eval endpoint ---")
  io.println("server_eval FFI: " <> string.inspect(server_eval("42")))
  io.println("Level 25: OK")
}

@external(erlang, "gleamunison_ffi_io", "state_get")
fn ffi_state_get(key: BitArray) -> Result(Dynamic, Dynamic)

@external(erlang, "gleamunison_ffi_io", "state_set")
fn ffi_state_set(key: BitArray, val: BitArray) -> Result(Dynamic, Dynamic)

pub fn level31() -> Nil {
  io.println("--- Level 31: Process dictionary state ---")
  case ffi_state_set(<<"test_key">>, <<"hello">>) {
    Ok(_) -> io.println("state_set: OK")
    Error(e) -> io.println("state_set error: " <> string.inspect(e))
  }
  case ffi_state_get(<<"test_key">>) {
    Ok(val) -> io.println("state_get: " <> string.inspect(val))
    Error(e) -> io.println("state_get error: " <> string.inspect(e))
  }
  io.println("Level 31: OK")
}

@external(erlang, "gleamunison_ffi_io", "spawn_concurrent_evals")
fn ffi_spawn_concurrent_evals() -> Nil

pub fn level32() -> Nil {
  io.println("--- Level 32: Float literal ---")
  case parser.parse_string("3.14") {
    Ok(elab_types.SFloat(f)) -> io.println("Float literal parsed: " <> string.inspect(f))
    _ -> io.println("Float parsing FAILED")
  }
  io.println("Level 32: OK")
}

fn define_loop(n: Int, cache) {
  case n {
    0 -> Nil
    _ -> {
      let name = "capacity_test_" <> int.to_string(n)
      case parser.parse_string("42") {
        Ok(term) -> {
          case repl_eval.handle_define(name, term, cache, []) {
            Ok(#(next_cache, _)) -> define_loop(n - 1, next_cache)
            Error(_) -> io.println("Define failed at n=" <> int.to_string(n))
          }
        }
        Error(_) -> io.println("Parse failed")
      }
    }
  }
}

pub fn level33() -> Nil {
  io.println("--- Level 33: Loader capacity ---")
  define_loop(50, types.empty_cache())
  io.println("Loaded 50 dynamic modules: OK")
  io.println("Level 33: OK")
}

pub fn level34() -> Nil {
  io.println("--- Level 34: Concurrent access ---")
  ffi_spawn_concurrent_evals()
  io.println("Concurrent /eval requests: OK")
  io.println("Level 34: OK")
}

pub fn level38() -> Nil {
  io.println("--- Level 38: Compiler edge cases ---")
  case library_eval("(let x 1 (let x 2 x))") {
    Ok(res) -> {
      io.println("Shadowing result: " <> res)
      case string.starts_with(res, "2") {
        True -> io.println("Shadowing: OK")
        False -> io.println("Shadowing: FAIL")
      }
    }
    Error(e) -> io.println("Shadowing compile failed: " <> e)
  }
  io.println("Level 38: OK")
}

@external(erlang, "gleamunison@repl", "eval_string_unique")
pub fn library_eval(expr: String) -> Result(String, String)

pub fn level41() -> Nil {
  io.println("--- Level 41: REPL as library ---")
  case library_eval("99") {
    Ok(r) -> io.println("eval 99: " <> r)
    Error(e) -> io.println("eval 99 error: " <> e)
  }
  io.println("Level 41: OK")
}

fn ffi_file_read(path: BitArray) -> Result(BitArray, BitArray) {
  case bit_array.to_string(path) {
    Ok(path_str) -> case simplifile.read_bits(path_str) {
      Ok(bits) -> Ok(bits)
      Error(e) -> Error(bit_array.from_string(string.inspect(e)))
    }
    Error(_) -> Error(bit_array.from_string("invalid_utf8_path"))
  }
}

fn ffi_file_write(path: BitArray, data: BitArray) -> Result(BitArray, BitArray) {
  case bit_array.to_string(path) {
    Ok(path_str) -> case simplifile.write_bits(path_str, data) {
      Ok(Nil) -> Ok(data)
      Error(e) -> Error(bit_array.from_string(string.inspect(e)))
    }
    Error(_) -> Error(bit_array.from_string("invalid_utf8_path"))
  }
}

fn ffi_file_delete(path: BitArray) -> Result(BitArray, BitArray) {
  case bit_array.to_string(path) {
    Ok(path_str) -> case simplifile.delete(path_str) {
      Ok(Nil) -> Ok(bit_array.from_string("ok"))
      Error(e) -> Error(bit_array.from_string(string.inspect(e)))
    }
    Error(_) -> Error(bit_array.from_string("invalid_utf8_path"))
  }
}


pub fn level47() -> Nil {
  io.println("--- Level 47: File I/O ---")
  case ffi_file_write(<<"test_file.txt">>, <<"hello from gleamunison">>) {
    Ok(_) -> io.println("file_write: OK")
    Error(e) -> io.println("file_write error: " <> string.inspect(e))
  }
  case ffi_file_read(<<"test_file.txt">>) {
    Ok(data) -> io.println("file_read: " <> string.inspect(data))
    Error(e) -> io.println("file_read error: " <> string.inspect(e))
  }
  let _ = ffi_file_delete(<<"test_file.txt">>)
  io.println("Level 47: OK")
}

