(ns playbook-session
  (:require [babashka.process :as proc]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(defn executable [] (or (System/getenv "PLAYBOOK_EXECUTABLE") "./gleamunison_escript"))
(defn crash? [text]
  (boolean (re-find #"(?i)escript:|internal error|exception error|init terminating|crash dump" text)))

(defn host-level [n timeout-ms]
  (let [p (proc/process [(executable) (str "level" n)] {:out :string :err :string :continue true})
        result (deref p timeout-ms ::timeout)]
    (if (= result ::timeout)
      (do (proc/destroy-tree p) {:status :timeout :reason "host process timed out"})
      (let [{:keys [exit out err]} result]
        {:status (if (and (zero? exit) (not (crash? err))
                          (str/includes? out (str "Level " n ": OK"))) :pass :fail)
         :exit exit :output (str out "\n" err)}))))

(defn start []
  (let [p (proc/process [(executable) "repl"] {:err :string :continue true})
        reader (io/reader (:out p))
        startup (future [(.readLine reader) (.readLine reader)])]
    (if (= ::timeout (deref startup 5000 ::timeout))
      (do (proc/destroy-tree p) (future-cancel startup) (throw (ex-info "REPL startup timed out" {})))
      {:process p :writer (io/writer (:in p)) :reader reader})))

(defn evaluate [session expression]
  (let [marker (str "__playbook_done_" (java.util.UUID/randomUUID) "__")
        work (future
               (let [w (:writer session) r (:reader session)]
                 (.write w (str expression "\n\"" marker "\"\n"))
                 (.flush w)
                 (loop [lines []]
                   (let [line (.readLine r)]
                     (cond
                       (nil? line) {:status :fail :reason "REPL EOF before completion marker" :outputs lines}
                       (str/includes? line marker) {:status :ok :outputs lines}
                       :else (recur (conj lines line)))))))
        result (try (deref work 15000 ::timeout)
                    (catch Exception e {:status :fail :reason (ex-message e)}))]
    (if (= result ::timeout)
      (do (proc/destroy-tree (:process session)) (future-cancel work)
          {:status :timeout :reason "REPL expression timed out"})
      result)))

(defn stop [session]
  (let [p (:process session)]
    (try (.write (:writer session) "quit\n") (.flush (:writer session)) (.close (:writer session))
         (catch Exception _))
    (let [result (deref p 5000 ::timeout)]
      (if (= result ::timeout)
        (do (proc/destroy-tree p) {:status :fail :reason "REPL shutdown timed out"})
        (if (and (zero? (:exit result)) (not (crash? (:err result))))
          {:status :pass}
          {:status :fail :exit (:exit result) :reason (:err result)})))))
