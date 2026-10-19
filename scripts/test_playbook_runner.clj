#!/usr/bin/env bb
(load-file "scripts/playbook_session.clj")
(require '[babashka.fs :as fs] '[babashka.process :as p])
(def work (str (fs/create-temp-dir {:prefix "playbook-process-test-"})))
(def bad (str (fs/path work "crash.sh")))
(spit bad "#!/bin/sh\necho 'Level 21: OK'\necho 'escript: Internal error: badarg code_server' >&2\nexit 7\n")
(fs/set-posix-file-permissions bad "rwx------")
(def slow (str (fs/path work "slow.sh")))
(spit slow "#!/bin/sh\nsleep 5\n")
(fs/set-posix-file-permissions slow "rwx------")
(with-redefs [playbook-session/executable (constantly bad)]
  (assert (= :fail (:status (playbook-session/host-level 21 1000)))))
(let [result @(p/process ["bb" "scripts/run_playbook_tests.clj" "21"]
                        {:out :string :err :string :continue true
                         :extra-env {"PLAYBOOK_EXECUTABLE" bad}})]
  (assert (= 1 (:exit result)))
  (println "injected code_server crash + OK marker => runner exit" (:exit result)))
(with-redefs [playbook-session/executable (constantly slow)]
  (assert (= :timeout (:status (playbook-session/host-level 21 30)))))
(load-file "scripts/playbook_policy.clj")
(let [cases [{:expr "(read_line)"}] result {:status :skipped :reason "manual"}
      policy {1 {:reason "manual" :source-sha256 (playbook-policy/fingerprint cases)}}]
  (assert (= :excluded (:status (playbook-policy/disposition policy 1 cases result))))
  (assert (= :fail (:status (playbook-policy/disposition policy 1 [] result))))
  (assert (= :skipped (:status (playbook-policy/disposition {} 1 cases result)))))
(println "nonzero child with OK marker + escript badarg: FAIL-CLOSED; timeout: FAIL-CLOSED; stale/unlisted exclusions: FAIL-CLOSED")
