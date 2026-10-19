#!/usr/bin/env bb
(ns test-cli-errors
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [clojure.string :as str]))

(def executable (str (fs/absolutize (or (first *command-line-args*) "gleamunison_escript"))))
(def work (str (fs/create-temp-dir {:prefix "gleamunison-cli-errors-"})))
(def failures (atom []))
(def sha256 (apply str (repeat 64 "a")))
(spit (str (fs/path work "valid.lisp")) "(define answer 42)\n")
(spit (str (fs/path work "invalid.lisp")) "(define broken\n")

(defn check! [args expected]
  (let [proc (apply p/process {:dir work :out :string :err :string :continue true
                              :extra-env {"GLEAMUNISON_EVIDENCE_SIGNING_KEY" ""}}
                    executable args)
        result (deref proc 10000 ::timeout)]
    (if (= result ::timeout)
      (do (p/destroy-tree proc) (swap! failures conj {:args args :reason :timeout}))
      (let [{:keys [exit out err]} result
            ok (if (= expected :success) (zero? exit) (= 1 exit))
            clean (not (re-find #"badarg|Internal error|exception error|init terminating" (str out err)))]
        (println (pr-str {:args args :exit exit :expected expected :clean clean}))
        (when-not (and ok clean)
          (swap! failures conj {:args args :exit exit :out out :err err}))))))

(doseq [args [["mcp" "--bad"] ["mcp" "0"] ["fmt"] ["fmt" "missing.lisp"]
              ["fmt" "invalid.lisp"] ["replay"] ["replay" "missing.lisp" "x" "missing.json"]
              ["evidence"] ["evidence" "attest" sha256 "io"] ["find"]
              ["find" "x" "--load" "missing.lisp"] ["find" "x" "--limit" "-1"]
              ["llm"] ["llm" "wrong" "prompt"] ["sync"] ["sync" "bad:abc"]
              ["pkg" "nonsense"] ["pkg" "install" "nope"] ["pkg" "install" sha256]
              ["pkg" "publish"] ["datalog"] ["watch"] ["publish"]]]
  (check! args :failure))
(doseq [args [["--help"] ["version"] ["verify" "valid.lisp"] ["fmt" "valid.lisp"]
              ["find" "nothing-matches-this"] ["evidence" sha256]]]
  (check! args :success))
(println (str "CLI error contract: " (count @failures) " failures; workspace: " work))
(when (seq @failures)
  (doseq [failure @failures] (binding [*out* *err*] (prn failure)))
  (System/exit 1))
