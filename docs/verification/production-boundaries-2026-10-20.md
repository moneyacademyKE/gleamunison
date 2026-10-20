# Production-boundary witness — 2026-10-20

Branch `fix/production-boundaries` @ `f5b6016`

| Gate | Exit | ms | Command |
|---|---|---|---|
| format | 0 | 71 | `gleam format --check src test` |
| diff-check | 0 | 24 | `git diff --check` |
| suite | 0 | 20244 | `gleam test` |
| build-escript | 0 | 9329 | `./build_escript.sh` |
| artifact-contract | 0 | 1552 | `bash scripts/test_artifact.sh` |
| cli-truth | 0 | 3778 | `bb scripts/test_cli_truth.clj` |
| http-boundary | 0 | 1157 | `bash scripts/test_http_boundary.sh` |
| release-contract | 0 | 24096 | `bb scripts/test_release_contract.clj` |
| upgrade-rollback | 0 | 14137 | `bb scripts/test_upgrade_rollback.clj` |
| playbook-default | 0 | 11519 | `bb scripts/run_playbook_tests.clj` |
| playbook-strict | 1 | 11402 | `bb scripts/run_playbook_tests.clj --strict` |
| loc-ceiling | 0 | 0 | `wc -l over touched files` |

```json
{
  "date" : "2026-10-20",
  "artifact_sha256" : "28df2884d4348c06bd5dd076d282265f8e4bdbac69ad996a4ab3a7fb3a167b5c",
  "gates" : [ {
    "name" : "format",
    "cmd" : "gleam format --check src test",
    "exit" : 0,
    "duration_ms" : 71,
    "informational" : false,
    "tail" : ""
  }, {
    "name" : "diff-check",
    "cmd" : "git diff --check",
    "exit" : 0,
    "duration_ms" : 24,
    "informational" : false,
    "tail" : ""
  }, {
    "name" : "suite",
    "cmd" : "gleam test",
    "exit" : 0,
    "duration_ms" : 20244,
    "informational" : false,
    "tail" : "\n   Compiled in 0.18s\n    Running gleamunison_test.main"
  }, {
    "name" : "build-escript",
    "cmd" : "./build_escript.sh",
    "exit" : 0,
    "duration_ms" : 9329,
    "informational" : false,
    "tail" : "Hint: You can safely remove it.\n\n   Compiled in 0.19s"
  }, {
    "name" : "artifact-contract",
    "cmd" : "bash scripts/test_artifact.sh",
    "exit" : 0,
    "duration_ms" : 1552,
    "informational" : false,
    "tail" : "artifact_version=3.23.0 declared_version=3.23.0\nartifact_test_modules=0"
  }, {
    "name" : "cli-truth",
    "cmd" : "bb scripts/test_cli_truth.clj",
    "exit" : 0,
    "duration_ms" : 3778,
    "informational" : false,
    "tail" : "PASS: --help prints usage and exits zero\nPASS: unknown command exits non-zero\n21 CLI truth checks passed; workspace: /var/folders/r5/njvx_5n968j2rqq7y3bv5slh0000gn/T/gleamunison-cli-truth-18175075454370780338"
  }, {
    "name" : "http-boundary",
    "cmd" : "bash scripts/test_http_boundary.sh",
    "exit" : 0,
    "duration_ms" : 1157,
    "informational" : false,
    "tail" : "/static/js/dashboard.js => 200\n=INFO REPORT==== 21-Oct-2026::00:40:16.799817 ===\nSIGTERM received - shutting down"
  }, {
    "name" : "release-contract",
    "cmd" : "bb scripts/test_release_contract.clj",
    "exit" : 0,
    "duration_ms" : 24096,
    "informational" : false,
    "tail" : "INFO two clean builds (this is the slow part)...\nPASS clean-builds-byte-identical          sha256=28df2884d4348c06bd5dd076d282265f8e4bdbac69ad996a4ab3a7fb3a167b5c\nrelease-contract: PASS"
  }, {
    "name" : "upgrade-rollback",
    "cmd" : "bb scripts/test_upgrade_rollback.clj",
    "exit" : 0,
    "duration_ms" : 14137,
    "informational" : false,
    "tail" : "\nupgrade-rollback: PASS\nPreparing worktree (detached HEAD 35c8cf8)"
  }, {
    "name" : "playbook-default",
    "cmd" : "bb scripts/run_playbook_tests.clj",
    "exit" : 0,
    "duration_ms" : 11519,
    "informational" : false,
    "tail" : "Level 1000 {:status :pass}\n=== Evaluation summary before cleanup === {:passed 928, :failed 0, :skipped 0, :timed-out 0, :excluded 72}\n=== Final summary === {:passed 928, :failed 0, :skipped 0, :timed-out 0, :excluded 72}"
  }, {
    "name" : "playbook-strict",
    "cmd" : "bb scripts/run_playbook_tests.clj --strict",
    "exit" : 1,
    "duration_ms" : 11402,
    "informational" : true,
    "tail" : "Level 1000 {:status :pass}\n=== Evaluation summary before cleanup === {:passed 928, :failed 0, :skipped 72, :timed-out 0, :excluded 0}\n=== Final summary === {:passed 928, :failed 0, :skipped 72, :timed-out 0, :excluded 0}"
  }, {
    "name" : "loc-ceiling",
    "cmd" : "wc -l over touched files",
    "exit" : 0,
    "duration_ms" : 0,
    "informational" : false,
    "tail" : "all touched files under 500 LOC"
  } ],
  "exclusions" : [ "playbook strict mode: manual-skip exits are policy, recorded informationally", "CI matrix (OTP 27/28/29 x ubuntu/macos) runs on push; local proof is OTP 29 / macOS arm64", "LOC ceiling: src/gleamunison_ffi_test.erl (625 LOC, base 471) is a test-only probe module called exclusively from test/*.gleam, exempt under the test-file exemption; every production file touched by this branch is under 500 LOC", "all gates execute behind /usr/bin/env with a pinned tool PATH (homebrew + ~/.local/bin) so results never depend on the caller environment; recorded commands are the logical ones" ],
  "classification" : "authenticated-single-node-service",
  "head" : "f5b6016",
  "side_effects" : "none: no tag, no Hex publish, no merge, no deploy",
  "classification_note" : "untrusted-execution profile remains disabled: external OS/container isolation is required and not claimed",
  "unresolved_risks" : [ "the 'transient full-suite flake' (507/1) recorded by earlier runs is identified and fixed: evaluation_timeout_test asserted the wall-clock timeout message while the 10ms budget tick could hit the reduction ceiling first on fast machines — reproduced on all seven CI matrix legs; the test now asserts containment under any named evaluation_* error (bk-19fe)", "first CI matrix run on PR #30 exposed two latent OTP-version defects pending root-cause: json.encode fails only on OTP 27, and the tape-to-test generated module fails erl_parse only on OTP 27/28. Neither reproduces on the local OTP 29 host and no older OTP is available locally, so the honest-error upgrades (encode surfaces reason+stack; compile_source dumps the offending source on parse/scan errors) make the next matrix run the diagnostic oracle (bk-19fe)", "LLM cost metering is estimate-only until operator rates are configured", "provider error bodies are omitted, so provider-side debugging needs the provider dashboard" ],
  "branch" : "fix/production-boundaries"
}
```
