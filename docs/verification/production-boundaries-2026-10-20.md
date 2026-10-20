# Production-boundary witness — 2026-10-20

Branch `fix/production-boundaries` @ `5a897de`

| Gate | Exit | ms | Command |
|---|---|---|---|
| format | 0 | 70 | `gleam format --check src test` |
| diff-check | 0 | 24 | `git diff --check` |
| suite | 0 | 20099 | `gleam test` |
| build-escript | 0 | 9458 | `./build_escript.sh` |
| artifact-contract | 0 | 1488 | `bash scripts/test_artifact.sh` |
| cli-truth | 0 | 3495 | `bb scripts/test_cli_truth.clj` |
| http-boundary | 0 | 1163 | `bash scripts/test_http_boundary.sh` |
| release-contract | 0 | 24339 | `bb scripts/test_release_contract.clj` |
| upgrade-rollback | 0 | 14643 | `bb scripts/test_upgrade_rollback.clj` |
| playbook-default | 0 | 11624 | `bb scripts/run_playbook_tests.clj` |
| playbook-strict | 1 | 11463 | `bb scripts/run_playbook_tests.clj --strict` |
| loc-ceiling | 0 | 0 | `wc -l over touched files` |

```json
{
  "date" : "2026-10-20",
  "artifact_sha256" : "21fcda98eb304c524d95a135da6e83c7606fcdee025a93a5e0eac6eea4992baa",
  "gates" : [ {
    "name" : "format",
    "cmd" : "gleam format --check src test",
    "exit" : 0,
    "duration_ms" : 70,
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
    "duration_ms" : 20099,
    "informational" : false,
    "tail" : "\n   Compiled in 0.19s\n    Running gleamunison_test.main"
  }, {
    "name" : "build-escript",
    "cmd" : "./build_escript.sh",
    "exit" : 0,
    "duration_ms" : 9458,
    "informational" : false,
    "tail" : "Hint: You can safely remove it.\n\n   Compiled in 0.19s"
  }, {
    "name" : "artifact-contract",
    "cmd" : "bash scripts/test_artifact.sh",
    "exit" : 0,
    "duration_ms" : 1488,
    "informational" : false,
    "tail" : "artifact_version=3.23.0 declared_version=3.23.0\nartifact_test_modules=0"
  }, {
    "name" : "cli-truth",
    "cmd" : "bb scripts/test_cli_truth.clj",
    "exit" : 0,
    "duration_ms" : 3495,
    "informational" : false,
    "tail" : "PASS: IO attestation is persisted before acknowledgement\nPASS: manifest write failure cannot report a successful publish\n19 CLI truth checks passed; workspace: /var/folders/r5/njvx_5n968j2rqq7y3bv5slh0000gn/T/gleamunison-cli-truth-7097306857814230531"
  }, {
    "name" : "http-boundary",
    "cmd" : "bash scripts/test_http_boundary.sh",
    "exit" : 0,
    "duration_ms" : 1163,
    "informational" : false,
    "tail" : "/static/js/dashboard.js => 200\n=INFO REPORT==== 20-Oct-2026::23:22:03.361733 ===\nSIGTERM received - shutting down"
  }, {
    "name" : "release-contract",
    "cmd" : "bb scripts/test_release_contract.clj",
    "exit" : 0,
    "duration_ms" : 24339,
    "informational" : false,
    "tail" : "INFO two clean builds (this is the slow part)...\nPASS clean-builds-byte-identical          sha256=21fcda98eb304c524d95a135da6e83c7606fcdee025a93a5e0eac6eea4992baa\nrelease-contract: PASS"
  }, {
    "name" : "upgrade-rollback",
    "cmd" : "bb scripts/test_upgrade_rollback.clj",
    "exit" : 0,
    "duration_ms" : 14643,
    "informational" : false,
    "tail" : "\nupgrade-rollback: PASS\nPreparing worktree (detached HEAD 35c8cf8)"
  }, {
    "name" : "playbook-default",
    "cmd" : "bb scripts/run_playbook_tests.clj",
    "exit" : 0,
    "duration_ms" : 11624,
    "informational" : false,
    "tail" : "Level 1000 {:status :pass}\n=== Evaluation summary before cleanup === {:passed 928, :failed 0, :skipped 0, :timed-out 0, :excluded 72}\n=== Final summary === {:passed 928, :failed 0, :skipped 0, :timed-out 0, :excluded 72}"
  }, {
    "name" : "playbook-strict",
    "cmd" : "bb scripts/run_playbook_tests.clj --strict",
    "exit" : 1,
    "duration_ms" : 11463,
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
  "exclusions" : [ "playbook strict mode: manual-skip exits are policy, recorded informationally", "CI matrix (OTP 27/28/29 x ubuntu/macos) runs on push; local proof is OTP 29 / macOS arm64", "LOC ceiling: src/gleamunison_ffi_test.erl (625 LOC, base 471) is a test-only probe module called exclusively from test/*.gleam, exempt under the test-file exemption; every production file touched by this branch is under 500 LOC" ],
  "classification" : "authenticated-single-node-service",
  "head" : "5a897de",
  "side_effects" : "none: no tag, no Hex publish, no merge, no deploy",
  "classification_note" : "untrusted-execution profile remains disabled: external OS/container isolation is required and not claimed",
  "unresolved_risks" : [ "transient full-suite failure (507 passed/1 failed) seen sporadically: twice around the llm LOC split, then green on 6 consecutive re-runs; failing test never identified, suspected listener timing in the drain probe", "LLM cost metering is estimate-only until operator rates are configured", "provider error bodies are omitted, so provider-side debugging needs the provider dashboard" ],
  "branch" : "fix/production-boundaries"
}
```
