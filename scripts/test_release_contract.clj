#!/usr/bin/env bb
;; Release contract gate for the built escript artifact.
;;
;; The artifact must satisfy, with receipts:
;;   1. version command == gleam.toml version (metadata is derived, not literal)
;;   2. schema-version command prints the codec/schema integer
;;   3. the packaged gleamunison.app declares exactly the runtime dependency
;;      closure (gleam.toml [dependencies] + OTP base) — no dev-only apps
;;   4. every module the .app declares is present in the archive
;;   5. no test-only modules in the archive (cli_test excepted: it is the
;;      shipped `test` command)
;;   6. --help runs
;;   7. two clean builds of the same source are byte-identical (the declared
;;      reproducibility result)
;;
;; Usage: bb scripts/test_release_contract.clj   (run after ./build_escript.sh)

(require '[babashka.process :refer [shell]]
         '[babashka.fs :as fs]
         '[clojure.string :as str])

(def repo (-> *file* fs/absolutize fs/parent fs/parent str))
(def artifact (str repo "/gleamunison_escript"))

(def failures (atom []))

(defn check [name ok? detail]
  (println (format "%s %-36s %s" (if ok? "PASS" "FAIL") name detail))
  (when-not ok? (swap! failures conj name)))

(defn toml-field [field]
  (some #(second (re-find (re-pattern (str "^" field " = \"([^\"]+)\"")) %))
        (str/split-lines (slurp (str repo "/gleam.toml")))))

(defn toml-runtime-deps []
  (->> (str/split-lines (slurp (str repo "/gleam.toml")))
       (drop-while #(not= "[dependencies]" (str/trim %)))
       rest
       (take-while #(not (str/starts-with? (str/trim %) "[")))
       (keep #(second (re-find #"^([a-z0-9_]+)\s*=" %)))
       sort))

(defn run-artifact [& args]
  (apply shell {:continue true :out :string :err :string} artifact args))

(defn archive-listing []
  ;; unzip exits 1 over an escript preamble; that is expected, not a failure.
  (str/split-lines (:out (shell {:continue true :out :string :err :string}
                                "unzip" "-Z1" artifact))))

(defn app-term []
  (:out (shell {:continue true :out :string :err :string}
               "unzip" "-p" artifact "gleamunison.app")))

(defn app-block [term key]
  (some-> (re-find (re-pattern (str "\\{" key ",\\s*\\[([^\\]]*)\\]")) term)
          second))

(defn sha256 []
  (-> (shell {:out :string} "shasum" "-a" "256" artifact) :out
      (str/split #"\s+") first))

(defn clean-build! []
  (fs/delete-tree (str repo "/build"))
  (let [r (shell {:continue true :dir repo :out :string :err :string}
                 "./build_escript.sh")]
    (when-not (zero? (:exit r))
      (println (:out r)) (println (:err r))
      (throw (ex-info "clean build failed" {:exit (:exit r)})))))

;; --- 1/2: version + schema-version ----------------------------------------
(let [declared (toml-field "version")
      v (run-artifact "version")
      sv (run-artifact "schema-version")]
  (check "version-matches-gleam-toml"
         (and (zero? (:exit v)) (= declared (str/trim (:out v))))
         (str "declared=" declared " artifact=" (str/trim (:out v))))
  (check "schema-version-is-an-integer"
         (and (zero? (:exit sv)) (some? (parse-long (str/trim (:out sv)))))
         (str "schema-version=" (str/trim (:out sv)))))

;; --- 3/4/5: .app closure ----------------------------------------------------
(let [term (app-term)
      listing (set (archive-listing))
      vsn (some->> term (re-find #"\{vsn,\s*\"([^\"]+)\"") second)
      apps (some->> (app-block term "applications")
                    (re-seq #"([a-z0-9_]+)") (map second) sort)
      modules (some->> (app-block term "modules")
                       (re-seq #"\'([^\']+)\'") (map second))
      expected-apps (sort (concat ["kernel" "stdlib" "crypto"]
                                  (toml-runtime-deps)))
      missing (remove #(contains? listing (str % ".beam")) modules)
      test-beams (remove #(= "gleamunison@cli_test.beam" %)
                         (filter #(re-find #"(_test|_test_ffi)\.beam$|^gleeunit|^birdie" %)
                                 listing))]
  (check "app-vsn-matches" (= vsn (toml-field "version")) (str "vsn=" vsn))
  (check "app-applications-are-runtime-closure"
         (= apps expected-apps)
         (str "declared=" (pr-str apps)))
  (check "app-modules-all-present" (empty? missing)
         (str "declared-modules=" (count modules) " missing=" (count missing)))
  (check "no-test-modules-in-archive" (empty? test-beams)
         (str "offenders=" (pr-str test-beams))))

;; --- 6: help runs -----------------------------------------------------------
(let [h (run-artifact "--help")]
  (check "help-runs" (zero? (:exit h)) (str "exit=" (:exit h))))

;; --- 7: reproducibility over two clean builds --------------------------------
(println "INFO two clean builds (this is the slow part)...")
(clean-build!)
(let [first-hash (sha256)]
  (clean-build!)
  (let [second-hash (sha256)]
    (check "clean-builds-byte-identical" (= first-hash second-hash)
           (str "sha256=" second-hash))))

(println (if (empty? @failures)
           "release-contract: PASS"
           (str "release-contract: FAIL " (pr-str @failures))))
(System/exit (if (empty? @failures) 0 1))
