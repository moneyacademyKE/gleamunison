#!/usr/bin/env bb
;; generate_levels.clj — Data-driven dogfood levels generator
(ns generate-levels
  (:require [cheshire.core :as json]
            [babashka.fs :as fs]
            [clojure.string :as str]))

(defn next-int [] (rand-nth [42 100 50 7 99 55 33 77 10 25]))
(defn next-float-s [] (rand-nth ["3.14" "2.71" "1.5" "0.5" "10.0" "99.9"]))
(defn next-text-s [] (rand-nth ["hello" "world" "dogfood" "test" "batch"]))
(defn next-lit-s [] (rand-nth ["42" "\"hello\"" "3.14"]))

(defn gen-compile-int [n] {:n n :t "CompileInt" :args [(str (next-int))]})
(defn gen-compile-float [n] {:n n :t "CompileFloat" :args [(next-float-s)]})
(defn gen-compile-text [n] {:n n :t "CompileText" :args [(next-text-s)]})
(defn gen-lambda-apply [n] {:n n :t "LambdaApply" :args [(str (next-int))]})
(defn gen-compile-let [n] {:n n :t "CompileLet" :args [(str (next-int))]})
(defn gen-compile-list [n]
  (let [nel (rand-nth [2 3 4 5])]
    {:n n :t "CompileList" :args (repeatedly nel #(str (next-int)))}))
(defn gen-elaborate [n] {:n n :t "Elaborate" :args [(next-lit-s)]})
(defn gen-loader-limit [n]
  (let [lim (max 1 (rand-int 5))
        ndefs (+ lim 3)]
    {:n n :t "LoaderLimit" :args [(str lim) (str ndefs)]}))
(defn gen-codebase-insert [n]
  (let [nd (max 1 (rand-int 5))]
    {:n n :t "CodebaseInsert" :args [(str nd) (str (next-int))]}))
(defn gen-storage-stress [n]
  (let [ni (* 100 (max 1 (rand-int 5)))]
    {:n n :t "StorageStress" :args [(str ni)]}))
(defn gen-cross-ref [n] {:n n :t "CrossRef" :args [(str (next-int))]})
(defn gen-effects-handle [n] {:n n :t "EffectsHandle" :args [(str (next-int))]})
(defn gen-elab-unit-abilities [n]
  (let [nab (max 1 (rand-int 4))]
    {:n n :t "ElabUnitAbilities" :args [(str nab)]}))
(defn gen-typecheck [n] {:n n :t "Typecheck" :args [(str (next-int)) (str (next-int))]})
(defn gen-loader-loaded [n] {:n n :t "LoaderLoaded" :args [(str (next-int))]})
(defn gen-hash-distinct [n] {:n n :t "HashDistinct" :args [(str (next-int)) (str (next-int))]})
(defn gen-insert-raw [n] {:n n :t "InsertRaw" :args []})
(defn gen-repl-eval [n] {:n n :t "ReplEval" :args [(next-lit-s)]})
(defn gen-serialize [n] {:n n :t "Serialize" :args [(str (next-int))]})
(defn gen-empty-list [n] {:n n :t "EmptyList" :args []})
(defn gen-elab-error [n] {:n n :t "ElabError" :args ["(lam x"]})
(defn gen-compile-construct [n] {:n n :t "CompileConstruct" :args []})
(defn gen-type-pretty [n]
  (let [lit (next-lit-s)
        expected (cond
                   (str/includes? lit "\"") "Text"
                   (str/includes? lit ".") "Float"
                   :else "Int")]
    {:n n :t "TypePretty" :args [lit expected]}))
(defn gen-infer-term [n]
  (let [lit (next-lit-s)
        expected (cond
                   (str/includes? lit "\"") "Text"
                   (str/includes? lit ".") "Float"
                   :else "Int")]
    {:n n :t "InferTerm" :args [lit expected]}))

(def all-templates
  [gen-compile-int gen-compile-float gen-compile-text gen-lambda-apply
   gen-compile-let gen-compile-list gen-elaborate gen-loader-limit
   gen-codebase-insert gen-storage-stress gen-cross-ref gen-effects-handle
   gen-elab-unit-abilities gen-typecheck gen-loader-loaded gen-hash-distinct
   gen-insert-raw gen-repl-eval gen-serialize gen-empty-list gen-elab-error
   gen-compile-construct gen-type-pretty gen-infer-term])

(defn get-template-for-level [n]
  (let [nt (count all-templates)]
    (nth all-templates (mod n nt))))

(defn generate-levels [start-n count-n]
  (map (fn [i]
         (let [lvl (+ start-n i)
               gen-fn (get-template-for-level lvl)]
           (gen-fn lvl)))
       (range count-n)))

(defn -main [& args]
  (let [args-map (set args)
        regenerate? (contains? args-map "--regenerate-all")
        count-flag (some-> (second (first (filter #(= "--count" (first %)) (partition 2 args)))) Integer/parseInt)
        default-count (or count-flag 5696) ;; 1001 to 6696
        db-file "src/dogfood_data.json"]
    (if (or regenerate? (not (fs/exists? db-file)))
      (do
        (println "Generating all" default-count "levels starting from 1001...")
        (let [levels (generate-levels 1001 default-count)]
          (spit db-file (json/generate-string levels {:pretty true}))
          (println "Wrote" db-file)))
      (do
        (println "Database exists. Loading and adding new levels...")
        (let [existing (json/parse-string (slurp db-file) true)
              latest-n (apply max (map :n existing))
              next-n (inc latest-n)
              cnt (or count-flag 50)
              _ (println "Generating" cnt "levels starting from" next-n "...")
              new-levels (generate-levels next-n cnt)
              merged (concat existing new-levels)]
          (spit db-file (json/generate-string merged {:pretty true}))
          (println "Wrote" (count merged) "total levels to" db-file))))))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
