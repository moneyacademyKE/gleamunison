#!/usr/bin/env bb
;; rebuild_meta.clj — Generate dogfood_meta.gleam from v*.gleam files.
;; Usage: bb scripts/rebuild_meta.clj

(require '[clojure.string :as str])
(require '[babashka.fs :as fs])

(let [files (->> (fs/glob "src" "dogfood_v*.gleam")
                 (map (fn [f] {:b (Long/parseLong (re-find #"\d+" (str f)))
                                :c (slurp (str f))}))
                 (sort-by :b))
      real (remove #(re-find #"(?i)placeholder|GENERATE 50" (:c %)) files)
      batch-data (keep (fn [f] (let [fns (->> (re-seq #"pub fn level(\d+)" (:c f))
                                              (map (comp #(Long/parseLong %) second))
                                              (sort))]
                                 (when (seq fns) [(:b f) fns]))) real)
      imports (str/join "\n" (for [[b _] batch-data] (str "import dogfood_v" b " as v" b)))
      entries (str/join "\n" (for [[b fns] batch-data i fns]
                              (str "    #(\"level" i "\", v" b ".level" i "),")))
      runners (str/join "\n" (for [[b fns] batch-data]
                              (str "    #(\"Level " (last fns) " (Batch " b " cert)\", v" b ".level" (last fns) "),")))]
  (spit "src/dogfood_meta.gleam"
    (str
"import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/string

" imports "

import gleamunison/ast
import gleamunison/identity.{hash_to_debug_string}

pub fn generic_hash_level(_n: Int) -> Nil { io.println(\"stub: hash\") }
pub fn generic_parse_level(_n: Int) -> Nil { io.println(\"stub: parse\") }
pub fn generic_eval_level(_n: Int) -> Nil { io.println(\"stub: eval\") }
pub fn generic_insert_level(_n: Int) -> Nil { io.println(\"stub: insert\") }
pub fn generic_infer_level(_n: Int) -> Nil { io.println(\"stub: infer\") }

pub fn level70() -> Nil {
  io.println(\"--- Level 70: Meta-test runner ---\")
  let tests: List(#(String, fn() -> Nil)) = [
" runners "
  ]
  let total = list.length(tests)
  io.println(\"Running \" <> string.inspect(total) <> \" real tests...\")
  list.each(tests, fn(t) {
    io.print(t.0 <> \"... \")
    t.1()
  })
  io.println(\"All \" <> string.inspect(total) <> \" real levels passed!\")
  io.println(\"Level 70: OK\")
}

pub fn real_levels_list() -> List(#(String, fn() -> Nil)) {
  [
" entries "
  ]
}
"))
  (println (count batch-data) "batches, total levels:" (count (mapcat second batch-data))
           "-> src/dogfood_meta.gleam"))
