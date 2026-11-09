#!/usr/bin/env bb
(ns test-cli-errors
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [clojure.string :as str]))

;; The CLI's exit codes are a contract a script reads:
;;   0 success, 1 refused (understood and declined), 2 could-not-resolve (the
;;   request named something absent).
;;
;; Every case below declares the code it must produce, so drift in either
;; direction fails. `run` and `pkg` are the two commands that implement the
;; three-code contract; the rest refuse with 1, including where the honest
;; answer would be 2 — that gap is real and is recorded in the witness, not
;; papered over by a test that accepts any nonzero exit.

(def executable (str (fs/absolutize (or (first *command-line-args*) "gleamunison_escript"))))
(def work (str (fs/create-temp-dir {:prefix "gleamunison-cli-errors-"})))
(def failures (atom []))
(def sha256 (apply str (repeat 64 "a")))
(spit (str (fs/path work "valid.lisp")) "(define answer 42)\n")
(spit (str (fs/path work "invalid.lisp")) "(define broken\n")

(defn check!
  ([args expected-exit] (check! args expected-exit nil))
  ([args expected-exit expected-err]
   (let [proc (apply p/process {:dir work :out :string :err :string :continue true
                               :extra-env {"GLEAMUNISON_EVIDENCE_SIGNING_KEY" ""}}
                     executable args)
         result (deref proc 10000 ::timeout)]
     (if (= result ::timeout)
       (do (p/destroy-tree proc) (swap! failures conj {:args args :reason :timeout}))
       (let [{:keys [exit out err]} result
             ok (= exit expected-exit)
             bytes-match (or (nil? expected-err) (and (= expected-err err) (= "" out)))
             clean (not (re-find #"badarg|Internal error|exception error|init terminating" (str out err)))]
         (println (pr-str {:args args :exit exit :expected expected-exit
                          :clean clean :bytes-match bytes-match}))
         (when-not (and ok clean bytes-match)
           (swap! failures conj {:args args :exit exit :expected expected-exit
                                 :expected-err expected-err :out out :err err})))))))

;; Refusals: the command understood the request and declined it.
(doseq [args [["mcp" "--bad"] ["mcp" "0"] ["fmt"] ["fmt" "missing.lisp"]
              ["fmt" "invalid.lisp"] ["replay"] ["replay" "missing.lisp" "x" "missing.json"]
              ["evidence"] ["evidence" "attest" sha256 "io"] ["find"]
              ["find" "x" "--load" "missing.lisp"] ["find" "x" "--limit" "-1"]
              ["llm"] ["llm" "wrong" "prompt"] ["sync"] ["sync" "bad:abc"]
              ["pkg" "nonsense"] ["pkg" "publish"] ["datalog"] ["watch"] ["publish"]]]
  (check! args 1))

;; Could-not-resolve: the request named something absent or malformed. A
;; missing manifest is not a policy refusal — telling a caller to configure a
;; signing key for content the store does not hold was the bug this pins.
(doseq [args [["pkg" "install" "nope"]
              ["pkg" "install" sha256]
              ["run" "nope"]
              ["run" sha256]]]
  (check! args 2))

(doseq [args [["--help"] ["version"] ["verify" "valid.lisp"] ["fmt" "valid.lisp"]
              ["find" "nothing-matches-this"] ["evidence" sha256]]]
  (check! args 0))

;; The shared flag-error mapping must preserve complete stderr bytes, including
;; the command-specific usage and its final newline. Refusals leave stdout empty.
(doseq [[args usage]
        [[["unpublish"]
          (str "usage: gleam run -- unpublish <name> [--store path] [--branch name]\n\n"
               "Retracts a published name: its index line, its namespace binding, and\n"
               "its definition bytes. Refuses when another stored definition depends on\n"
               "it, or when another name still binds the same content.\n"
               "The branch defaults to main; --branch selects another namespace.")]
         [["purge"]
          (str "usage: gleam run -- purge <content-hash> [--yes] [--store path] [--branch name]\n\n"
               "Removes a definition and the stored dependencies nothing else uses.\n"
               "Dry run by default: prints the removal set and changes nothing until\n"
               "--yes. Refuses when something outside that set depends on the ref.\n"
               "The branch defaults to main; --branch selects another namespace.")]
         [["pkg" "install"]
          "usage: gleam run -- pkg install <manifest-hash> [--peer host:port] [--branch name]"]]
        [flag sentence] [["--store" "--store needs a path"]
                         ["--branch" "--branch needs a name"]]]
  (check! (conj args flag) 1 (str sentence "\n" usage "\n")))

(println (str "CLI error contract: " (count @failures) " failures; workspace: " work))
(when (seq @failures)
  (doseq [failure @failures] (binding [*out* *err*] (prn failure)))
  (System/exit 1))
