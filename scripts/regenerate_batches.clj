#!/usr/bin/env bb
;; Regenerate all auto-generated v*.gleam files with the v2 generator.
;; Extracts batch number and start level from the file header.

(require '[clojure.string :as str])

(let [files (sort (filter #(re-find #"dogfood_v\d+\.gleam" (str %))
                         (.listFiles (java.io.File. "src"))))
      auto-gen (filter #(re-find #"AUTO-GENERATED" (slurp (str %))) files)]
  (println "Found" (count auto-gen) "auto-generated files to regenerate")
  (doseq [f auto-gen]
    (let [c (slurp (str f))
          [batch-str] (re-find #"BATCH (\d+)" c)
          batch (Long/parseLong (second (re-find #"BATCH (\d+)" c)))
          header (nth (re-find #"BATCH \d+ \((\d+)-" c) 1)
          start (Long/parseLong header)
          _ (println "  v" batch "(levels" start "-" (+ start 49) ")...")
          r (clojure.java.shell/sh
             "bb" "scripts/generate_levels.clj"
             "--batch" (str batch) "--start" (str start) "--count" "50"
             :dir "/Users/moe/Desktop/gleamunison_dogfood/gleamunison_repo")]
      (println "    " (str/trim (:out r)))))
  (println "Done. Run: bb scripts/dogfood_loop.clj --register")
  (println "Then: gleam build && gleam run level70 && gleam test"))
