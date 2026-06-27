#!/usr/bin/env bb
(ns refactor-playbooks
  (:require [babashka.fs :as fs]
            [clojure.string :as str]))

(defn clean-expected-part [s]
  (-> s
      (str/replace #"^(Expected:|\*\*Expected:\*\*)\s*" "")
      (str/replace #"\.$" "")
      str/trim))

(defn parse-expected-list [s]
  (let [cleaned (clean-expected-part s)]
    (if (or (str/includes? cleaned "Typecheck or runtime")
            (str/includes? cleaned "Interaction with stdin")
            (str/includes? cleaned "Parse Error:")
            (str/includes? cleaned "Typecheck Error:")
            (str/includes? cleaned "should return")
            (str/includes? cleaned "Some type error")
            (str/includes? cleaned "or runtime error"))
      ;; For descriptive text, don't treat as clean list of expected outputs
      []
      (->> (str/split cleaned #",\s*")
           (map #(str/replace % #"`" ""))
           (map str/trim)
           (remove str/blank?)))))

(defn refactor-file [file]
  (let [lines (str/split-lines (slurp (str file)))
        output (atom [])
        len (count lines)]
    (loop [i 0]
      (when (< i len)
        (let [line (nth lines i)]
          (if (str/starts-with? line "```")
            ;; Found code block
            (let [block-start i
                  block-lines (atom [])
                  ;; Find end of code block
                  end-idx (loop [j (inc i)]
                            (if (>= j len)
                              j
                              (let [l (nth lines j)]
                                (if (str/starts-with? l "```")
                                  j
                                  (do (swap! block-lines conj l)
                                      (recur (inc j)))))))
                  ;; Look for Expected: line after code block
                  expected-line-info (loop [k (inc end-idx)
                                            scanned 0]
                                       (if (or (>= k len) (> scanned 5))
                                         nil
                                         (let [l (nth lines k)]
                                           (if (or (str/starts-with? l "Expected:")
                                                   (str/starts-with? l "**Expected:**"))
                                             {:line l :idx k}
                                             (recur (inc k) (inc scanned))))))
                  exprs (->> @block-lines
                             (map str/trim)
                             (remove str/blank?)
                             (remove #(str/starts-with? % ";")))
                  expected-vals (if expected-line-info
                                  (parse-expected-list (:line expected-line-info))
                                  [])]
              ;; If we have clean expected values and count matches expressions
              (if (and (seq expected-vals) (= (count exprs) (count expected-vals)))
                (do
                  ;; Emit updated code block
                  (swap! output conj line)
                  (doseq [[expr exp] (map vector exprs expected-vals)]
                    (swap! output conj expr)
                    (swap! output conj (str ";; Expected: " exp)))
                  (swap! output conj "```")
                  (recur (inc end-idx)))
                (do
                  ;; Keep original block
                  (swap! output conj line)
                  (doseq [l @block-lines]
                    (swap! output conj l))
                  (swap! output conj "```")
                  (recur (inc end-idx)))))
            (do
              (swap! output conj line)
              (recur (inc i)))))))
    (spit (str file) (str (str/join "\n" @output) "\n"))))

(defn -main []
  (let [playbooks (sort (fs/glob "docs/playbook" "PLAYBOOK_DOGFOOD_*.md"))]
    (doseq [pb playbooks]
      (println "Refactoring" (fs/file-name pb))
      (refactor-file pb))
    (println "Done!")))

(-main)
