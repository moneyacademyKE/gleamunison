#!/usr/bin/env bb
(ns test-lsp-stdio
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [cheshire.core :as json]
            [clojure.string :as str]))

(def root (str (fs/absolutize ".")))
(def code-paths (mapv str (fs/glob (str root "/build/dev/erlang") "*/ebin")))
(def failures (atom []))
(defn bytes [text] (.getBytes ^String text "UTF-8"))
(defn frame [body] (str "Content-Length: " (alength (bytes body)) "\r\n\r\n" body))
(defn message [value] (json/generate-string value))
(defn frames [output]
  (loop [input (bytes output) result []]
    (if (zero? (alength input)) result
        (let [text (String. input "UTF-8")
              separator (.indexOf text "\r\n\r\n")]
          (assert (>= separator 0) "missing frame separator")
          (let [header (subs text 0 separator)
                length (parse-long (second (re-find #"Content-Length: ([0-9]+)" header)))
                start (+ 4 (alength (bytes header)))
                end (+ start length)]
            (assert (<= end (alength input)) "short frame")
            (recur (java.util.Arrays/copyOfRange input end (alength input))
                   (conj result (json/parse-string (String. input start length "UTF-8") true))))))))

(defn run! [label input verify]
  (let [proc (p/process (into ["erl" "-noshell" "-pa"]
                               (concat code-paths ["-eval" "gleamunison@cli_lsp:command([]), halt()."]))
                        {:in input :out :string :err :string :continue true})
        result (deref proc 10000 ::timeout)]
    (if (= result ::timeout)
      (do (p/destroy-tree proc) (swap! failures conj [label :timeout]))
      (try
        (assert (zero? (:exit result)) (str "exit=" (:exit result) " " (:err result)))
        (verify (:out result))
        (println label "PASS")
        (catch Throwable error
          (swap! failures conj [label (.getMessage error)]))))))

(def initialize {:jsonrpc "2.0" :id "café🦀" :method "initialize" :params {}})
(def shutdown {:jsonrpc "2.0" :id "done" :method "shutdown"})
(def exit-note {:jsonrpc "2.0" :method "exit"})
(run! "Unicode concatenated stdio frames"
      (apply str (map #(frame (message %)) [initialize shutdown exit-note]))
      #(let [replies (frames %)]
         (assert (= ["café🦀" "done"] (mapv :id replies)) (str "Unicode or next frame corrupted: " (pr-str replies)))
         (assert (get-in (first replies) [:result :capabilities]) "initialize missing")))
(doseq [[label input] [["negative length" "Content-Length: -1\r\n\r\nx"]
                       ["oversized body" "Content-Length: 1048577\r\n\r\n"]
                       ["duplicate length" "Content-Length: 1\r\nContent-Length: 1\r\n\r\nx"]
                       ["oversized header" (str "X: " (str/join (repeat 8193 "x")))]
                       ["short body" "Content-Length: 20\r\n\r\n{}"]]]
  (run! label input #(assert (empty? %) "malformed frame produced output")))
(doseq [failure @failures] (binding [*out* *err*] (prn failure)))
(println "LSP stdio:" (count @failures) "failures")
(when (seq @failures) (System/exit 1))
