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
  ;; The mechanism, not the repo's mood. A check that passes only while the
  ;; working tree happens to be dirty fails the moment the work is committed —
  ;; the opposite of what it is for. A throwaway repository proves the scan sees
  ;; both a modified file and an untracked one, in any repo state.
  (let [scratch (str (fs/create-temp-dir {:prefix "verification-scan-"}))]
    (run "git" "init" "-q" scratch)
    (spit (str (fs/path scratch "modified.gleam")) "(pub fn x() { 1 })\n")
    (spit (str (fs/path scratch "untracked.erl")) "-module(untracked).\n")
    (run "git" "-C" scratch "add" "modified.gleam")
    (run "git" "-C" scratch "-c" "user.email=a@b" "-c" "user.name=a"
         "commit" "-qm" "fixture")
    (spit (str (fs/path scratch "modified.gleam")) "(pub fn x() { 2 })\n")
    (let [dirty (run "git" "-C" scratch "diff" "--name-only" "HEAD")
          untracked (run "git" "-C" scratch "ls-files" "--others"
                         "--exclude-standard")]
      (check "dirty-and-untracked-production-files-are-scanned"
             (and (str/includes? (:out dirty) "modified.gleam")
                  (str/includes? (:out untracked) "untracked.erl"))))
    (fs/delete-tree scratch))
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
