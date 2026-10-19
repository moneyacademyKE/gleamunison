(ns playbook-policy
  (:require [clojure.edn :as edn]
            [clojure.string :as str])
  (:import [java.security MessageDigest]))

(defn fingerprint [cases]
  (str/join (map #(format "%02x" (bit-and 255 %))
                 (.digest (MessageDigest/getInstance "SHA-256")
                          (.getBytes (pr-str cases) "UTF-8")))))

(defn read-policy []
  (if (some #{"--strict"} *command-line-args*) {}
      (edn/read-string (slurp "scripts/playbook_exclusions.edn"))))

(defn disposition [policy level cases result]
  (if-let [entry (get policy level)]
    (if (and (= :skipped (:status result)) (= (:reason entry) (:reason result))
             (= (:source-sha256 entry) (fingerprint cases)))
      (assoc result :status :excluded :coverage "manual/not executable; not a passing test")
      {:status :fail :reason "stale playbook exclusion; source or behavior changed"})
    result))
