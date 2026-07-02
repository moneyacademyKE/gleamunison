(ns watch-scratch
  (:require [babashka.fs :as fs]
            [babashka.process :refer [shell]]))

(defn run-verification []
  (println "\n📦 scratch.lisp changed — verifying...")
  (try
    (let [res (shell {:continue true} "gleam run -- verify scratch.lisp")]
      (if (zero? (:exit res))
        (println "✅ Verification succeeded")
        (println "❌ Verification failed")))
    (catch Exception e
      (println "❌ Execution failed:" (.getMessage e)))))

(defn -main []
  (let [path "scratch.lisp"]
    (when-not (fs/exists? path)
      (spit path ";; Write your S-expressions here\n(define x 42)\nx\n"))
    (println "👁  Watching scratch.lisp for changes...")
    (println "   Press Ctrl+C to stop.")
    (run-verification)
    (loop [last-mod (fs/last-modified-time path)]
      (Thread/sleep 500)
      (let [curr-mod (fs/last-modified-time path)]
        (if (not= curr-mod last-mod)
          (do
            (run-verification)
            (recur curr-mod))
          (recur last-mod))))))

(-main)
