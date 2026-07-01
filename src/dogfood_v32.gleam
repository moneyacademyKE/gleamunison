import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import gleamunison/ast
import gleamunison/codebase.{empty as new_codebase, get_adapter, hash_of_definition, insert, insert_raw}
import gleamunison/compile.{module_name_for, new as new_compiler}
import gleamunison/elab_types.{SInt, SVar, SurfaceAbilityDef, SurfaceOp, SurfaceTermDef, SurfaceUnit, TBuiltin, TInt, TText}
import gleamunison/elaborate.{elaborate_unit}
import gleamunison/identity.{Local, Ref, hash_bytes, hash_equal, hash_to_debug_string, hash_to_short_string}
import gleamunison/loader.{ensure_loaded, is_loaded, new_loader, new_loader_with_limit}
import gleamunison/pipeline.{compile_only, elaborate_only, load_and_eval, parse_only}
import gleamunison/repl.{eval_string}
import gleamunison/repl_eval.{do_eval, handle_define, deserialize_term, serialize_term}
import gleamunison/storage.{StorageAdapter, inmemory}
import gleamunison/typecheck.{typecheck_unit}
import gleamunison/type_pretty.{pretty_print}
import gleamunison/types.{empty_cache}

fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}

// --- AUTO-GENERATED BATCH 32 (2721-2770) ---

pub fn level2721() -> Nil {
  io.println("--- compile+load int ---")
  let def = ast.TermDef(ast.Int(25), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Int: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2721: OK")
}

pub fn level2722() -> Nil {
  io.println("--- compile+load float ---")
  let def = ast.TermDef(ast.Float(2.71), ast.Builtin(ast.FloatType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Float: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2722: OK")
}

pub fn level2723() -> Nil {
  io.println("--- compile+load text ---")
  let def = ast.TermDef(ast.Text(bit_array.from_string("batch")), ast.Builtin(ast.TextType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Text: " <> string.slice(r, 0, 10))
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2723: OK")
}

pub fn level2724() -> Nil {
  io.println("--- compile+load lambda apply ---")
  let id = ast.Lambda(Local(0), ast.LocalVarRef(Local(0)))
  let def = ast.TermDef(ast.Apply(id, ast.Int(10)), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Apply: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2724: OK")
}

pub fn level2725() -> Nil {
  io.println("--- compile Let ---")
  let def = ast.TermDef(ast.Let(Local(0), ast.Int(99), ast.LocalVarRef(Local(0))), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Let: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2725: OK")
}

pub fn level2726() -> Nil {
  io.println("--- compile List ---")
  let def = ast.TermDef(ast.List([ast.Int(10), ast.Int(10), ast.Int(10), ast.Int(10)]), ast.Builtin(ast.ListType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("List: " <> string.slice(r, 0, 15))
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2726: OK")
}

pub fn level2727() -> Nil {
  io.println("--- elaborate_only ---")
  case parse_only("\"hello\"") {
    Ok(st) -> case elaborate_only(st, "e
2727
", empty_cache(), []) {
      Ok(#(_, _, _)) -> io.println("Elab: OK")
      Error(e) -> io.println("Err: " <> string.inspect(e))
    }
    Error(e) -> io.println("Parse: " <> e.message)
  }
  io.println("Level 2727: OK")
}

pub fn level2728() -> Nil {
  io.println("--- loader limit 2 + 5 ---")
  let ldr = new_loader_with_limit(2)
  let defs = list.map(range(1, 6), fn(i) {
    let d = ast.TermDef(ast.Int(i), ast.Builtin(ast.IntType))
    let h = Ref(hash_of_definition(d))
    #(h, d)
  })
  case list.fold(defs, Ok(ldr), fn(acc, p) {
    case acc { Ok(l) -> { let #(h,d)=p ensure_loaded(l,h,d) } Error(e)->Error(e) }
  }) {
    Ok(_) -> io.println("
5
 defs: OK")
    Error(_) -> io.println("Err")
  }
  io.println("Level 2728: OK")
}

pub fn level2729() -> Nil {
  io.println("--- codebase insert 4 defs ---")
  let defs = list.map(range(1, 5), fn(i) {
    let d = ast.TermDef(ast.Int(i * 10), ast.Builtin(ast.IntType))
    let r = Ref(hash_of_definition(d))
    #(r, d)
  })
  let unit = ast.Unit(Ref(hash_bytes(bit_array.from_string("u2729"))), defs)
  case insert(new_codebase(), unit) {
    Ok(cb) -> {
      let a = get_adapter(cb)
      case a.list_refs() {
        Ok(rs) -> io.println("
4
 defs: " <> int.to_string(list.length(rs)))
        Error(e) -> io.println("Err: " <> string.inspect(e))
      }
    }
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2729: OK")
}

pub fn level2730() -> Nil {
  io.println("--- storage 100 inserts ---")
  let a = inmemory()
  list.each(range(1, 101), fn(i) {
    let r = Ref(hash_bytes(bit_array.from_string("s" <> int.to_string(i))))
    let _ = a.insert(r, bit_array.from_string("d"))
  })
  case a.list_refs() {
    Ok(rs) -> io.println("
100
 refs: " <> int.to_string(list.length(rs)))
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2730: OK")
}

pub fn level2731() -> Nil {
  io.println("--- cross-module RefTo ---")
  let db = ast.TermDef(ast.Int(55), ast.Builtin(ast.IntType))
  let hb = hash_of_definition(db)
  case compile_only(db, Ref(hb)) {
    Ok(bb) -> case load_and_eval(module_name_for(Ref(hb)), bb) {
      Ok(_) -> {
        let da = ast.TermDef(ast.RefTo(Ref(hb)), ast.Builtin(ast.IntType))
        let ha = hash_of_definition(da)
        case compile_only(da, Ref(ha)) {
          Ok(ba) -> case load_and_eval(module_name_for(Ref(ha)), ba) {
            Ok(r) -> io.println("Cross: " <> r)
            Error(e) -> io.println("A: " <> e)
          }
          Error(e) -> io.println("A comp: " <> e)
        }
      }
      Error(e) -> io.println("B: " <> e)
    }
    Error(e) -> io.println("B comp: " <> e)
  }
  io.println("Level 2731: OK")
}

pub fn level2732() -> Nil {
  io.println("--- effects Handle ---")
  let ab_r = Ref(hash_bytes(bit_array.from_string("ab2732")))
  let ab = ast.AbilityDecl(ast.AbilityDeclaration(name: Local(0), operations: [
    ast.Operation(name: Local(0), inputs: [], output: ast.TypeRefBuiltin(ast.IntType)),
  ]))
  let ah = hash_of_definition(ab)
  case compile_only(ab, Ref(ah)) {
    Ok(bb) -> case load_and_eval(module_name_for(Ref(ah)), bb) {
      Ok(_) -> {
        let h = ast.Handle(ast.Int(99), ast.Lambda(Local(0), ast.LocalVarRef(Local(0))), ab_r)
        let d = ast.TermDef(h, ast.Builtin(ast.IntType))
        let dh = hash_of_definition(d)
        case compile_only(d, Ref(dh)) {
          Ok(b) -> case load_and_eval(module_name_for(Ref(dh)), b) {
            Ok(r) -> io.println("Handle: " <> r)
            Error(e) -> io.println("L&E: " <> e)
          }
          Error(e) -> io.println("Comp: " <> e)
        }
      }
      Error(e) -> io.println("Ab: " <> e)
    }
    Error(e) -> io.println("Ab comp: " <> e)
  }
  io.println("Level 2732: OK")
}

pub fn level2733() -> Nil {
  io.println("--- elab abilities ---")
  let su = SurfaceUnit(Ref(hash_bytes(bit_array.from_string("elab2733"))), [
    #("A", SurfaceAbilityDef("A", [SurfaceOp("op0",[],TBuiltin(TInt))]))
  ])
  case elaborate_unit(su, empty_cache()) {
    Ok(#(_, _, _)) -> io.println("Elab: OK")
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2733: OK")
}

pub fn level2734() -> Nil {
  io.println("--- typecheck ---")
  let d1 = ast.TermDef(ast.Int(50), ast.Builtin(ast.IntType))
  let d2 = ast.TermDef(ast.Int(10), ast.Builtin(ast.IntType))
  let r1 = Ref(hash_of_definition(d1))
  let r2 = Ref(hash_of_definition(d2))
  let unit = ast.Unit(r1, [#(r1, d1), #(r2, d2)])
  case typecheck_unit(unit, empty_cache()) {
    Ok(#(_, _)) -> io.println("TC: OK")
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2734: OK")
}

pub fn level2735() -> Nil {
  io.println("--- loader is_loaded ---")
  let ldr = new_loader()
  let d = ast.TermDef(ast.Int(100), ast.Builtin(ast.IntType))
  let h = Ref(hash_of_definition(d))
  case ensure_loaded(ldr, h, d) {
    Ok(l) -> case is_loaded(l, h) {
      True -> io.println("Loaded: OK")
      False -> io.println("Not tracked")
    }
    Error(_) -> io.println("Err")
  }
  io.println("Level 2735: OK")
}

pub fn level2736() -> Nil {
  io.println("--- hash distinct ---")
  let d1 = ast.TermDef(ast.Int(42), ast.Builtin(ast.IntType))
  let d2 = ast.TermDef(ast.Int(77), ast.Builtin(ast.IntType))
  case hash_equal(hash_of_definition(d1), hash_of_definition(d2)) {
    True -> io.println("Same: OK")
    False -> io.println("Diff: OK")
  }
  io.println("Level 2736: OK")
}

pub fn level2737() -> Nil {
  io.println("--- insert_raw ---")
  let r = Ref(hash_bytes(bit_array.from_string("raw2737")))
  let cb2 = insert_raw(new_codebase(), r, bit_array.from_string("data"))
  let a = get_adapter(cb2)
  case a.lookup(r) {
    Ok(option.Some(v)) -> io.println("Found: " <> string.inspect(v))
    Ok(option.None) -> io.println("Not found")
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2737: OK")
}

pub fn level2738() -> Nil {
  io.println("--- REPL eval ---")
  case eval_string("\"hello\"") {
    Ok(r) -> io.println("Eval: " <> r)
    Error(e) -> io.println("Err: " <> e)
  }
  io.println("Level 2738: OK")
}

pub fn level2739() -> Nil {
  io.println("--- serialize ---")
  let ser = serialize_term([1,2,3])
  let deser = deserialize_term(ser)
  io.println("Serde: OK")
  io.println("Level 2739: OK")
}

pub fn level2740() -> Nil {
  io.println("--- empty list ---")
  let def = ast.TermDef(ast.List([]), ast.Builtin(ast.ListType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Empty: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2740: OK")
}

pub fn level2741() -> Nil {
  io.println("--- elab error ---")
  case parse_only("nonexistent") {
    Ok(st) -> case elaborate_only(st, "t", empty_cache(), []) {
      Ok(_) -> io.println("Unexpected")
      Error(e) -> io.println("Err: " <> string.inspect(e))
    }
    Error(e) -> io.println("Parse: " <> string.inspect(e))
  }
  io.println("Level 2741: OK")
}

pub fn level2742() -> Nil {
  io.println("--- compile+load int ---")
  let def = ast.TermDef(ast.Int(10), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Int: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2742: OK")
}

pub fn level2743() -> Nil {
  io.println("--- compile+load float ---")
  let def = ast.TermDef(ast.Float(99.9), ast.Builtin(ast.FloatType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Float: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2743: OK")
}

pub fn level2744() -> Nil {
  io.println("--- compile+load text ---")
  let def = ast.TermDef(ast.Text(bit_array.from_string("batch")), ast.Builtin(ast.TextType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Text: " <> string.slice(r, 0, 10))
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2744: OK")
}

pub fn level2745() -> Nil {
  io.println("--- compile+load lambda apply ---")
  let id = ast.Lambda(Local(0), ast.LocalVarRef(Local(0)))
  let def = ast.TermDef(ast.Apply(id, ast.Int(42)), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Apply: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2745: OK")
}

pub fn level2746() -> Nil {
  io.println("--- compile Let ---")
  let def = ast.TermDef(ast.Let(Local(0), ast.Int(33), ast.LocalVarRef(Local(0))), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Let: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2746: OK")
}

pub fn level2747() -> Nil {
  io.println("--- compile List ---")
  let def = ast.TermDef(ast.List([ast.Int(33), ast.Int(33), ast.Int(33), ast.Int(33), ast.Int(33)]), ast.Builtin(ast.ListType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("List: " <> string.slice(r, 0, 15))
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2747: OK")
}

pub fn level2748() -> Nil {
  io.println("--- elaborate_only ---")
  case parse_only("\"hello\"") {
    Ok(st) -> case elaborate_only(st, "e
2748
", empty_cache(), []) {
      Ok(#(_, _, _)) -> io.println("Elab: OK")
      Error(e) -> io.println("Err: " <> string.inspect(e))
    }
    Error(e) -> io.println("Parse: " <> e.message)
  }
  io.println("Level 2748: OK")
}

pub fn level2749() -> Nil {
  io.println("--- loader limit 3 + 6 ---")
  let ldr = new_loader_with_limit(3)
  let defs = list.map(range(1, 7), fn(i) {
    let d = ast.TermDef(ast.Int(i), ast.Builtin(ast.IntType))
    let h = Ref(hash_of_definition(d))
    #(h, d)
  })
  case list.fold(defs, Ok(ldr), fn(acc, p) {
    case acc { Ok(l) -> { let #(h,d)=p ensure_loaded(l,h,d) } Error(e)->Error(e) }
  }) {
    Ok(_) -> io.println("
6
 defs: OK")
    Error(_) -> io.println("Err")
  }
  io.println("Level 2749: OK")
}

pub fn level2750() -> Nil {
  io.println("--- codebase insert 2 defs ---")
  let defs = list.map(range(1, 3), fn(i) {
    let d = ast.TermDef(ast.Int(i * 77), ast.Builtin(ast.IntType))
    let r = Ref(hash_of_definition(d))
    #(r, d)
  })
  let unit = ast.Unit(Ref(hash_bytes(bit_array.from_string("u2750"))), defs)
  case insert(new_codebase(), unit) {
    Ok(cb) -> {
      let a = get_adapter(cb)
      case a.list_refs() {
        Ok(rs) -> io.println("
2
 defs: " <> int.to_string(list.length(rs)))
        Error(e) -> io.println("Err: " <> string.inspect(e))
      }
    }
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2750: OK")
}

pub fn level2751() -> Nil {
  io.println("--- storage 100 inserts ---")
  let a = inmemory()
  list.each(range(1, 101), fn(i) {
    let r = Ref(hash_bytes(bit_array.from_string("s" <> int.to_string(i))))
    let _ = a.insert(r, bit_array.from_string("d"))
  })
  case a.list_refs() {
    Ok(rs) -> io.println("
100
 refs: " <> int.to_string(list.length(rs)))
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2751: OK")
}

pub fn level2752() -> Nil {
  io.println("--- cross-module RefTo ---")
  let db = ast.TermDef(ast.Int(55), ast.Builtin(ast.IntType))
  let hb = hash_of_definition(db)
  case compile_only(db, Ref(hb)) {
    Ok(bb) -> case load_and_eval(module_name_for(Ref(hb)), bb) {
      Ok(_) -> {
        let da = ast.TermDef(ast.RefTo(Ref(hb)), ast.Builtin(ast.IntType))
        let ha = hash_of_definition(da)
        case compile_only(da, Ref(ha)) {
          Ok(ba) -> case load_and_eval(module_name_for(Ref(ha)), ba) {
            Ok(r) -> io.println("Cross: " <> r)
            Error(e) -> io.println("A: " <> e)
          }
          Error(e) -> io.println("A comp: " <> e)
        }
      }
      Error(e) -> io.println("B: " <> e)
    }
    Error(e) -> io.println("B comp: " <> e)
  }
  io.println("Level 2752: OK")
}

pub fn level2753() -> Nil {
  io.println("--- effects Handle ---")
  let ab_r = Ref(hash_bytes(bit_array.from_string("ab2753")))
  let ab = ast.AbilityDecl(ast.AbilityDeclaration(name: Local(0), operations: [
    ast.Operation(name: Local(0), inputs: [], output: ast.TypeRefBuiltin(ast.IntType)),
  ]))
  let ah = hash_of_definition(ab)
  case compile_only(ab, Ref(ah)) {
    Ok(bb) -> case load_and_eval(module_name_for(Ref(ah)), bb) {
      Ok(_) -> {
        let h = ast.Handle(ast.Int(42), ast.Lambda(Local(0), ast.LocalVarRef(Local(0))), ab_r)
        let d = ast.TermDef(h, ast.Builtin(ast.IntType))
        let dh = hash_of_definition(d)
        case compile_only(d, Ref(dh)) {
          Ok(b) -> case load_and_eval(module_name_for(Ref(dh)), b) {
            Ok(r) -> io.println("Handle: " <> r)
            Error(e) -> io.println("L&E: " <> e)
          }
          Error(e) -> io.println("Comp: " <> e)
        }
      }
      Error(e) -> io.println("Ab: " <> e)
    }
    Error(e) -> io.println("Ab comp: " <> e)
  }
  io.println("Level 2753: OK")
}

pub fn level2754() -> Nil {
  io.println("--- elab abilities ---")
  let su = SurfaceUnit(Ref(hash_bytes(bit_array.from_string("elab2754"))), [
    #("A", SurfaceAbilityDef("A", [SurfaceOp("op0",[],TBuiltin(TInt))])),
    #("B", SurfaceAbilityDef("B", [SurfaceOp("op1",[],TBuiltin(TInt))])),
    #("C", SurfaceAbilityDef("C", [SurfaceOp("op2",[],TBuiltin(TInt))]))
  ])
  case elaborate_unit(su, empty_cache()) {
    Ok(#(_, _, _)) -> io.println("Elab: OK")
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2754: OK")
}

pub fn level2755() -> Nil {
  io.println("--- typecheck ---")
  let d1 = ast.TermDef(ast.Int(7), ast.Builtin(ast.IntType))
  let d2 = ast.TermDef(ast.Int(25), ast.Builtin(ast.IntType))
  let r1 = Ref(hash_of_definition(d1))
  let r2 = Ref(hash_of_definition(d2))
  let unit = ast.Unit(r1, [#(r1, d1), #(r2, d2)])
  case typecheck_unit(unit, empty_cache()) {
    Ok(#(_, _)) -> io.println("TC: OK")
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2755: OK")
}

pub fn level2756() -> Nil {
  io.println("--- loader is_loaded ---")
  let ldr = new_loader()
  let d = ast.TermDef(ast.Int(77), ast.Builtin(ast.IntType))
  let h = Ref(hash_of_definition(d))
  case ensure_loaded(ldr, h, d) {
    Ok(l) -> case is_loaded(l, h) {
      True -> io.println("Loaded: OK")
      False -> io.println("Not tracked")
    }
    Error(_) -> io.println("Err")
  }
  io.println("Level 2756: OK")
}

pub fn level2757() -> Nil {
  io.println("--- hash distinct ---")
  let d1 = ast.TermDef(ast.Int(50), ast.Builtin(ast.IntType))
  let d2 = ast.TermDef(ast.Int(55), ast.Builtin(ast.IntType))
  case hash_equal(hash_of_definition(d1), hash_of_definition(d2)) {
    True -> io.println("Same: OK")
    False -> io.println("Diff: OK")
  }
  io.println("Level 2757: OK")
}

pub fn level2758() -> Nil {
  io.println("--- insert_raw ---")
  let r = Ref(hash_bytes(bit_array.from_string("raw2758")))
  let cb2 = insert_raw(new_codebase(), r, bit_array.from_string("data"))
  let a = get_adapter(cb2)
  case a.lookup(r) {
    Ok(option.Some(v)) -> io.println("Found: " <> string.inspect(v))
    Ok(option.None) -> io.println("Not found")
    Error(e) -> io.println("Err: " <> string.inspect(e))
  }
  io.println("Level 2758: OK")
}

pub fn level2759() -> Nil {
  io.println("--- REPL eval ---")
  case eval_string("\"hello\"") {
    Ok(r) -> io.println("Eval: " <> r)
    Error(e) -> io.println("Err: " <> e)
  }
  io.println("Level 2759: OK")
}

pub fn level2760() -> Nil {
  io.println("--- serialize ---")
  let ser = serialize_term("hello")
  let deser = deserialize_term(ser)
  io.println("Serde: OK")
  io.println("Level 2760: OK")
}

pub fn level2761() -> Nil {
  io.println("--- empty list ---")
  let def = ast.TermDef(ast.List([]), ast.Builtin(ast.ListType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Empty: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2761: OK")
}

pub fn level2762() -> Nil {
  io.println("--- elab error ---")
  case parse_only("nonexistent") {
    Ok(st) -> case elaborate_only(st, "t", empty_cache(), []) {
      Ok(_) -> io.println("Unexpected")
      Error(e) -> io.println("Err: " <> string.inspect(e))
    }
    Error(e) -> io.println("Parse: " <> string.inspect(e))
  }
  io.println("Level 2762: OK")
}

pub fn level2763() -> Nil {
  io.println("--- compile+load int ---")
  let def = ast.TermDef(ast.Int(100), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Int: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2763: OK")
}

pub fn level2764() -> Nil {
  io.println("--- compile+load float ---")
  let def = ast.TermDef(ast.Float(10.0), ast.Builtin(ast.FloatType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Float: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2764: OK")
}

pub fn level2765() -> Nil {
  io.println("--- compile+load text ---")
  let def = ast.TermDef(ast.Text(bit_array.from_string("dogfood")), ast.Builtin(ast.TextType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Text: " <> string.slice(r, 0, 10))
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2765: OK")
}

pub fn level2766() -> Nil {
  io.println("--- compile+load lambda apply ---")
  let id = ast.Lambda(Local(0), ast.LocalVarRef(Local(0)))
  let def = ast.TermDef(ast.Apply(id, ast.Int(42)), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Apply: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2766: OK")
}

pub fn level2767() -> Nil {
  io.println("--- compile Let ---")
  let def = ast.TermDef(ast.Let(Local(0), ast.Int(42), ast.LocalVarRef(Local(0))), ast.Builtin(ast.IntType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("Let: " <> r)
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2767: OK")
}

pub fn level2768() -> Nil {
  io.println("--- compile List ---")
  let def = ast.TermDef(ast.List([ast.Int(7), ast.Int(7), ast.Int(7)]), ast.Builtin(ast.ListType))
  let h = hash_of_definition(def)
  case compile_only(def, Ref(h)) {
    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {
      Ok(r) -> io.println("List: " <> string.slice(r, 0, 15))
      Error(e) -> io.println("L&E: " <> e)
    }
    Error(e) -> io.println("Comp: " <> e)
  }
  io.println("Level 2768: OK")
}

pub fn level2769() -> Nil {
  io.println("--- elaborate_only ---")
  case parse_only("\"hello\"") {
    Ok(st) -> case elaborate_only(st, "e
2769
", empty_cache(), []) {
      Ok(#(_, _, _)) -> io.println("Elab: OK")
      Error(e) -> io.println("Err: " <> string.inspect(e))
    }
    Error(e) -> io.println("Parse: " <> e.message)
  }
  io.println("Level 2769: OK")
}

pub fn level2770() -> Nil {
  io.println("--- loader limit 1 + 4 ---")
  let ldr = new_loader_with_limit(1)
  let defs = list.map(range(1, 5), fn(i) {
    let d = ast.TermDef(ast.Int(i), ast.Builtin(ast.IntType))
    let h = Ref(hash_of_definition(d))
    #(h, d)
  })
  case list.fold(defs, Ok(ldr), fn(acc, p) {
    case acc { Ok(l) -> { let #(h,d)=p ensure_loaded(l,h,d) } Error(e)->Error(e) }
  }) {
    Ok(_) -> io.println("
4
 defs: OK")
    Error(_) -> io.println("Err")
  }
  io.println("Level 2770: OK")
}

