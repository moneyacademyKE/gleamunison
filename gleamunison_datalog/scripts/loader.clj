(ns loader
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [babashka.http-client :as http])
  (:import [java.net URLEncoder]))

(defn url-encode [s]
  (URLEncoder/encode s "UTF-8"))

(defn send-define [name expr]
  (let [url (str "http://localhost:8080/define?name=" (url-encode name) "&expr=" (url-encode expr))]
    (try
      (let [resp (http/get url)]
        (if (= 200 (:status resp))
          (println "Defined:" name)
          (println "Error defining" name ":" (:body resp))))
      (catch Exception e
        (println "Connection failed to define" name ":" (.getMessage e))))))

(defn send-eval [expr]
  (let [url (str "http://localhost:8080/eval?expr=" (url-encode expr))]
    (try
      (let [resp (http/get url)]
        (if (= 200 (:status resp))
          (println "Result:" (:body resp))
          (println "Error eval:" (:body resp))))
      (catch Exception e
        (println "Connection failed to eval:" (.getMessage e))))))

(defn load-file-defs [file-path]
  (println "Loading file:" file-path)
  (let [content (slurp file-path)
        ;; Simple parser to read S-expressions using Clojure's reader
        reader (clojure.lang.LineNumberingPushbackReader. (java.io.StringReader. content))
        eof (Object.)]
    (loop []
      (let [form (try
                   (read reader false eof)
                   (catch Exception e
                     (println "Reader error:" (.getMessage e))
                     eof))]
        (if-not (identical? form eof)
          (do
            (when (and (seq? form) (= 'define (first form)))
              (let [name (str (second form))
                    ;; Convert the rest of the form (the expr) back to an S-expression string
                    ;; We construct a string representation of the body
                    ;; Clojure printing handles lists with parentheses perfectly
                    expr-str (pr-str (nth form 2))]
                (send-define name expr-str)))
            (recur))
          (println "Finished loading" file-path))))))

(defn -main [& args]
  (if (or (empty? args) (some #{"--all" "-a"} args))
    (let [src-dir (io/file "src")
          files (sort (.listFiles src-dir))]
      (doseq [f files]
        (when (.endsWith (.getName f) ".lisp")
          (load-file-defs (.getAbsolutePath f)))))
    (doseq [f args]
      (load-file-defs f))))

(apply -main *command-line-args*)
