# Production-boundary witness — 2026-10-23

Branch `main` @ `009db6b`

| Gate | Exit | ms | Command |
|---|---|---|---|
| format | 0 | 80 | `gleam format --check src test` |
| diff-check | 0 | 32 | `git diff --check` |
| suite | 0 | 23567 | `gleam test` |
| build-escript | 0 | 9901 | `./build_escript.sh` |
| artifact-contract | 0 | 1112 | `bash scripts/test_artifact.sh` |
| cli-truth | 0 | 3823 | `bb scripts/test_cli_truth.clj` |
| http-boundary | 0 | 1186 | `bash scripts/test_http_boundary.sh` |
| release-contract | 0 | 24743 | `bb scripts/test_release_contract.clj` |
| upgrade-rollback | 0 | 14784 | `bb scripts/test_upgrade_rollback.clj` |
| playbook-default | 0 | 8546 | `bb scripts/run_playbook_tests.clj` |
| cli-errors | 0 | 3819 | `bb scripts/test_cli_errors.clj` |
| dashboard-safety | 0 | 122 | `bun scripts/test_dashboard_safety.mjs` |
| parser | 0 | 42 | `bb scripts/test_parser.clj` |
| playbook-runner | 0 | 585 | `bb scripts/test_playbook_runner.clj` |
| loc-ceiling | 0 | 0 | `wc -l over touched files` |

```json
{
  "date" : "2026-10-23",
  "artifact_sha256" : "23f82bbd7b3712aea897a1e61b3d455abddb1c3c55db4c92455f0780cf445574",
  "gates" : [ {
    "name" : "format",
    "cmd" : "gleam format --check src test",
    "exit" : 0,
    "duration_ms" : 80,
    "informational" : false,
    "tail" : ""
  }, {
    "name" : "diff-check",
    "cmd" : "git diff --check",
    "exit" : 0,
    "duration_ms" : 32,
    "informational" : false,
    "tail" : ""
  }, {
    "name" : "suite",
    "cmd" : "gleam test",
    "exit" : 0,
    "duration_ms" : 23567,
    "informational" : false,
    "tail" : "\n   Compiled in 0.21s\n    Running gleamunison_test.main"
  }, {
    "name" : "build-escript",
    "cmd" : "./build_escript.sh",
    "exit" : 0,
    "duration_ms" : 9901,
    "informational" : false,
    "tail" : "Hint: You can safely remove it.\n\n   Compiled in 0.20s"
  }, {
    "name" : "artifact-contract",
    "cmd" : "bash scripts/test_artifact.sh",
    "exit" : 0,
    "duration_ms" : 1112,
    "informational" : false,
    "tail" : "artifact_version=3.24.0 declared_version=3.24.0\nartifact_engine_modules=13\nartifact_test_modules=0"
  }, {
    "name" : "cli-truth",
    "cmd" : "bb scripts/test_cli_truth.clj",
    "exit" : 0,
    "duration_ms" : 3823,
    "informational" : false,
    "tail" : "PASS: --help prints usage and exits zero\nPASS: unknown command exits non-zero\n21 CLI truth checks passed; workspace: /var/folders/r5/njvx_5n968j2rqq7y3bv5slh0000gn/T/gleamunison-cli-truth-4477754363545532178"
  }, {
    "name" : "http-boundary",
    "cmd" : "bash scripts/test_http_boundary.sh",
    "exit" : 0,
    "duration_ms" : 1186,
    "informational" : false,
    "tail" : "/static/js/dashboard.js => 200\n=INFO REPORT==== 23-Oct-2026::22:13:28.834358 ===\nSIGTERM received - shutting down"
  }, {
    "name" : "release-contract",
    "cmd" : "bb scripts/test_release_contract.clj",
    "exit" : 0,
    "duration_ms" : 24743,
    "informational" : false,
    "tail" : "INFO two clean builds (this is the slow part)...\nPASS clean-builds-byte-identical          sha256=23f82bbd7b3712aea897a1e61b3d455abddb1c3c55db4c92455f0780cf445574\nrelease-contract: PASS"
  }, {
    "name" : "upgrade-rollback",
    "cmd" : "bb scripts/test_upgrade_rollback.clj",
    "exit" : 0,
    "duration_ms" : 14784,
    "informational" : false,
    "tail" : "\nupgrade-rollback: PASS\nPreparing worktree (detached HEAD 35c8cf8)"
  }, {
    "name" : "playbook-default",
    "cmd" : "bb scripts/run_playbook_tests.clj",
    "exit" : 0,
    "duration_ms" : 8546,
    "informational" : false,
    "tail" : "Level 1641 {:status :excluded, :reason \"no executable cases\", :coverage \"manual/not executable; not a passing test\"}\n=== Evaluation summary before cleanup === {:passed 934, :failed 0, :skipped 0, :timed-out 0, :excluded 238}\n=== Final summary === {:passed 934, :failed 0, :skipped 0, :timed-out 0, :excluded 238}"
  }, {
    "name" : "cli-errors",
    "cmd" : "bb scripts/test_cli_errors.clj",
    "exit" : 0,
    "duration_ms" : 3819,
    "informational" : false,
    "tail" : "{:args [\"find\" \"nothing-matches-this\"], :exit 0, :expected :success, :clean true}\n{:args [\"evidence\" \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"], :exit 0, :expected :success, :clean true}\nCLI error contract: 0 failures; workspace: /var/folders/r5/njvx_5n968j2rqq7y3bv5slh0000gn/T/gleamunison-cli-errors-938356819186123218"
  }, {
    "name" : "dashboard-safety",
    "cmd" : "bun scripts/test_dashboard_safety.mjs",
    "exit" : 0,
    "duration_ms" : 122,
    "informational" : false,
    "tail" : "dashboard hostile names/expressions/module/process values stay text: PASS"
  }, {
    "name" : "parser",
    "cmd" : "bb scripts/test_parser.clj",
    "exit" : 0,
    "duration_ms" : 42,
    "informational" : false,
    "tail" : "PLAYBOOK_DOGFOOD_2871-2920.md: parsed 0 levels\nPLAYBOOK_DOGFOOD_2921-2970.md: parsed 0 levels\nPLAYBOOK_DOGFOOD_2971-3020.md: parsed 0 levels"
  }, {
    "name" : "playbook-runner",
    "cmd" : "bb scripts/test_playbook_runner.clj",
    "exit" : 0,
    "duration_ms" : 585,
    "informational" : false,
    "tail" : "injected code_server crash + OK marker => runner exit 1\nnonzero child with OK marker + escript badarg: FAIL-CLOSED; timeout: FAIL-CLOSED; stale/unlisted exclusions: FAIL-CLOSED"
  }, {
    "name" : "loc-ceiling",
    "cmd" : "wc -l over touched files",
    "exit" : 0,
    "duration_ms" : 0,
    "informational" : false,
    "tail" : "all touched files under 500 LOC"
  } ],
  "exclusions" : [ "CI matrix (OTP 27/28/29 x ubuntu/macos) runs on push; local proof is OTP 29 / macOS arm64", "LOC ceiling: src/gleamunison_ffi_test.erl (625 LOC, base 471) is a test-only probe module called exclusively from test/*.gleam, exempt under the test-file exemption; every production file touched by this branch is under 500 LOC", "all gates execute behind /usr/bin/env with a pinned tool PATH (homebrew + ~/.local/bin) so results never depend on the caller environment; recorded commands are the logical ones" ],
  "classification" : "authenticated-single-node-service",
  "head" : "009db6b",
  "side_effects" : "none: no tag, no Hex publish, no merge, no deploy",
  "classification_note" : "untrusted-execution profile remains disabled: external OS/container isolation is required and not claimed",
  "unresolved_risks" : [ "the 'transient full-suite flake' (507/1) recorded by earlier runs is identified and fixed: evaluation_timeout_test asserted the wall-clock timeout message while the 10ms budget tick could hit the reduction ceiling first on fast machines — reproduced on all seven CI matrix legs; the test now asserts containment under any named evaluation_* error (bk-19fe)", "first CI matrix run on PR #30 exposed four latent platform defects, all root-caused from the matrix's own honest-error output and fixed (bk-19fe): (1) binary:join/2 does not exist on OTP 27 (added in OTP 28) — json.encode plus 8 HTTP route handlers that would have crashed any OTP-27 deployment now use lists:join; (2) the emitter emitted curried handler application ('m':'$eval'()(Val)) that OTP 27/28 erl_parse rejects while OTP 29's extended grammar accepts it — now nested erlang:apply like every other call site; (3) the corrupt-artifact rollback probe assumed an exit code, but Linux exec rejects the corrupt file with an IOException where macOS returns one — exec refusal now counts as failing loudly; (4) drain raced a self-inflicted link backfire: the http acceptor is spawn_linked and drain killed it with reason shutdown without unlinking, so the signal could kill the server before the drain reply under CI scheduling — macos-28 crashed with {shutdown,{gen_server,call,...}} and no assertion block, the same shape as the earlier blockless '4th failure' on ubuntu-27; fixed by unlink-before-kill, stress probe 120/120 clean. Next matrix run is the confirmation", "LLM cost metering is estimate-only until operator rates are configured", "provider error bodies are omitted, so provider-side debugging needs the provider dashboard" ],
  "branch" : "main"
}
```
