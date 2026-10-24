#!/usr/bin/env bb
(ns test-ci-contract
  (:require [babashka.fs :as fs]
            [clojure.string :as str]))

(def root (str (fs/absolutize ".")))
(def test-workflow (slurp (str root "/.github/workflows/test.yml")))
(def publish-workflow (slurp (str root "/.github/workflows/publish.yml")))
(def failures (atom []))
(defn check [label value]
  (println (if value "PASS" "FAIL") label)
  (when-not value (swap! failures conj label)))

(check "test-workflow-diff-check-is-strict"
       (and (str/includes? test-workflow "git diff --check HEAD --")
            (not (str/includes? test-workflow "|| git diff --check"))))
(check "test-workflow-runs-lsp-stdio"
       (str/includes? test-workflow "scripts/test_lsp_stdio.clj"))
(doseq [command ["gleam test" "gleam format --check src test" "./build_escript.sh"
                "scripts/test_artifact.sh" "scripts/test_release_contract.clj"
                "scripts/run_playbook_tests.clj"]]
  (check (str "publish-runs-" command)
         (str/includes? publish-workflow command)))
(check "publish-is-last-side-effect"
       (< (.indexOf publish-workflow "scripts/run_playbook_tests.clj")
          (.indexOf publish-workflow "gleam publish --yes")))
(println "ci-contract:" (count @failures) "failures")
(when (seq @failures) (System/exit 1))
