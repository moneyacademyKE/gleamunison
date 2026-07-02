import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleamunison/ast
import gleamunison/codebase
import gleamunison/compile
import gleamunison/elab_types
import gleamunison/elaborate
import gleamunison/identity.{Local, Ref, hash_bytes}
import gleamunison/loader
import gleamunison/pipeline
import gleamunison/repl
import gleamunison/repl_eval
import gleamunison/storage
import gleamunison/type_pretty
import gleamunison/typecheck
import gleamunison/types
import gleamunison/util.{range}
import dogfood_data.{type LevelData}

pub fn run_level(lvl: LevelData) -> Nil {
  case lvl {
    dogfood_data.CompileInt(n, val) -> {
      io.println("--- compile+load int ---")
      let def = ast.TermDef(ast.Int(val), ast.Builtin(ast.IntType))
      let h = codebase.hash_of_definition(def)
      let assert Ok(beam) = pipeline.compile_only(def, Ref(h))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(h)), beam)
      io.println("Int: " <> r <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.CompileFloat(n, val) -> {
      io.println("--- compile+load float ---")
      let def = ast.TermDef(ast.Float(val), ast.Builtin(ast.FloatType))
      let h = codebase.hash_of_definition(def)
      let assert Ok(beam) = pipeline.compile_only(def, Ref(h))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(h)), beam)
      io.println("Float: " <> r <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.CompileText(n, val) -> {
      io.println("--- compile+load text ---")
      let def = ast.TermDef(ast.Text(bit_array.from_string(val)), ast.Builtin(ast.TextType))
      let h = codebase.hash_of_definition(def)
      let assert Ok(beam) = pipeline.compile_only(def, Ref(h))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(h)), beam)
      io.println("Text: " <> string.slice(r, 0, 10) <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.LambdaApply(n, val) -> {
      io.println("--- compile+load lambda apply ---")
      let id = ast.Lambda(Local(0), ast.LocalVarRef(Local(0)))
      let def = ast.TermDef(ast.Apply(id, ast.Int(val)), ast.Builtin(ast.IntType))
      let h = codebase.hash_of_definition(def)
      let assert Ok(beam) = pipeline.compile_only(def, Ref(h))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(h)), beam)
      io.println("Apply: " <> r <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.CompileLet(n, val) -> {
      io.println("--- compile Let ---")
      let def = ast.TermDef(ast.Let(Local(0), ast.Int(val), ast.LocalVarRef(Local(0))), ast.Builtin(ast.IntType))
      let h = codebase.hash_of_definition(def)
      let assert Ok(beam) = pipeline.compile_only(def, Ref(h))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(h)), beam)
      io.println("Let: " <> r <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.CompileList(n, elements) -> {
      io.println("--- compile List ---")
      let def = ast.TermDef(ast.List(list.map(elements, ast.Int)), ast.Builtin(ast.ListType))
      let h = codebase.hash_of_definition(def)
      let assert Ok(beam) = pipeline.compile_only(def, Ref(h))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(h)), beam)
      io.println("List: " <> string.slice(r, 0, 15) <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.Elaborate(n, lit) -> {
      io.println("--- elaborate_only ---")
      let assert Ok(st) = pipeline.parse_only(lit)
      let assert Ok(#(_, _, _)) = pipeline.elaborate_only(st, "e" <> int.to_string(n), types.empty_cache(), [])
      io.println("Elab: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.LoaderLimit(n, limit, count) -> {
      io.println("--- loader limit ---")
      let ldr = loader.new_loader_with_limit(limit)
      let defs = list.map(range(1, count), fn(i) {
        let d = ast.TermDef(ast.Int(i), ast.Builtin(ast.IntType))
        let h = Ref(codebase.hash_of_definition(d))
        #(h, d)
      })
      let assert Ok(_) = list.fold(defs, Ok(ldr), fn(acc, p) {
        case acc { Ok(l) -> loader.ensure_loaded(l, p.0, p.1) Error(e) -> Error(e) }
      })
      io.println("limit: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.CodebaseInsert(n, count, mult) -> {
      io.println("--- codebase insert ---")
      let defs = list.map(range(1, count), fn(i) {
        let d = ast.TermDef(ast.Int(i * mult), ast.Builtin(ast.IntType))
        let r = Ref(codebase.hash_of_definition(d))
        #(r, d)
      })
      let unit = ast.Unit(Ref(hash_bytes(bit_array.from_string("u" <> int.to_string(n)))), defs)
      let assert Ok(cb) = codebase.insert(codebase.empty(), unit)
      let a = codebase.get_adapter(cb)
      let assert Ok(rs) = a.list_refs()
      io.println("insert: OK " <> int.to_string(list.length(rs)))
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.StorageStress(n, count) -> {
      io.println("--- storage stress ---")
      let a = storage.inmemory()
      list.each(range(1, count), fn(i) {
        let r = Ref(hash_bytes(bit_array.from_string("s" <> int.to_string(i))))
        let _ = a.insert(r, bit_array.from_string("d"))
      })
      let assert Ok(rs) = a.list_refs()
      io.println("refs: " <> int.to_string(list.length(rs)))
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.CrossRef(n, val) -> {
      io.println("--- cross-module RefTo ---")
      let db = ast.TermDef(ast.Int(val), ast.Builtin(ast.IntType))
      let hb = codebase.hash_of_definition(db)
      let assert Ok(bb) = pipeline.compile_only(db, Ref(hb))
      let assert Ok(_) = pipeline.load_and_eval(compile.module_name_for(Ref(hb)), bb)
      let da = ast.TermDef(ast.RefTo(Ref(hb)), ast.Builtin(ast.IntType))
      let ha = codebase.hash_of_definition(da)
      let assert Ok(ba) = pipeline.compile_only(da, Ref(ha))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(ha)), ba)
      io.println("Cross: " <> r <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.EffectsHandle(n, val) -> {
      io.println("--- effects Handle ---")
      let ab_r = Ref(hash_bytes(bit_array.from_string("ab" <> int.to_string(n))))
      let ab = ast.AbilityDecl(ast.AbilityDeclaration(name: Local(0), operations: [
        ast.Operation(name: Local(0), inputs: [], output: ast.TypeRefBuiltin(ast.IntType)),
      ]))
      let ah = codebase.hash_of_definition(ab)
      let assert Ok(bb) = pipeline.compile_only(ab, Ref(ah))
      let assert Ok(_) = pipeline.load_and_eval(compile.module_name_for(Ref(ah)), bb)
      let h = ast.Handle(ast.Int(val), ast.Lambda(Local(0), ast.LocalVarRef(Local(0))), ab_r)
      let d = ast.TermDef(h, ast.Builtin(ast.IntType))
      let dh = codebase.hash_of_definition(d)
      let assert Ok(b) = pipeline.compile_only(d, Ref(dh))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(dh)), b)
      io.println("Handle: " <> r <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.ElabUnitAbilities(n, count) -> {
      io.println("--- elab abilities ---")
      let su = elab_types.SurfaceUnit(Ref(hash_bytes(bit_array.from_string("elab" <> int.to_string(n)))), list.map(range(0, count - 1), fn(i) {
        let name = "Ab" <> int.to_string(i)
        #(name, elab_types.SurfaceAbilityDef(name, [elab_types.SurfaceOp("op" <> int.to_string(i), [], elab_types.TBuiltin(elab_types.TInt))]))
      }))
      let assert Ok(#(_, _, _)) = elaborate.elaborate_unit(su, types.empty_cache())
      io.println("Elab: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.Typecheck(n, v1, v2) -> {
      io.println("--- typecheck ---")
      let d1 = ast.TermDef(ast.Int(v1), ast.Builtin(ast.IntType))
      let d2 = ast.TermDef(ast.Int(v2), ast.Builtin(ast.IntType))
      let r1 = Ref(codebase.hash_of_definition(d1))
      let r2 = Ref(codebase.hash_of_definition(d2))
      let unit = ast.Unit(r1, [#(r1, d1), #(r2, d2)])
      let assert Ok(#(_, _)) = typecheck.typecheck_unit(unit, types.empty_cache())
      io.println("TC: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.LoaderLoaded(n, val) -> {
      io.println("--- loader is_loaded ---")
      let ldr = loader.new_loader()
      let d = ast.TermDef(ast.Int(val), ast.Builtin(ast.IntType))
      let h = Ref(codebase.hash_of_definition(d))
      let assert Ok(l) = loader.ensure_loaded(ldr, h, d)
      let assert True = loader.is_loaded(l, h)
      io.println("Loaded: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.HashDistinct(n, v1, v2) -> {
      io.println("--- hash distinct ---")
      let d1 = ast.TermDef(ast.Int(v1), ast.Builtin(ast.IntType))
      let d2 = ast.TermDef(ast.Int(v2), ast.Builtin(ast.IntType))
      let assert False = identity.hash_equal(codebase.hash_of_definition(d1), codebase.hash_of_definition(d2))
      io.println("Diff: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.InsertRaw(n) -> {
      io.println("--- insert_raw ---")
      let r = Ref(hash_bytes(bit_array.from_string("raw" <> int.to_string(n))))
      let cb2 = codebase.insert_raw(codebase.empty(), r, bit_array.from_string("data"))
      let a = codebase.get_adapter(cb2)
      let assert Ok(Some(v)) = a.lookup(r)
      io.println("Found: " <> string.inspect(v))
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.ReplEval(n, lit) -> {
      io.println("--- REPL eval ---")
      let assert Ok(_) = repl.eval_string(lit)
      io.println("REPL: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.Serialize(n, val) -> {
      io.println("--- serialize/deserialize ---")
      let ser = repl_eval.serialize_term(val)
      let deser: Int = repl_eval.deserialize_term(ser)
      let assert True = val == deser
      io.println("Ser: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.EmptyList(n) -> {
      io.println("--- compile empty list ---")
      let def = ast.TermDef(ast.List([]), ast.Builtin(ast.ListType))
      let h = codebase.hash_of_definition(def)
      let assert Ok(beam) = pipeline.compile_only(def, Ref(h))
      let assert Ok(r) = pipeline.load_and_eval(compile.module_name_for(Ref(h)), beam)
      io.println("Empty: " <> r <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.ElabError(n, lit) -> {
      io.println("--- elab error check ---")
      let assert Error(_) = pipeline.parse_only(lit)
      io.println("Err: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.CompileConstruct(n) -> {
      io.println("--- compile Construct ---")
      let ctor_ref = Ref(hash_bytes(bit_array.from_string("ctor")))
      let def = ast.TermDef(ast.Construct(ctor_ref, [ast.Int(42)]), ast.Builtin(ast.IntType))
      let h = codebase.hash_of_definition(def)
      let assert Ok(beam) = pipeline.compile_only(def, Ref(h))
      let assert Ok(_) = pipeline.load_and_eval(compile.module_name_for(Ref(h)), beam)
      io.println("Construct: OK")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.TypePretty(n, lit, expected) -> {
      io.println("--- type pretty-print ---")
      let assert Ok(t) = pipeline.parse_only(lit)
      let assert Ok(#(unit, _, _)) = pipeline.elaborate_only(t, "tp" <> int.to_string(n), types.empty_cache(), [])
      let assert [#(_, ast.TermDef(_, ty))] = unit.defs
      let pretty = type_pretty.pretty_print(ty)
      let assert True = string.contains(pretty, expected)
      io.println("Pretty: " <> pretty <> " [OK]")
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
    dogfood_data.InferTerm(n, lit, expected) -> {
      io.println("--- infer_term ---")
      let assert Ok(t) = pipeline.parse_only(lit)
      let assert Ok(#(unit, _, _)) = pipeline.elaborate_only(t, "inf" <> int.to_string(n), types.empty_cache(), [])
      let assert [#(_, ast.TermDef(_, ty))] = unit.defs
      let pretty = type_pretty.pretty_print(ty)
      let assert True = string.contains(pretty, expected)
      io.println("Infer: " <> pretty)
      io.println("Level " <> int.to_string(n) <> ": OK")
    }
  }
}
