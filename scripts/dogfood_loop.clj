#!/usr/bin/env bb
;; dogfood_loop.clj — Registration and verification helper.
(ns dogfood-loop
  (:require [clojure.string :as str]
            [babashka.fs :as fs]
            [cheshire.core :as json]))

(def repo (str (fs/parent (fs/parent *file*))))

(defn sh [& args]
  (let [pb (doto (java.lang.ProcessBuilder. (into-array String (cons "/bin/sh" (cons "-c" [(str/join " " args)]))))
             (.directory (java.io.File. repo))
             (.redirectErrorStream true))
        p (.start pb)
        out (slurp (.getInputStream p))
        exit (.waitFor p)]
    {:exit exit :out (str/trim out)}))

(defn latest-level []
  (let [db-path (str repo "/src/dogfood_data.json")
        levels (if (fs/exists? db-path)
                 (json/parse-string (slurp db-path) true)
                 [])
        max-n (if (seq levels)
                (apply max (map :n levels))
                1000)]
    [nil max-n]))

(defn count-levels []
  (let [db-path (str repo "/src/dogfood_data.json")]
    (if (fs/exists? db-path)
      (count (json/parse-string (slurp db-path) true))
      0)))

(defn register []
  (println "Registering levels...")
  (let [[_ lvl] (latest-level)
        new-end (inc lvl)]
    (doseq [f [(str repo "/src/dogfood.gleam") (str repo "/src/gleamunison.gleam")]]
      (let [c (slurp f)]
        (when-let [[_ n] (re-find #"range\(1, (\d+)\)" c)]
          (let [old-n (Long/parseLong n)]
            (when (< old-n new-end)
              (spit f (str/replace c (re-pattern (str "range\\(1, " old-n "\\)"))
                                     (str "range(1, " new-end ")")))
              (println "  " (fs/file-name f) "-> range(1," new-end ")")))))))
  (println "OK." (count-levels) "total levels."))

(defn verify []
  (println "Verifying all levels...")
  (let [{:keys [exit out]} (sh "gleam" "build")]
    (println out)
    (when (not= 0 exit) (println "BUILD FAILED") (System/exit 1)))
  (let [{:keys [exit out]} (sh "gleam" "run" "level70")]
    (println out)
    (when (not= 0 exit) (println "VERIFY FAILED") (System/exit 1)))
  (println "ALL" (count-levels) "LEVELS PASS."))

(defn help []
  (println "Usage: bb scripts/dogfood_loop.clj [--register | --verify]")
  (println "  --register  Update ranges in dogfood.gleam and gleamunison.gleam")
  (println "  --verify    Build, run level70, confirm all pass"))

(defn entry [& args]
  (cond
    (some #{"--register"} args) (register)
    (some #{"--verify"} args) (verify)
    (some #{"--help" "-h"} args) (help)
    :else (help)))

(apply entry *command-line-args*)
