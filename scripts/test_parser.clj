#!/usr/bin/env bb
(ns test-parser
  (:require [babashka.fs :as fs]
            [clojure.string :as str]))

(defn parse-playbook [file]
  (let [content (slurp (str file))
        lines (str/split-lines content)
        levels (atom {})
        current-level (atom nil)
        in-code-block (atom false)
        code-block-lang (atom nil)
        current-code (atom [])
        current-expected (atom nil)]
    (doseq [line lines]
      (cond
        ;; Level header
        (str/starts-with? line "## Level ")
        (let [num (second (re-find #"## Level (\d+)" line))]
          (when num
            (reset! current-level (int (Integer/parseInt num)))
            (swap! levels assoc @current-level {:code-blocks [] :expected []})))

        ;; Code block start/end
        (str/starts-with? line "```")
        (if @in-code-block
          ;; End of code block
          (do
            (when (and @current-level (not-empty @current-code))
              (swap! levels update-in [@current-level :code-blocks] conj
                     {:lang @code-block-lang
                      :code (str/join "\n" @current-code)}))
            (reset! in-code-block false)
            (reset! code-block-lang nil)
            (reset! current-code []))
          ;; Start of code block
          (do
            (reset! in-code-block true)
            (reset! code-block-lang (str/replace line "```" ""))))

        ;; Content within code block
        @in-code-block
        (swap! current-code conj line)

        ;; Expected line
        (and @current-level (or (str/starts-with? line "Expected:") (str/starts-with? line "**Expected:**")))
        (let [exp (str/replace line #"^(Expected:|\*\*Expected:\*\*)\s*" "")]
          (swap! levels update-in [@current-level :expected] conj exp))))
    @levels))

(defn -main []
  (let [playbooks (sort (fs/glob "docs/playbook" "PLAYBOOK_DOGFOOD_*.md"))]
    (doseq [pb playbooks]
      (let [levels (parse-playbook pb)]
        (println (str (fs/file-name pb) ": parsed " (count levels) " levels"))
        (doseq [[num info] (sort (into [] levels))]
          (when (< (count (:code-blocks info)) 1)
            (println "  Level" num "has NO code blocks!")))))))

(-main)
