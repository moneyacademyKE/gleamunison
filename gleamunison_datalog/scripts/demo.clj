(ns demo
  (:require [babashka.http-client :as http]
            [cheshire.core :as json]
            [clojure.string :as str])
  (:import [java.net URLEncoder]))

(defn url-encode [s]
  (URLEncoder/encode s "UTF-8"))

(defn eval-expr [expr]
  (let [url (str "http://localhost:8080/eval?expr=" (url-encode expr))
        resp (http/get url)]
    (if (= 200 (:status resp))
      (let [body (json/parse-string (:body resp) true)]
        (:result body))
      (str "HTTP Error: " (:body resp)))))

(defn -main []
  (println "=== Datalog DB Interactive Demo ===")
  
  (println "\n1. Creating database...")
  (println "Code:" "(define db1 (db-assert db-empty 1 \"name\" \"Alice\"))")
  (eval-expr "(define db1 (db-assert db-empty 1 \"name\" \"Alice\"))")
  
  (println "\n2. Adding Bob and relationships...")
  (eval-expr "(define db2 (db-assert db1 2 \"name\" \"Bob\"))")
  (eval-expr "(define db3 (db-assert db2 1 \"friend\" 2))")
  
  (println "\n3. Performing query (Find friends of Alice)...")
  (let [query-expr "(db-query db3 (list (pair (q-val 1) (pair \"friend\" (q-var \"?friend\"))) (pair (q-var \"?friend\") (pair \"name\" (q-var \"?name\")))))"]
    (println "Query:" query-expr)
    (println "Result:" (eval-expr query-expr)))

  (println "\n4. Pull API (Pull Alice's attributes)...")
  (let [pull-expr "(db-pull db3 1 (list \"wildcard\"))"]
    (println "Pull:" pull-expr)
    (println "Result:" (eval-expr pull-expr)))

  (println "\n5. Graph Algorithm (Shortest path)...")
  ;; 1 -> friend -> 2 -> friend -> 3
  (eval-expr "(define db4 (db-assert db3 2 \"friend\" 3))")
  (let [path-expr "(graph-shortest-path db4 1 3 \"friend\")"]
    (println "Shortest Path (1 to 3):" path-expr)
    (println "Result:" (eval-expr path-expr)))

  (println "\n6. Cosine Similarity...")
  (let [vec-expr "(vector-cosine-similarity (list 1 2 3) (list 2 4 6))"]
    (println "Similarity between [1 2 3] and [2 4 6]:" vec-expr)
    (println "Result:" (eval-expr vec-expr))))

(when (= *file* (System/getProperty "babashka.file"))
  (-main))
