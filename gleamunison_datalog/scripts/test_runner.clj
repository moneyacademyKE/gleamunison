(ns test-runner
  (:require [babashka.http-client :as http]
            [cheshire.core :as json]
            [clojure.string :as str])
  (:import [java.net URLEncoder]))

(defn url-encode [s]
  (URLEncoder/encode s "UTF-8"))

(defn eval-expr [expr]
  (let [url (str "http://localhost:8080/eval?expr=" (url-encode expr))]
    (try
      (let [resp (http/get url)]
        (if (= 200 (:status resp))
          (let [body (json/parse-string (:body resp) true)]
            (:result body))
          (str "HTTP Error: " (:body resp))))
      (catch Exception e
        (str "Connection failed: " (.getMessage e))))))

(defn run-test-suite [suite-name eval-fn]
  (println "\nRunning" suite-name "...")
  (let [result (eval-expr eval-fn)]
    (println "Result:" result)))

(defn -main []
  (println "=== Running GleamUnison Native Datalog Tests ===")
  ;; Ensure all test files are loaded first
  (require '[loader])
  (loader/-main "test/test_core.lisp" "test/test_query.lisp" "test/test_temporal.lisp" "test/test_graph.lisp")

  ;; Run the test functions defined in the files
  (run-test-suite "Core Tests" "(run-core-tests 0)")
  (run-test-suite "Query Tests" "(run-query-tests 0)")
  (run-test-suite "Temporal Tests" "(run-temporal-tests 0)")
  (run-test-suite "Graph Tests" "(run-graph-tests 0)"))

(when (= *file* (System/getProperty "babashka.file"))
  (-main))
