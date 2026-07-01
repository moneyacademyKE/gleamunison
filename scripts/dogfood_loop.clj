#!/usr/bin/env bb
;; dogfood_loop.clj — Registration and verification helper.
;; Called via `bb dogfood-register` and `bb dogfood-verify`.
;; Registration works by rebuilding meta from v*.gleam files.

(require '[clojure.string :as str])
(require '[babashka.fs :as fs])

(def repo (str (fs/parent (fs/parent *file*))))

(defn sh [& args]
  (let [pb (doto (java.lang.ProcessBuilder. (into-array String (cons "/bin/sh" (cons "-c" [(str/join " " args)]))))
             (.directory (java.io.File. repo))
             (.redirectErrorStream true))
        p (.start pb)
        out (slurp (.getInputStream p))
        exit (.waitFor p)]
    {:exit exit :out (str/trim out)}))

(defn sorted-batches []
  (->> (fs/glob (str repo "/src") "dogfood_v*.gleam")
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

(defn count-levels []
  (->> (sorted-batches)
       (map (comp slurp second))
       (mapcat #(re-seq #"pub fn level(\d+)" %))
       (count)))

(defn register []
  (println "Registering levels...")
  (let [{:keys [exit out]} (sh "bb" (str repo "/scripts/rebuild_meta.clj"))]
    (println out)
    (when (not= 0 exit)
      (println "FAILED")
      (System/exit 1)))
  (let [[_ lvl] (latest-level)
        new-end (inc lvl)]
    (doseq [f [(str repo "/src/dogfood.gleam") (str repo "/src/gleamunison.gleam")]]
      (let [c (slurp f)]
        (when-let [[_ n] (re-find #"range\(1, (\d+)\)" c)]
          (let [old-n (Long/parseLong n)]
            (when (< old-n new-end)
              (spit f (str/replace c (re-pattern (str "range\\(1, " old-n "\\)"))
                                     (str "range(1, " new-end ")")))
              (println "  " (fs/file-name f) "-> range(1," new-end ")")))))))
  (println "OK." (count-levels) "total levels."))

(defn verify []
  (println "Verifying all levels...")
  (let [{:keys [exit out]} (sh "gleam" "build")]
    (println out)
    (when (not= 0 exit) (println "BUILD FAILED") (System/exit 1)))
  (let [{:keys [exit out]} (sh "gleam" "run" "level70")]
    (println out)
    (when (not= 0 exit) (println "VERIFY FAILED") (System/exit 1)))
  (println "ALL" (count-levels) "LEVELS PASS."))

(defn help []
  (println "Usage: bb scripts/dogfood_loop.clj [--register | --verify]")
  (println "  --register  Rebuild meta from v*.gleam files and update ranges")
  (println "  --verify    Build, run level70, confirm all pass"))

(defn entry [& args]
  (cond
    (some #{"--register"} args) (register)
    (some #{"--verify"} args) (verify)
    (some #{"--help" "-h"} args) (help)
    :else (help)))

(apply entry *command-line-args*)
