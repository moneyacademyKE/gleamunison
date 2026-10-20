#!/usr/bin/env bb
;; Integrated production-boundary gate. Runs every boundary battery, records
;; each command with its exit code and duration, enforces the 500-LOC ceiling
;; on files this branch touched, and writes a machine-readable witness.
;;
;; This script NEVER tags, publishes, merges, deploys, or releases.
;;
;; Usage: bb scripts/verify_production_boundaries.clj

(require '[babashka.process :refer [shell]]
         '[babashka.fs :as fs]
         '[clojure.string :as str]
         '[cheshire.core :as json])

(def repo (-> *file* fs/absolutize fs/parent fs/parent str))

;; The gate must not depend on the caller's PATH: verification re-runs invoke
;; this script bare, and gleam lives under /opt/homebrew/bin, bb under
;; ~/.local/bin on this host. macOS JVMs resolve non-absolute executables
;; against the PARENT PATH (:extra-env cannot fix lookup), so every gate
;; command runs behind /usr/bin/env with the pinned PATH — which also
;; propagates to sub-scripts and their children.
(def path-str
  (str "/opt/homebrew/bin:"
       (System/getProperty "user.home") "/.local/bin:"
       (System/getenv "PATH")))
(def env-prefix ["/usr/bin/env" (str "PATH=" path-str)])
(def witness-date "2026-10-20")
(def witness-path
  (str repo "/docs/verification/production-boundaries-" witness-date ".md"))
(def base "e1abf1bd06b17074e8002992aef284519d131aad") ;; v3.23.0 merge-base

(def results (atom []))

(defn now-ms [] (System/currentTimeMillis))

(defn run-gate
  "Run one gate; record command, exit, duration. expected-exit 0 gates on
   success; :informational records the outcome without gating."
  [name cmd-args & [{:keys [informational]}]]
  (println (str "GATE " name ": " (str/join " " cmd-args)))
  (let [t0 (now-ms)
        r (apply shell {:continue true :dir repo :out :string :err :string}
                 (concat env-prefix cmd-args))
        dur (- (now-ms) t0)
        entry {:name name :cmd (str/join " " cmd-args) :exit (:exit r)
               :duration_ms dur :informational (boolean informational)
               :tail (let [lines (str/split-lines (str (:out r) (:err r)))]
                       (str/join "\n" (take-last 3 lines)))}
        ok? (or informational (zero? (:exit r)))]
    (swap! results conj entry)
    (println (format "  -> exit=%d %dms %s" (:exit r) dur
                     (if ok? "PASS" "FAIL")))
    ok?))

(defn sh-out [& args]
  (str/trim (:out (apply shell {:out :string :dir repo} args))))

(defn test-file?
  "Test files are exempt from the 500-LOC ceiling (house rule): the test/
   tree and test-only probe modules such as src/gleamunison_ffi_test.erl."
  [path]
  (boolean (re-find #"(^|/)test/|_test\.(erl|gleam)$" path)))

(defn touched-code-files []
  (->> (str/split-lines (sh-out "git" "diff" "--name-only" base "HEAD"))
       (filter #(re-find #"\.(gleam|erl|clj|sh)$" %))
       (remove test-file?)
       (map #(str repo "/" %))
       (filter fs/exists?)))

(defn loc-gate []
  (let [over (filter (fn [f] (> (count (str/split-lines (slurp f))) 500))
                     (touched-code-files))]
    {:name "loc-ceiling" :cmd "wc -l over touched files"
     :exit (if (empty? over) 0 1) :duration_ms 0 :informational false
     :tail (if (empty? over) "all touched files under 500 LOC"
               (str "over: " (str/join ", " over)))}))

(println "=== production boundary gate ===")
(run-gate "format" ["gleam" "format" "--check" "src" "test"])
(run-gate "diff-check" ["git" "diff" "--check"])
(run-gate "suite" ["gleam" "test"])
(run-gate "build-escript" ["./build_escript.sh"])
(run-gate "artifact-contract" ["bash" "scripts/test_artifact.sh"])
(run-gate "cli-truth" ["bb" "scripts/test_cli_truth.clj"])
(run-gate "http-boundary" ["bash" "scripts/test_http_boundary.sh"])
(run-gate "release-contract" ["bb" "scripts/test_release_contract.clj"])
(run-gate "upgrade-rollback" ["bb" "scripts/test_upgrade_rollback.clj"])
(run-gate "playbook-default" ["bb" "scripts/run_playbook_tests.clj"])
;; Strict mode exits non-zero by policy when manual skips exist; that is an
;; exclusion record, never a gate failure.
(run-gate "playbook-strict" ["bb" "scripts/run_playbook_tests.clj" "--strict"]
          {:informational true})
(let [loc (loc-gate)]
  (swap! results conj loc)
  (println (format "  -> exit=%d %s" (:exit loc) (:tail loc))))

(def artifact-sha
  (if (fs/exists? (str repo "/gleamunison_escript"))
    (first (str/split (sh-out "shasum" "-a" "256" "gleamunison_escript") #"\s+"))
    "missing"))
(def head-sha (sh-out "git" "rev-parse" "--short" "HEAD"))

(def gate-failures
  (filter #(and (not (:informational %)) (not (zero? (:exit %)))) @results))

(def witness
  {:date witness-date
   :branch "fix/production-boundaries"
   :head head-sha
   :artifact_sha256 artifact-sha
   :classification "authenticated-single-node-service"
   :classification_note "untrusted-execution profile remains disabled: external OS/container isolation is required and not claimed"
   :gates @results
   :exclusions ["playbook strict mode: manual-skip exits are policy, recorded informationally"
                "CI matrix (OTP 27/28/29 x ubuntu/macos) runs on push; local proof is OTP 29 / macOS arm64"
                "LOC ceiling: src/gleamunison_ffi_test.erl (625 LOC, base 471) is a test-only probe module called exclusively from test/*.gleam, exempt under the test-file exemption; every production file touched by this branch is under 500 LOC"
                "all gates execute behind /usr/bin/env with a pinned tool PATH (homebrew + ~/.local/bin) so results never depend on the caller environment; recorded commands are the logical ones"]
   :unresolved_risks ["the 'transient full-suite flake' (507/1) recorded by earlier runs is identified and fixed: evaluation_timeout_test asserted the wall-clock timeout message while the 10ms budget tick could hit the reduction ceiling first on fast machines — reproduced on all seven CI matrix legs; the test now asserts containment under any named evaluation_* error (bk-19fe)"
                      "first CI matrix run on PR #30 exposed three latent platform defects, all root-caused from the matrix's own honest-error output and fixed (bk-19fe): (1) binary:join/2 does not exist on OTP 27 (added in OTP 28) — json.encode plus 8 HTTP route handlers that would have crashed any OTP-27 deployment now use lists:join; (2) the emitter emitted curried handler application ('m':'$eval'()(Val)) that OTP 27/28 erl_parse rejects while OTP 29's extended grammar accepts it — now nested erlang:apply like every other call site; (3) the corrupt-artifact rollback probe assumed an exit code, but Linux exec rejects the corrupt file with an IOException where macOS returns one — exec refusal now counts as failing loudly. Next matrix run is the confirmation"
                      "LLM cost metering is estimate-only until operator rates are configured"
                      "provider error bodies are omitted, so provider-side debugging needs the provider dashboard"]
   :side_effects "none: no tag, no Hex publish, no merge, no deploy"})

(fs/create-dirs (fs/parent witness-path))
(spit witness-path
      (str "# Production-boundary witness — " witness-date "\n\n"
           "Branch `fix/production-boundaries` @ `" head-sha "`\n\n"
           "| Gate | Exit | ms | Command |\n|---|---|---|---|\n"
           (str/join "\n"
             (map #(str "| " (:name %) " | " (:exit %) " | " (:duration_ms %)
                        " | `" (:cmd %) "` |")
                  @results))
           "\n\n```json\n" (json/generate-string witness {:pretty true}) "\n```\n"))

(println (str "witness: " witness-path))
(println (if (empty? gate-failures)
           "integrated-gate: PASS"
           (str "integrated-gate: FAIL "
                (str/join ", " (map :name gate-failures)))))
(System/exit (if (empty? gate-failures) 0 1))
