#!/usr/bin/env bb
(ns test-cli-truth
  (:require [babashka.fs :as fs]
            [babashka.process :as process]
            [clojure.string :as str])
  (:import [java.nio.file Files]
           [java.security MessageDigest]))

;; Exercise the public process contract; never infer success from log text.
(def repo (str (fs/absolutize ".")))
(def executable
  (str (fs/absolutize (or (first *command-line-args*) "gleamunison_escript"))))
(def work (str (fs/create-temp-dir {:prefix "gleamunison-cli-truth-"})))
(def checks (atom 0))

(defn check! [label passed output]
  (when-not passed
    (throw (ex-info (str "FAIL: " label) {:output output :workspace work})))
  (swap! checks inc)
  (println (str "PASS: " label)))

;; This key is generated per run, belongs only to the disposable store,
;; and must never reuse the caller's production signing identity.
(def fixture-signing-key (str (java.util.UUID/randomUUID)))

(defn cli [& args]
  @(apply process/process {:dir work :out :string :err :string :continue true
                           :extra-env {"GLEAMUNISON_EVIDENCE_SIGNING_KEY" fixture-signing-key}}
          executable args))

(defn digest [path]
  (vec (.digest (MessageDigest/getInstance "SHA-256")
                (Files/readAllBytes (fs/path path)))))

(let [artifact (str (fs/path repo "gleamunison_escript"))
      original (when (fs/exists? artifact) (digest artifact))]
  (doseq [compiler ["/definitely/missing/gleam" "/usr/bin/false"]]
    (let [result @(process/process
                  {:dir repo :out :string :err :string :continue true
                   :extra-env {"GLEAM_BIN" compiler}}
                  "bash" "build_escript.sh")]
      (check! (str "failed compiler aborts build: " compiler)
              (not (zero? (:exit result))) result)
      (check! "failed build preserves the previous artifact"
              (= original (when (fs/exists? artifact) (digest artifact))) result))))

(doseq [[name content]
        {"empty.lisp" ""
         "comments.lisp" "; no program\n"
         "invalid.lisp" "(define answer\n"
         "no-tests.lisp" "(define answer 42)\n"
         "vacuous.lisp" "(define empty-answer 1)\n(define test_empty-answer 1)\n"
         "fail.lisp" "(define bad-answer 2)\n(define test_bad-answer (do Test expect 0))\n"
         "pass.lisp" "(define answer 42)\n(define test_answer (do Test expect (eq? answer 42)))\n"}]
  (spit (str (fs/path work name)) content))

(doseq [[command path needle]
        [["verify" "empty.lisp" "source contains no forms"]
         ["verify" "comments.lisp" "source contains no forms"]
         ["verify" "invalid.lisp" "Parse Error"]
         ["verify" "missing.lisp" "Failed to read"]
         ["test" "missing.lisp" "Failed to read"]
         ["test" "fail.lisp" "1 failed"]
         ["test" "vacuous.lisp" "no assertions"]
         ["test" "no-tests.lisp" "0 tests"]
         ["publish" "no-tests.lisp" "REFUSED"]]]
  (let [{:keys [exit out] :as result} (cli command path)]
    (check! (str command " " path " fails truthfully")
            (and (not (zero? exit)) (str/includes? out needle)) result)))

(let [result (cli "verify" "pass.lisp")]
  (check! "valid definitions verify" (zero? (:exit result)) result))

(let [{:keys [exit out] :as result} (cli "test" "pass.lisp")
      subject (second (re-find #"evidence: ([a-f0-9]{64})" out))]
  (check! "real assertion attaches evidence" (and (zero? exit) subject) result)
  (let [stored (cli "evidence" subject)]
    (check! "evidence survives process exit"
            (and (zero? (:exit stored))
                 (str/includes? (:out stored) "test  pass  test_answer: 1 passed, 0 failed")) stored))
  (let [published (cli "publish" "pass.lisp")]
    (check! "separate publish consumes persisted evidence"
            (and (zero? (:exit published))
                 (str/includes? (:out published) "2 definitions admitted")) published)))

(let [subject (apply str (repeat 64 "b"))
      attested (cli "evidence" "attest" subject "io" "subprocess regression")
      stored (cli "evidence" subject)]
  (check! "IO attestation is persisted before acknowledgement"
          (and (zero? (:exit attested))
               (str/includes? (:out stored) "subprocess regression"))
          {:attested attested :stored stored}))

(let [manifest (fs/path work ".gleamunison" "published")]
  (fs/move manifest (fs/path work "published-backup"))
  (fs/create-dir manifest)
  (let [blocked (cli "publish" "pass.lisp")]
    (check! "manifest write failure cannot report a successful publish"
            (and (not (zero? (:exit blocked)))
                 (str/includes? (:out blocked) "cannot write manifest")
                 (not (str/includes? (:out blocked) "published:"))) blocked)))

(println (str @checks " CLI truth checks passed; workspace: " work))
