#!/usr/bin/env bb
(ns test-verification-contract
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [clojure.string :as str]))

(def root (str (fs/absolutize ".")))
(def failures (atom []))
(defn check [label value]
  (println (if value "PASS" "FAIL") label)
  (when-not value (swap! failures conj label)))
(defn run [& args]
  (apply p/shell {:dir root :out :string :err :string :continue true} args))
(defn changed-files []
  (let [result (run "git" "diff" "--name-only" "HEAD")
        untracked (run "git" "ls-files" "--others" "--exclude-standard")]
    (concat (str/split-lines (:out result))
            (str/split-lines (:out untracked)))))
(defn source-file? [path]
  (and (re-find #"\.(gleam|erl|clj|sh)$" path)
       (not (re-find #"(^|/)test/|_test\.(erl|gleam)$" path))))
(defn loc [path]
  (let [file (if (str/starts-with? path "/") path (str root "/" path))]
    (count (str/split-lines (slurp file)))))
(defn loc-over [paths]
  (filter #(and (fs/exists? (str root "/" %))
                (source-file? %)
                (> (loc %) 499)) paths))

(let [bad (str (fs/create-temp-file {:prefix "verification-contract-" :suffix ".txt"}))]
  (spit bad "x \n")
  (let [result (run "/usr/bin/git" "diff" "--no-index" "--check" "/dev/null" bad)]
    (check "whitespace-failure-is-not-masked" (not (zero? (:exit result)))))
  (fs/delete bad))

(let [tracked (changed-files)]
  (check "dirty-and-untracked-production-files-are-scanned"
         (and (some #(= % "scripts/verify_production_boundaries.clj") tracked)
              (some #(= % "scripts/test_verification_contract.clj") tracked)))
  (let [exact (str (fs/create-temp-file {:prefix "verification-exact-500-" :suffix ".clj"}))]
    (spit exact (str (str/join "\n" (repeat 500 "x")) "\n"))
    (check "exactly-500-is-refused" (> (loc exact) 499))
    (fs/delete exact))
  (check "all-current-production-files-under-500" (empty? (loc-over tracked))))

(let [workflow (slurp (str root "/.github/workflows/test.yml"))]
  (check "CI-diff-check-has-no-or-fallback" (not (str/includes? workflow "|| git diff --check")))
  (check "CI-runs-real-LSP-stdio-probe" (str/includes? workflow "test_lsp_stdio.clj")))

(println "verification-contract:" (count @failures) "failures")
(when (seq @failures) (System/exit 1))
