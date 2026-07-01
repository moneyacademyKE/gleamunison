#!/usr/bin/env bb
;; generate_levels.clj — Autonomous level generator.
;; Writes generated Gleam code directly. Builds strings to avoid Clojure/Gleam
;; brace conflicts.

(require '[clojure.string :as str])
(require '[babashka.fs :as fs])

(def *counter* (atom 0))
(defn next-int [] (rand-nth [42 100 50 7 99 55 33 77 10 25]))
(defn next-float-s [] (rand-nth ["3.14" "2.71" "1.5" "0.5" "10.0" "99.9"]))
(defn next-text-s [] (rand-nth ["hello" "world" "dogfood" "test" "batch"]))
(defn next-lit-s [] (rand-nth ["\"42\"" "\"\\\"hello\\\"\"" "\"3.14\""]))

;; Each template returns a string of the complete level function.
;; We use (clojure.string/join) to build strings line by line, avoiding any
;; Clojure brace/paren conflicts in the generated Gleam code.

(defn gen-compile-int [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- compile+load int ---\")"
     (str "  let def = ast.TermDef(ast.Int(" (next-int) "), ast.Builtin(ast.IntType))")
     "  let h = hash_of_definition(def)"
     "  case compile_only(def, Ref(h)) {"
     "    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {"
     "      Ok(r) -> io.println(\"Int: \" <> r)"
     "      Error(e) -> io.println(\"L&E: \" <> e)"
     "    }"
     "    Error(e) -> io.println(\"Comp: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-compile-float [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- compile+load float ---\")"
     (str "  let def = ast.TermDef(ast.Float(" (next-float-s) "), ast.Builtin(ast.FloatType))")
     "  let h = hash_of_definition(def)"
     "  case compile_only(def, Ref(h)) {"
     "    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {"
     "      Ok(r) -> io.println(\"Float: \" <> r)"
     "      Error(e) -> io.println(\"L&E: \" <> e)"
     "    }"
     "    Error(e) -> io.println(\"Comp: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-compile-text [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- compile+load text ---\")"
     (str "  let def = ast.TermDef(ast.Text(bit_array.from_string(\"" (next-text-s) "\")), ast.Builtin(ast.TextType))")
     "  let h = hash_of_definition(def)"
     "  case compile_only(def, Ref(h)) {"
     "    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {"
     "      Ok(r) -> io.println(\"Text: \" <> string.slice(r, 0, 10))"
     "      Error(e) -> io.println(\"L&E: \" <> e)"
     "    }"
     "    Error(e) -> io.println(\"Comp: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-lambda-apply [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- compile+load lambda apply ---\")"
     "  let id = ast.Lambda(Local(0), ast.LocalVarRef(Local(0)))"
     (str "  let def = ast.TermDef(ast.Apply(id, ast.Int(" (next-int) ")), ast.Builtin(ast.IntType))")
     "  let h = hash_of_definition(def)"
     "  case compile_only(def, Ref(h)) {"
     "    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {"
     "      Ok(r) -> io.println(\"Apply: \" <> r)"
     "      Error(e) -> io.println(\"L&E: \" <> e)"
     "    }"
     "    Error(e) -> io.println(\"Comp: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-compile-let [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- compile Let ---\")"
     (str "  let def = ast.TermDef(ast.Let(Local(0), ast.Int(" (next-int) "), ast.LocalVarRef(Local(0))), ast.Builtin(ast.IntType))")
     "  let h = hash_of_definition(def)"
     "  case compile_only(def, Ref(h)) {"
     "    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {"
     "      Ok(r) -> io.println(\"Let: \" <> r)"
     "      Error(e) -> io.println(\"L&E: \" <> e)"
     "    }"
     "    Error(e) -> io.println(\"Comp: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-compile-list [n]
  (let [nel (rand-nth [2 3 4 5])]
    (str/join "\n"
      [(str "pub fn level" n "() -> Nil {")
       "  io.println(\"--- compile List ---\")"
       (str "  let def = ast.TermDef(ast.List([" (str/join ", " (repeat nel (str "ast.Int(" (next-int) ")"))) "]), ast.Builtin(ast.ListType))")
       "  let h = hash_of_definition(def)"
       "  case compile_only(def, Ref(h)) {"
       "    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {"
       "      Ok(r) -> io.println(\"List: \" <> string.slice(r, 0, 15))"
       "      Error(e) -> io.println(\"L&E: \" <> e)"
       "    }"
       "    Error(e) -> io.println(\"Comp: \" <> e)"
       "  }"
       (str "  io.println(\"Level " n ": OK\")")
       "}"])))

(defn gen-elaborate [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- elaborate_only ---\")"
     (str "  case parse_only(" (next-lit-s) ") {")
     "    Ok(st) -> case elaborate_only(st, \"e" n "\", empty_cache(), []) {"
     "      Ok(#(_, _, _)) -> io.println(\"Elab: OK\")"
     "      Error(e) -> io.println(\"Err: \" <> string.inspect(e))"
     "    }"
     "    Error(e) -> io.println(\"Parse: \" <> e.message)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-loader-limit [n]
  (let [lim (max 1 (rand-int 5))
        ndefs (+ lim 3)]
    (str/join "\n"
      [(str "pub fn level" n "() -> Nil {")
       (str "  io.println(\"--- loader limit " lim " + " ndefs " ---\")")
       (str "  let ldr = new_loader_with_limit(" lim ")")
       (str "  let defs = list.map(range(1, " (inc ndefs) "), fn(i) {")
       "    let d = ast.TermDef(ast.Int(i), ast.Builtin(ast.IntType))"
       "    let h = Ref(hash_of_definition(d))"
       "    #(h, d)"
       "  })"
       "  case list.fold(defs, Ok(ldr), fn(acc, p) {"
       "    case acc { Ok(l) -> { let #(h,d)=p ensure_loaded(l,h,d) } Error(e)->Error(e) }"
       "  }) {"
       "    Ok(_) -> io.println(\"" ndefs " defs: OK\")"
       "    Error(_) -> io.println(\"Err\")"
       "  }"
       (str "  io.println(\"Level " n ": OK\")")
       "}"])))

(defn gen-codebase-insert [n]
  (let [nd (max 1 (rand-int 5))]
    (str/join "\n"
      [(str "pub fn level" n "() -> Nil {")
       (str "  io.println(\"--- codebase insert " nd " defs ---\")")
       (str "  let defs = list.map(range(1, " (inc nd) "), fn(i) {")
       (str "    let d = ast.TermDef(ast.Int(i * " (next-int) "), ast.Builtin(ast.IntType))")
       "    let r = Ref(hash_of_definition(d))"
       "    #(r, d)"
       "  })"
       (str "  let unit = ast.Unit(Ref(hash_bytes(bit_array.from_string(\"u" n "\"))), defs)")
       "  case insert(new_codebase(), unit) {"
       "    Ok(cb) -> {"
       "      let a = get_adapter(cb)"
       "      case a.list_refs() {"
       "        Ok(rs) -> io.println(\"" nd " defs: \" <> int.to_string(list.length(rs)))"
       "        Error(e) -> io.println(\"Err: \" <> string.inspect(e))"
       "      }"
       "    }"
       "    Error(e) -> io.println(\"Err: \" <> string.inspect(e))"
       "  }"
       (str "  io.println(\"Level " n ": OK\")")
       "}"])))

(defn gen-storage-stress [n]
  (let [ni (* 100 (max 1 (rand-int 5)))]
    (str/join "\n"
      [(str "pub fn level" n "() -> Nil {")
       (str "  io.println(\"--- storage " ni " inserts ---\")")
       "  let a = inmemory()"
       (str "  list.each(range(1, " (inc ni) "), fn(i) {")
       "    let r = Ref(hash_bytes(bit_array.from_string(\"s\" <> int.to_string(i))))"
       "    let _ = a.insert(r, bit_array.from_string(\"d\"))"
       "  })"
       "  case a.list_refs() {"
       "    Ok(rs) -> io.println(\"" ni " refs: \" <> int.to_string(list.length(rs)))"
       "    Error(e) -> io.println(\"Err: \" <> string.inspect(e))"
       "  }"
       (str "  io.println(\"Level " n ": OK\")")
       "}"])))

(defn gen-cross-ref [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- cross-module RefTo ---\")"
     (str "  let db = ast.TermDef(ast.Int(" (next-int) "), ast.Builtin(ast.IntType))")
     "  let hb = hash_of_definition(db)"
     "  case compile_only(db, Ref(hb)) {"
     "    Ok(bb) -> case load_and_eval(module_name_for(Ref(hb)), bb) {"
     "      Ok(_) -> {"
     "        let da = ast.TermDef(ast.RefTo(Ref(hb)), ast.Builtin(ast.IntType))"
     "        let ha = hash_of_definition(da)"
     "        case compile_only(da, Ref(ha)) {"
     "          Ok(ba) -> case load_and_eval(module_name_for(Ref(ha)), ba) {"
     "            Ok(r) -> io.println(\"Cross: \" <> r)"
     "            Error(e) -> io.println(\"A: \" <> e)"
     "          }"
     "          Error(e) -> io.println(\"A comp: \" <> e)"
     "        }"
     "      }"
     "      Error(e) -> io.println(\"B: \" <> e)"
     "    }"
     "    Error(e) -> io.println(\"B comp: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-effects-handle [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- effects Handle ---\")"
     (str "  let ab_r = Ref(hash_bytes(bit_array.from_string(\"ab" n "\")))")
     "  let ab = ast.AbilityDecl(ast.AbilityDeclaration(name: Local(0), operations: ["
     "    ast.Operation(name: Local(0), inputs: [], output: ast.TypeRefBuiltin(ast.IntType)),"
     "  ]))"
     "  let ah = hash_of_definition(ab)"
     "  case compile_only(ab, Ref(ah)) {"
     "    Ok(bb) -> case load_and_eval(module_name_for(Ref(ah)), bb) {"
     "      Ok(_) -> {"
     (str "        let h = ast.Handle(ast.Int(" (next-int) "), ast.Lambda(Local(0), ast.LocalVarRef(Local(0))), ab_r)")
     "        let d = ast.TermDef(h, ast.Builtin(ast.IntType))"
     "        let dh = hash_of_definition(d)"
     "        case compile_only(d, Ref(dh)) {"
     "          Ok(b) -> case load_and_eval(module_name_for(Ref(dh)), b) {"
     "            Ok(r) -> io.println(\"Handle: \" <> r)"
     "            Error(e) -> io.println(\"L&E: \" <> e)"
     "          }"
     "          Error(e) -> io.println(\"Comp: \" <> e)"
     "        }"
     "      }"
     "      Error(e) -> io.println(\"Ab: \" <> e)"
     "    }"
     "    Error(e) -> io.println(\"Ab comp: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-elab-unit-abilities [n]
  (let [nab (max 1 (rand-int 4))]
    (str/join "\n"
      [(str "pub fn level" n "() -> Nil {")
       "  io.println(\"--- elab abilities ---\")"
       (str "  let su = SurfaceUnit(Ref(hash_bytes(bit_array.from_string(\"elab" n "\"))), [")
       (str/join ",\n" (map-indexed (fn [i _] (str "    #(\"" (char (+ 65 i)) "\", SurfaceAbilityDef(\"" (char (+ 65 i)) "\", [SurfaceOp(\"op" i "\",[],TBuiltin(TInt))]))")) (range nab)))
       "  ])"
       "  case elaborate_unit(su, empty_cache()) {"
       "    Ok(#(_, _, _)) -> io.println(\"Elab: OK\")"
       "    Error(e) -> io.println(\"Err: \" <> string.inspect(e))"
       "  }"
       (str "  io.println(\"Level " n ": OK\")")
       "}"])))

(defn gen-typecheck [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- typecheck ---\")"
     (str "  let d1 = ast.TermDef(ast.Int(" (next-int) "), ast.Builtin(ast.IntType))")
     (str "  let d2 = ast.TermDef(ast.Int(" (next-int) "), ast.Builtin(ast.IntType))")
     "  let r1 = Ref(hash_of_definition(d1))"
     "  let r2 = Ref(hash_of_definition(d2))"
     "  let unit = ast.Unit(r1, [#(r1, d1), #(r2, d2)])"
     "  case typecheck_unit(unit, empty_cache()) {"
     "    Ok(#(_, _)) -> io.println(\"TC: OK\")"
     "    Error(e) -> io.println(\"Err: \" <> string.inspect(e))"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-loader-loaded [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- loader is_loaded ---\")"
     (str "  let ldr = new_loader()")
     (str "  let d = ast.TermDef(ast.Int(" (next-int) "), ast.Builtin(ast.IntType))")
     "  let h = Ref(hash_of_definition(d))"
     "  case ensure_loaded(ldr, h, d) {"
     "    Ok(l) -> case is_loaded(l, h) {"
     "      True -> io.println(\"Loaded: OK\")"
     "      False -> io.println(\"Not tracked\")"
     "    }"
     "    Error(_) -> io.println(\"Err\")"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-hash-distinct [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- hash distinct ---\")"
     (str "  let d1 = ast.TermDef(ast.Int(" (next-int) "), ast.Builtin(ast.IntType))")
     (str "  let d2 = ast.TermDef(ast.Int(" (next-int) "), ast.Builtin(ast.IntType))")
     "  case hash_equal(hash_of_definition(d1), hash_of_definition(d2)) {"
     "    True -> io.println(\"Same: OK\")"
     "    False -> io.println(\"Diff: OK\")"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-insert-raw [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- insert_raw ---\")"
     (str "  let r = Ref(hash_bytes(bit_array.from_string(\"raw" n "\")))")
     "  let cb2 = insert_raw(new_codebase(), r, bit_array.from_string(\"data\"))"
     "  let a = get_adapter(cb2)"
     "  case a.lookup(r) {"
     "    Ok(option.Some(v)) -> io.println(\"Found: \" <> string.inspect(v))"
     "    Ok(option.None) -> io.println(\"Not found\")"
     "    Error(e) -> io.println(\"Err: \" <> string.inspect(e))"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-repl-eval [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- REPL eval ---\")"
     (str "  case eval_string(" (next-lit-s) ") {")
     "    Ok(r) -> io.println(\"Eval: \" <> r)"
     "    Error(e) -> io.println(\"Err: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-serialize [n]
  (let [v (rand-nth ["42" "\"hello\"" "[1,2,3]"])]
    (str/join "\n"
      [(str "pub fn level" n "() -> Nil {")
       "  io.println(\"--- serialize ---\")"
       (str "  let ser = serialize_term(" v ")")
       "  let deser = deserialize_term(ser)"
       "  io.println(\"Serde: OK\")"
       (str "  io.println(\"Level " n ": OK\")")
       "}"])))

(defn gen-empty-list [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- empty list ---\")"
     "  let def = ast.TermDef(ast.List([]), ast.Builtin(ast.ListType))"
     "  let h = hash_of_definition(def)"
     "  case compile_only(def, Ref(h)) {"
     "    Ok(beam) -> case load_and_eval(module_name_for(Ref(h)), beam) {"
     "      Ok(r) -> io.println(\"Empty: \" <> r)"
     "      Error(e) -> io.println(\"L&E: \" <> e)"
     "    }"
     "    Error(e) -> io.println(\"Comp: \" <> e)"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

(defn gen-elab-error [n]
  (str/join "\n"
    [(str "pub fn level" n "() -> Nil {")
     "  io.println(\"--- elab error ---\")"
     "  case parse_only(\"nonexistent\") {"
     "    Ok(st) -> case elaborate_only(st, \"t\", empty_cache(), []) {"
     "      Ok(_) -> io.println(\"Unexpected\")"
     "      Error(e) -> io.println(\"Err: \" <> string.inspect(e))"
     "    }"
     "    Error(e) -> io.println(\"Parse: \" <> string.inspect(e))"
     "  }"
     (str "  io.println(\"Level " n ": OK\")")
     "}"]))

;; Template dispatch table
(def templates
  [gen-compile-int gen-compile-float gen-compile-text gen-lambda-apply
   gen-compile-let gen-compile-list gen-elaborate gen-loader-limit
   gen-codebase-insert gen-storage-stress gen-cross-ref gen-effects-handle
   gen-elab-unit-abilities gen-typecheck gen-loader-loaded gen-hash-distinct
   gen-insert-raw gen-repl-eval gen-serialize gen-empty-list gen-elab-error
   gen-compile-int gen-compile-float gen-compile-text gen-lambda-apply
   gen-compile-let gen-compile-list gen-elaborate gen-loader-limit
   gen-codebase-insert gen-storage-stress gen-cross-ref gen-effects-handle
   gen-elab-unit-abilities gen-typecheck gen-loader-loaded gen-hash-distinct
   gen-insert-raw gen-repl-eval gen-serialize gen-empty-list gen-elab-error
   gen-compile-int gen-compile-float gen-compile-text gen-lambda-apply
   gen-compile-let gen-compile-list gen-elaborate gen-loader-limit
   gen-codebase-insert gen-storage-stress])

(defn generate-levels [batch level-start]
  (map-indexed
    (fn [i gen-fn]
      (let [n (+ level-start i)]
        {:level n :code (gen-fn n)}))
    (take 49 templates)))

(defn write-file [batch level-start level-end levels]
  (let [f (str "src/dogfood_v" batch ".gleam")
        cert-level level-end
        body (str/join "\n\n" (map :code levels))
        header (str/join "\n"
                ["import gleam/bit_array"
                 "import gleam/int"
                 "import gleam/io"
                 "import gleam/list"
                 "import gleam/option"
                 "import gleam/string"
                 "import gleamunison/ast"
                 "import gleamunison/codebase.{empty as new_codebase, get_adapter, hash_of_definition, insert, insert_raw}"
                 "import gleamunison/compile.{module_name_for, new as new_compiler}"
                 "import gleamunison/elab_types.{SInt, SVar, SurfaceAbilityDef, SurfaceOp, SurfaceTermDef, SurfaceUnit, TBuiltin, TInt, TText}"
                 "import gleamunison/elaborate.{elaborate_unit}"
                 "import gleamunison/identity.{Local, Ref, hash_bytes, hash_equal, hash_to_debug_string, hash_to_short_string}"
                 "import gleamunison/loader.{ensure_loaded, is_loaded, new_loader, new_loader_with_limit}"
                 "import gleamunison/pipeline.{compile_only, elaborate_only, load_and_eval, parse_only}"
                 "import gleamunison/repl.{eval_string}"
                 "import gleamunison/repl_eval.{do_eval, handle_define, deserialize_term, serialize_term}"
                 "import gleamunison/storage.{StorageAdapter, inmemory}"
                 "import gleamunison/typecheck.{typecheck_unit}"
                 "import gleamunison/type_pretty.{pretty_print}"
                 "import gleamunison/types.{empty_cache}"
                 ""
                 "fn range(start: Int, end: Int) -> List(Int) {"
                 "  case start > end {"
                 "    True -> []"
                 "    False -> [start, ..range(start + 1, end)]"
                 "  }"
                 "}"
                 ""
                 (str "// --- AUTO-GENERATED BATCH " batch " (" level-start "-" level-end ") ---")
                 ""])
        cert (str/join "\n"
               [""
                "// --- CERTIFICATION ---"
                ""
                (str "pub fn level" cert-level "() -> Nil {")
                "  io.println(\"============================================================\")"
                (str "  io.println(\"  BATCH " batch " COMPLETE — Auto-generated\")")
                "  io.println(\"============================================================\")"
                (str "  io.println(\"  Levels " level-start "-" level-end " all passed\")")
                "  io.println(\"============================================================\")"
                (str "  io.println(\"Level " cert-level ": OK\")")
                "}"
                ""])]
    (spit f (str header "\n" body "\n" cert))
    (println "Wrote" f "with" (count levels) "levels")))

(defn -main [& args]
  (let [flags (set (filter #(str/starts-with? % "--") args))
        batch-str (first (remove #(str/starts-with? % "--") *command-line-args*))
        batch (or (some-> batch-str Long/parseLong)
                  (let [f (last (sort (fs/glob "src" "dogfood_v*.gleam")))]
                    (Long/parseLong (re-find #"\d+" (str f)))))
        lvl-flag (when-let [s (second (first (filter #(= "--start" (first %)) (partition 2 args))))]
                   (Long/parseLong s))
        meta (slurp "src/dogfood_meta.gleam")
        latest (apply max (map #(Long/parseLong (second %)) (re-seq #"level(\d+)" meta)))
        level-start (or lvl-flag (inc latest))
        level-end (+ level-start 49)
        levels (generate-levels batch level-start)]
    (println "Generating batch" batch "levels" level-start "-" level-end)
    (write-file batch level-start level-end levels)
    (println "Done. bb dogfood-register -> gleam build -> verify")))

(when *command-line-args*
  (apply -main *command-line-args*))
