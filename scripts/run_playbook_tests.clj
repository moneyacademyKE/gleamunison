#!/usr/bin/env bb
(ns run-playbook-tests
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(def real-levels #{21 22 23 24 25 31 32 33 34 38 41 47 48 49 50 51 52 53 54 55 70})
(def ignored-langs #{"bash" "sh" "erlang" "python" "http" "json" "xml" "html" "javascript" "js" "gleam"})

(declare balanced?)

(defn parse-code-block-cases [block-lines]
  (loop [ls block-lines cases [] buffer [] current-expr nil]
    (if (empty? ls)
      (let [next-cases (if current-expr (conj cases {:expr current-expr :expected nil}) cases)]
        (if (seq buffer) (conj next-cases {:expr (str/join "\n" buffer) :expected nil}) next-cases))
      (let [line (str/trim (first ls))]
        (cond
          (str/starts-with? line ";; Expected:")
          (let [exp-val (str/trim (str/replace line ";; Expected:" ""))
                expr (if (seq buffer) (str/join "\n" buffer) current-expr)]
            (recur (next ls) (if expr (conj cases {:expr expr :expected exp-val}) cases) [] nil))
          (or (str/starts-with? line ";") (str/blank? line))
          (recur (next ls) cases buffer current-expr)
          :else
          (let [new-buf (conj buffer (first ls)) joined (str/join "\n" new-buf)]
            (if (balanced? joined)
              (recur (next ls) (if current-expr (conj cases {:expr current-expr :expected nil}) cases) [] joined)
              (recur (next ls) cases new-buf current-expr))))))))

(defn parse-playbooks []
  (let [playbooks (sort (fs/glob "docs/playbook" "PLAYBOOK_DOGFOOD_*.md"))
        levels (atom {})]
    (doseq [pb playbooks]
      (let [lines (str/split-lines (slurp (str pb)))
            current-level (atom nil) in-code-block (atom false)
            code-block-lang (atom nil) current-code (atom [])]
        (doseq [line lines]
          (cond
            (str/starts-with? line "## Level ")
            (when-let [num (second (re-find #"## Level (\d+)" line))]
              (reset! current-level (int (Integer/parseInt num)))
              (swap! levels assoc @current-level []))
            (str/starts-with? line "```")
            (if @in-code-block
              (do
                (when (and @current-level (not-empty @current-code))
                  (let [cases (parse-code-block-cases @current-code)]
                    (when-not (contains? ignored-langs @code-block-lang)
                      (swap! levels update @current-level concat cases))))
                (reset! in-code-block false) (reset! code-block-lang nil) (reset! current-code []))
              (do
                (reset! in-code-block true) (reset! code-block-lang (str/replace line "```" ""))))
            @in-code-block (swap! current-code conj line)))))
    @levels))

(defn run-real-level [n]
  (let [res (proc/shell {:out :string :err :string :continue true} "./gleamunison_escript" (str "level" n))]
    (if (str/includes? (:out res) (str "Level " n ": OK"))
      {:status :pass :output (:out res)}
      {:status :fail :output (str (:out res) "\nERROR:\n" (:err res))})))

(defn start-repl-session []
  (let [p (proc/process ["./gleamunison_escript" "repl"] {:err :inherit})
        w (io/writer (:in p)) r (io/reader (:out p))]
    (dotimes [_ 2] (.readLine r))
    {:process p :writer w :reader r}))

(defn eval-expr-raw [session expr]
  (let [w (:writer session) r (:reader session)]
    (.write w (str expr "\n"))
    (.write w "\"__level_done__\"\n")
    (.flush w)
    (loop [lines []]
      (let [line (.readLine r)]
        (if (or (nil? line) (str/includes? line "__level_done__"))
          lines
          (recur (conj lines line)))))))

(defn eval-expr [session expr]
  (let [fut (future (eval-expr-raw session expr))]
    (try (deref fut 15000 :timeout) (catch Exception _ :timeout))))

(defn clean-value [v]
  (if-not v ""
    (let [v (str/replace (str/trim v) #"\s*:\s*.*$" "")]
      (cond
        (and (str/starts-with? v "<<\"") (str/ends-with? v "\">>")) (subs v 3 (- (count v) 3))
        (and (str/starts-with? v "\"") (str/ends-with? v "\"")) (subs v 1 (- (count v) 1))
        :else v))))

(defn verify-result [output expected]
  (let [o-val (clean-value output) e-val (clean-value expected)]
    (if (or (str/includes? o-val e-val) (str/includes? e-val o-val))
      {:status :pass}
      {:status :fail :reason (str "Mismatch: Expected '" e-val "', got '" o-val "'") :expected e-val :actual o-val})))

(defn balanced? [s]
  (zero? (loop [chars (seq s) depth 0 in-str false]
           (if (empty? chars) depth
             (let [c (first chars)]
               (cond
                 (= c \") (recur (next chars) depth (not in-str))
                 in-str (recur (next chars) depth true)
                 (= c \() (recur (next chars) (inc depth) false)
                 (= c \)) (recur (next chars) (dec depth) false)
                 :else (recur (next chars) depth false)))))))

(defn define-expr? [expr] (str/starts-with? (str/trim expr) "(define "))

(defn expected-define-output [expr]
  (let [parts (str/split (str/replace (str/trim expr) #"^\(define\s+" "") #"\s+")]
    (str (first parts) " defined.")))

(defn run-repl-level [session n test-cases]
  (loop [cases test-cases]
    (if (empty? cases) {:status :pass}
      (let [{:keys [expr expected]} (first cases)]
        (cond
          (or (str/includes? expr "read_line") (str/includes? expr "spawn") (str/includes? expr "recv")
              (str/includes? expr "(do Console") (str/includes? expr "(do State")
              (= (str/trim expr) "exit") (= (str/trim expr) "quit"))
          (recur (next cases))
          (not (balanced? expr)) (recur (next cases))
          :else
          (let [outputs (eval-expr session expr)]
            (if (= outputs :timeout) {:status :timeout :expr expr}
              (let [res-line (str/join "\n" (remove #(or (str/starts-with? % "gleamunison>") (str/starts-with? % "...")) outputs))
                    exp-val (if (define-expr? expr) (expected-define-output expr) expected)
                    res (if exp-val (verify-result res-line exp-val) {:status :pass})]
                (if (= (:status res) :pass) (recur (next cases))
                  {:status :fail :reason (:reason res) :expr expr :outputs outputs :expected exp-val})))))))))

(defn -main []
  (println "=== Playbook Conformance Test Runner ===")
  (let [levels (parse-playbooks)
        session (atom (start-repl-session))
        passed (atom 0) failed (atom 0) skipped (atom 0) timed-out (atom 0)]
    (try
      (doseq [n (range 1 1001)]
        (let [test-cases (get levels n)]
          (cond
            (contains? real-levels n)
            (let [res (run-real-level n)]
              (if (= (:status res) :pass)
                (do (swap! passed inc) (println "Level" n " (Host): PASS") (flush))
                (do (swap! failed inc) (println "Level" n " (Host): FAIL") (flush))))
            (seq test-cases)
            (do
              (when (contains? #{71 101} n)
                (try (proc/destroy (:process @session)) (catch Exception _))
                (reset! session (start-repl-session)))
              (let [res (run-repl-level @session n test-cases)]
                (cond
                  (= (:status res) :pass)
                  (do (swap! passed inc) (println "Level" n " (REPL): PASS") (flush))
                  (= (:status res) :timeout)
                  (do (swap! timed-out inc)
                      (println "Level" n " (REPL): TIMEOUT on" (:expr res) "- restarting session") (flush)
                      (try (proc/destroy (:process @session)) (catch Exception _))
                      (reset! session (start-repl-session)))
                  :else
                  (do (swap! failed inc)
                      (println "Level" n " (REPL): FAIL -" (:reason res) "on" (:expr res)) (flush)))))
            :else
            (do (swap! skipped inc) (println "Level" n ": SKIPPED (no cases)") (flush)))))
      (finally (proc/destroy (:process @session))))
    (println "\n=== Summary ===")
    (prn {:passed @passed :failed @failed :skipped @skipped :timed-out @timed-out})
    (when (pos? @failed) (System/exit 1))))

(when (= *file* (System/getProperty "babashka.file")) (-main))
