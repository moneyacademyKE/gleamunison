#!/usr/bin/env bb
;; loop_infinite.clj v2 — Infinite dogfooding loop.
;; Zombie cleanup, concise prompt, retry detection, error exit.
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

(defn kill-stale-cmds! []
  (try
    (let [pb (java.lang.ProcessBuilder. (into-array String ["pkill" "-f" "cmd -p"]))]
      (.waitFor (.start pb)))
    (catch Exception _)))

(defn run-cmd [prompt]
  (println "  spawning cmd...")
  (kill-stale-cmds!)
  (proc/shell {:dir repo-dir :continue true}
              "cmd" "-p" prompt "--yolo" "--skip-onboarding" "--max-turns" "40")
  (println "  cmd exited"))

(println "=== INFINITE DOGFOOD LOOP v2 ===")
(println "PID:" (.pid (java.lang.ProcessHandle/current)))
(println "Cwd:" repo-dir)
(println "Features: zombie cleanup, retry detection (skip after 3 fails), error file")
(println "Press Ctrl+C to stop.")
(println)

(loop [n 0 last-batch nil same-batch-count 0]
  (let [result
        (try
          (let [[batch latest] (latest-level)
                next-batch (inc batch)
                start (inc latest)
                end (+ start 49)
                is-retry (= next-batch last-batch)
                cnt (if is-retry (inc same-batch-count) 0)]
            (if (>= cnt 3)
              (do (println "ERROR: batch" next-batch "failed 3 times. Skipping.")
                  (spit (str repo-dir "/batch_" next-batch "_failure.log")
                        (str "Batch " next-batch " failed after 3 attempts at "
                             (java.time.LocalDateTime/now) "\n"))
                  :fail)
              (let [prompt (str "DOGFOOD BATCH " next-batch " (" start "-" end ")\n"
                                "1) bb scripts/generate_levels.clj --batch " next-batch " --start " start " --count 50\n"
                                "2) bb scripts/dogfood_loop.clj --register\n"
                                "3) gleam build && gleam run level70 && gleam test\n"
                                "4) Update docs/ARCHITECTURE.md dogfood badge to " end "\n"
                                "Exit when done.")]
                (println "--- Iteration" n "(batch" next-batch "levels" start "-" end
                         (if is-retry (str " RETRY#" cnt) "") ") ---")
                (println "Time:" (str (java.time.LocalDateTime/now)))
                (println prompt)
                (let [exit (run-cmd prompt)]
                  (println "Batch" next-batch "exit:" exit)
                  (Thread/sleep 2000))
                :ok)))
          (catch InterruptedException _ :stop)
          (catch Exception e
            (println "ERROR:" (.getMessage e))
            (Thread/sleep 5000)
            :error))]
    (case result
      :ok (recur (inc n) (first (latest-level)) 0)
      :stop (do (println "Stopped.") (System/exit 0))
      :fail (do (println "Failed.") (System/exit 1))
      :error (recur n last-batch same-batch-count))))
