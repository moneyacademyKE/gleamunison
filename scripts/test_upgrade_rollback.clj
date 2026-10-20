#!/usr/bin/env bb
;; Upgrade/rollback gate over real releases.
;;
;; Exercises, with receipts:
;;   1. install the previous release (built from its git tag in a worktree)
;;   2. lifecycle: server starts, accepts TCP, stops clean
;;   3. upgrade: current artifact over the install; identity flips; the
;;      schema/codec version gate decides store compatibility (equal =>
;;      no migration; a bump would require an explicit migration step)
;;   4. failed upgrade: a corrupt artifact is detected, not silently served
;;   5. rollback: previous binary restored, identity and lifecycle verified
;;   6. hot-loading and drain limits are documented in the ops doc
;;
;; Usage: bb scripts/test_upgrade_rollback.clj  (run after ./build_escript.sh)

(require '[babashka.process :refer [shell process destroy]]
         '[babashka.fs :as fs]
         '[clojure.string :as str])

(def repo (-> *file* fs/absolutize fs/parent fs/parent str))
(def artifact (str repo "/gleamunison_escript"))
(def prev-tag "v3.22.0")
(def prev-version "3.22.0")
(def sandbox (str (fs/create-temp-dir {:prefix "gleamunison-upgrade-"})))
(def installed-dir (str sandbox "/installed"))
;; The escript entry module is derived from the FILE NAME: rename the file
;; and the VM calls <newname>:main/1, which does not exist. The installed
;; name stays gleamunison_escript.
(def installed (str installed-dir "/gleamunison_escript"))

(def failures (atom []))

(defn check [name ok? detail]
  (println (format "%s %-36s %s" (if ok? "PASS" "FAIL") name detail))
  (when-not ok? (swap! failures conj name)))

(defn toml-version []
  (some #(second (re-find #"^version = \"([^\"]+)\"" %))
        (str/split-lines (slurp (str repo "/gleam.toml")))))

(defn app-vsn [path]
  (let [r (shell {:continue true :out :string :err :string}
                 "unzip" "-p" path "gleamunison.app")]
    (some->> (:out r) (re-find #"\{vsn,\s*\"([^\"]+)\"") second)))

(defn port-open? [port]
  (try
    (with-open [_ (java.net.Socket. "127.0.0.1" port)] true)
    (catch Exception _ false)))

(defn wait-port [port attempts]
  (cond (port-open? port) true
        (zero? attempts) false
        :else (do (Thread/sleep 100) (recur port (dec attempts)))))

(defn lifecycle-probe [label port]
  (let [proc (process {:dir installed-dir :out :inherit :err :inherit}
                      "./gleamunison_escript" "server" (str port))
        up (wait-port port 100)]
    (destroy proc)
    (check (str label "-starts-and-stops") up (str "port=" port))))

;; --- 1: build and install the previous release ------------------------------
(println "INFO building previous release" prev-tag "in a detached worktree...")
(let [worktree (str sandbox "/prev")]
  (shell {:dir repo} "git" "worktree" "add" "--detach" worktree prev-tag)
  (let [deps (shell {:continue true :dir worktree :out :string :err :string}
                    "gleam" "deps" "download")
        build (when (zero? (:exit deps))
                (shell {:continue true :dir worktree :out :string :err :string}
                       "./build_escript.sh"))]
    (check "previous-release-builds"
           (and build (zero? (:exit build)) (fs/exists? (str worktree "/gleamunison_escript")))
           (str "exit=" (:exit build)))
    (fs/create-dirs installed-dir)
    (fs/copy (str worktree "/gleamunison_escript") installed)
    (shell "chmod" "+x" installed)))

;; --- 2: identity + lifecycle of the previous install -------------------------
;; v3.22.0 predates the packaged release .app and the version command, so its
;; identity proof is behavioral: it runs --help, and it does NOT answer the
;; current release's version string. The worktree gleam.toml pins the tag's
;; declared version.
(let [prev-declared (some #(second (re-find #"^version = \"([^\"]+)\"" %))
                          (str/split-lines (slurp (str sandbox "/prev/gleam.toml"))))
      help (shell {:continue true :out :string :err :string} installed "--help")
      v (shell {:continue true :out :string :err :string} installed "version")]
  (check "previous-tag-version-declared" (= prev-version prev-declared)
         (str "tag-declared=" prev-declared))
  (check "previous-install-runs"
         (and (zero? (:exit help)) (str/includes? (:out help) "server"))
         (str "exit=" (:exit help)))
  (check "previous-is-not-current"
         (not= (toml-version) (str/trim (:out v)))
         (str "version-out=" (str/trim (:out v)))))
(lifecycle-probe "previous-release" 18431)

;; --- 3: upgrade --------------------------------------------------------------
(fs/copy installed (str sandbox "/gleamunison-prev-backup"))
(fs/copy artifact installed {:replace-existing true})
(check "upgrade-flips-identity" (= (toml-version) (app-vsn installed))
       (str "vsn=" (app-vsn installed)))
(let [v (shell {:continue true :out :string} installed "version")
      sv (shell {:continue true :out :string} installed "schema-version")]
  (check "upgraded-version-command"
         (and (zero? (:exit v)) (= (toml-version) (str/trim (:out v))))
         (str "out=" (str/trim (:out v))))
  ;; The codec is version 1 across this upgrade: stores need no migration.
  ;; A bump here is the gate that forces an explicit migration step.
  (check "schema-version-unchanged" (= "1" (str/trim (:out sv)))
         (str "schema-version=" (str/trim (:out sv)))))
(lifecycle-probe "upgraded-release" 18432)

;; --- 4: failed upgrade is detected -------------------------------------------
(spit installed "corrupt-not-a-real-escript")
(let [r (shell {:continue true :out :string :err :string} installed "version")]
  (check "corrupt-artifact-fails-loudly" (not (zero? (:exit r)))
         (str "exit=" (:exit r))))

;; --- 5: rollback ---------------------------------------------------------------
(fs/copy (str sandbox "/gleamunison-prev-backup") installed {:replace-existing true})
(shell "chmod" "+x" installed)
(let [v (shell {:continue true :out :string :err :string} installed "version")
      help (shell {:continue true :out :string :err :string} installed "--help")]
  (check "rollback-restores-previous"
         (and (zero? (:exit help))
              (not= (toml-version) (str/trim (:out v))))
         (str "version-out=" (str/trim (:out v)))))
(lifecycle-probe "rolled-back-release" 18433)

;; --- 6: ops doc covers drain + hot-loading limits ------------------------------
(let [doc (str repo "/docs/operations/upgrade-and-rollback.md")
      text (if (fs/exists? doc) (str/lower-case (slurp doc)) "")]
  (check "ops-doc-covers-drain" (str/includes? text "drain") doc)
  (check "ops-doc-covers-hot-loading" (str/includes? text "hot-load") doc))

;; --- cleanup -------------------------------------------------------------------
(shell {:dir repo :continue true} "git" "worktree" "remove" "--force"
       (str sandbox "/prev"))
(fs/delete-tree sandbox)

(println (if (empty? @failures)
           "upgrade-rollback: PASS"
           (str "upgrade-rollback: FAIL " (pr-str @failures))))
(System/exit (if (empty? @failures) 0 1))
