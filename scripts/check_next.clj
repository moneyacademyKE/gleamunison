#!/usr/bin/env bb
;; check_next.clj — Check if a batch is ready to implement.
;;
;; Detects whether a skeleton file exists for a batch that hasn't been
;; registered yet. If yes, prints the batch info and exits 0 (continue).
;; If no, prints "waiting" and exits 0.
;;
;; This is the loop signal: after completing a batch + running
;; next_batch.sh, run this. If it says "READY", start the next batch.

(require '[babashka.fs :as fs])
(require '[clojure.string :as str])

(defn latest-dogfood-file []
  (->> (fs/glob "src" "dogfood_v*.gleam")
       (sort-by #(Long/parseLong (re-find #"\d+" (str %))))
       last))

(defn batch-of [f]
  (Long/parseLong (re-find #"\d+" (str f))))

(defn latest-level-in-meta []
  (when-let [content (slurp "src/dogfood_meta.gleam")]
    (->> (re-seq #"level(\d+)" content)
         (mapv (comp #(Long/parseLong %) second))
         (apply max))))

(defn is-skeleton? [f]
  (let [content (slurp (str f))]
    (or (str/includes? content "GENERATE")
        (str/includes? content "placeholder"))))

(defn has-meta-entry? [batch]
  (let [content (slurp "src/dogfood_meta.gleam")]
    (str/includes? content (str "v" batch ".level"))))

(let [latest (latest-dogfood-file)
      batch (some-> latest batch-of)
      ll (latest-level-in-meta)]
  (if (nil? latest)
    (println "WAITING: no dogfood files found")
    (if (has-meta-entry? batch)
      (do (println "DONE: batch" batch "is registered")
          (println "Next skeleton:" (when-let [n (some-> latest batch-of inc)]
                                     (str "src/dogfood_v" n ".gleam")))
          (println "Run: scripts/next_batch.sh to create it"))
      ;; Not registered yet — check if it's a skeleton waiting for implementation
      (if (is-skeleton? latest)
        (do (println "READY: batch" batch "skeleton ready for implementation")
            (println "Levels:" (inc ll) "-" (+ ll 49))
            (println "File: src/dogfood_v" batch ".gleam")
            (println "")
            (println "Next action: write 50 level functions in the file"))
        (do (println "IMPLEMENTED: batch" batch "written but not registered")
            (println "Levels:" (inc ll) "-" (+ ll 49))
            (println "Next action: bb dogfood-register"))))))
