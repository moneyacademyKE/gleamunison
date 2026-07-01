#!/usr/bin/env bb
;; loop_infinite.clj — Infinite dogfooding loop.
;; Computes next batch, spawns cmd, waits for exit, repeats.

(require '[clojure.string :as str])
(require '[babashka.fs :as fs])
(require '[babashka.process :as proc])

(def repo-dir (str (fs/parent (fs/parent *file*))))

(defn sorted-batches []
  (->> (fs/glob (str repo-dir "/src") "dogfood_v*.gleam")
       (map (fn [f] [(Long/parseLong (re-find #"\d+" (str f))) (str f)]))
       (sort-by first)))

(defn latest-level []
  (let [batches (sorted-batches)
        [bn f] (last batches)
        c (slurp f)]
    (if (re-find #"(?i)placeholder" c)
      (let [[pbn pf] (last (butlast batches))
            nums (->> (re-seq #"level(\d+)" (slurp pf))
                      (map (comp #(Long/parseLong %) second))
                      (filter #(> % 1000))
                      (sort))]
        [pbn (last nums)])
      (let [nums (->> (re-seq #"level(\d+)" c)
                      (map (comp #(Long/parseLong %) second))
                      (filter #(> % 1000))
                      (sort))]
        [bn (last nums)]))))

(defn run-cmd [prompt]
  (println "  spawning cmd...")
  (proc/shell {:dir repo-dir :continue true}
              "cmd" "-p" prompt "--yolo" "--skip-onboarding" "--max-turns" "40")
  (println "  cmd exited"))

(println "=== INFINITE DOGFOOD LOOP ===")
(println "PID:" (.pid (java.lang.ProcessHandle/current)))
(println "Cwd:" repo-dir)
(println "Press Ctrl+C to stop.")
(println)

(loop [n 0]
  (let [result
        (try
          (let [[batch latest] (latest-level)
                next-batch (inc batch)
                start (inc latest)
                end (+ start 49)
                cmd1 (str "bb scripts/generate_levels.clj --batch " next-batch " --start " start)
                cmd2 "bb scripts/dogfood_loop.clj --register"
                cmd3 "gleam build"
                cmd4 (str "for lvl in $(seq " start " " end "); do gleam run $lvl 2>/dev/null | tail -1; done")
                cmd5 "gleam test"
                cmd6 (str "Update docs/ARCHITECTURE.md dogfood badge to " end)
                prompt (str "DOGFOOD BATCH " next-batch " (" start "-" end ")\n"
                            "Run each command in order. Exit when done.\n"
                            "1: " cmd1 "\n2: " cmd2 "\n3: " cmd3 "\n4: " cmd4 "\n5: " cmd5 "\n6: " cmd6)]
            (println "--- Iteration" n "(batch" next-batch "levels" start "-" end ") ---")
            (println "Time:" (str (java.time.LocalDateTime/now)))
            (println prompt)
            (let [exit (run-cmd prompt)]
              (println "Batch" next-batch "exit:" exit)
              (Thread/sleep 2000))
            :ok)
          (catch InterruptedException _
            (println "\nStopped.")
            :stop)
          (catch Exception e
            (println "ERROR:" (.getMessage e))
            (Thread/sleep 5000)
            :error))]
    (when (= result :ok)
      (recur (inc n)))))
