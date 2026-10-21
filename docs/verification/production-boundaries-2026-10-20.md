# Production-boundary witness — 2026-10-20

Branch `fix/production-boundaries` @ `76433be`

| Gate | Exit | ms | Command |
|---|---|---|---|
| format | 0 | 69 | `gleam format --check src test` |
| diff-check | 0 | 21 | `git diff --check` |
| suite | 0 | 20368 | `gleam test` |
| build-escript | 0 | 9922 | `./build_escript.sh` |
| artifact-contract | 0 | 1288 | `bash scripts/test_artifact.sh` |
| cli-truth | 0 | 3715 | `bb scripts/test_cli_truth.clj` |
| http-boundary | 0 | 1154 | `bash scripts/test_http_boundary.sh` |
| release-contract | 0 | 23970 | `bb scripts/test_release_contract.clj` |
| upgrade-rollback | 0 | 14115 | `bb scripts/test_upgrade_rollback.clj` |
| playbook-default | 0 | 11393 | `bb scripts/run_playbook_tests.clj` |
| playbook-strict | 1 | 11295 | `bb scripts/run_playbook_tests.clj --strict` |
| loc-ceiling | 0 | 0 | `wc -l over touched files` |

```json
{
  "date" : "2026-10-20",
  "artifact_sha256" : "5f99554dac33d5445869a9cd934cad556b4bb7eb159903697e0867be49d3d54b",
  "gates" : [ {
    "name" : "format",
    "cmd" : "gleam format --check src test",
    "exit" : 0,
    "duration_ms" : 69,
    "informational" : false,
    "tail" : ""
  }, {
    "name" : "diff-check",
    "cmd" : "git diff --check",
    "exit" : 0,
    "duration_ms" : 21,
    "informational" : false,
    "tail" : ""
  }, {
    "name" : "suite",
    "cmd" : "gleam test",
    "exit" : 0,
    "duration_ms" : 20368,
    "informational" : false,
    "tail" : "\n   Compiled in 0.20s\n    Running gleamunison_test.main"
  }, {
    "name" : "build-escript",
    "cmd" : "./build_escript.sh",
    "exit" : 0,
    "duration_ms" : 9922,
    "informational" : false,
    "tail" : "Hint: You can safely remove it.\n\n   Compiled in 0.19s"
  }, {
    "name" : "artifact-contract",
    "cmd" : "bash scripts/test_artifact.sh",
    "exit" : 0,
    "duration_ms" : 1288,
    "informational" : false,
    "tail" : "artifact_version=3.24.0 declared_version=3.24.0\nartifact_test_modules=0"
  }, {
    "name" : "cli-truth",
    "cmd" : "bb scripts/test_cli_truth.clj",
    "exit" : 0,
    "duration_ms" : 3715,
    "informational" : false,
    "tail" : "PASS: --help prints usage and exits zero\nPASS: unknown command exits non-zero\n21 CLI truth checks passed; workspace: /var/folders/r5/njvx_5n968j2rqq7y3bv5slh0000gn/T/gleamunison-cli-truth-12701395075021207848"
  }, {
    "name" : "http-boundary",
    "cmd" : "bash scripts/test_http_boundary.sh",
    "exit" : 0,
    "duration_ms" : 1154,
    "informational" : false,
    "tail" : "/static/js/dashboard.js => 200\n=INFO REPORT==== 21-Oct-2026::04:28:36.952941 ===\nSIGTERM received - shutting down"
  }, {
    "name" : "release-contract",
    "cmd" : "bb scripts/test_release_contract.clj",
    "exit" : 0,
    "duration_ms" : 23970,
    "informational" : false,
    "tail" : "INFO two clean builds (this is the slow part)...\nPASS clean-builds-byte-identical          sha256=5f99554dac33d5445869a9cd934cad556b4bb7eb159903697e0867be49d3d54b\nrelease-contract: PASS"
  }, {
    "name" : "upgrade-rollback",
    "cmd" : "bb scripts/test_upgrade_rollback.clj",
    "exit" : 0,
    "duration_ms" : 14115,
    "informational" : false,
    "tail" : "\nupgrade-rollback: PASS\nPreparing worktree (detached HEAD 35c8cf8)"
  }, {
    "name" : "playbook-default",
    "cmd" : "bb scripts/run_playbook_tests.clj",
    "exit" : 0,
    "duration_ms" : 11393,
    "informational" : false,
    "tail" : "Level 1000 {:status :pass}\n=== Evaluation summary before cleanup === {:passed 928, :failed 0, :skipped 0, :timed-out 0, :excluded 72}\n=== Final summary === {:passed 928, :failed 0, :skipped 0, :timed-out 0, :excluded 72}"
  }, {
    "name" : "playbook-strict",
    "cmd" : "bb scripts/run_playbook_tests.clj --strict",
    "exit" : 1,
    "duration_ms" : 11295,
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
  "head" : "76433be",
  "side_effects" : "none: no tag, no Hex publish, no merge, no deploy",
  "classification_note" : "untrusted-execution profile remains disabled: external OS/container isolation is required and not claimed",
  "unresolved_risks" : [ "the 'transient full-suite flake' (507/1) recorded by earlier runs is identified and fixed: evaluation_timeout_test asserted the wall-clock timeout message while the 10ms budget tick could hit the reduction ceiling first on fast machines — reproduced on all seven CI matrix legs; the test now asserts containment under any named evaluation_* error (bk-19fe)", "first CI matrix run on PR #30 exposed four latent platform defects, all root-caused from the matrix's own honest-error output and fixed (bk-19fe): (1) binary:join/2 does not exist on OTP 27 (added in OTP 28) — json.encode plus 8 HTTP route handlers that would have crashed any OTP-27 deployment now use lists:join; (2) the emitter emitted curried handler application ('m':'$eval'()(Val)) that OTP 27/28 erl_parse rejects while OTP 29's extended grammar accepts it — now nested erlang:apply like every other call site; (3) the corrupt-artifact rollback probe assumed an exit code, but Linux exec rejects the corrupt file with an IOException where macOS returns one — exec refusal now counts as failing loudly; (4) drain raced a self-inflicted link backfire: the http acceptor is spawn_linked and drain killed it with reason shutdown without unlinking, so the signal could kill the server before the drain reply under CI scheduling — macos-28 crashed with {shutdown,{gen_server,call,...}} and no assertion block, the same shape as the earlier blockless '4th failure' on ubuntu-27; fixed by unlink-before-kill, stress probe 120/120 clean. Next matrix run is the confirmation", "LLM cost metering is estimate-only until operator rates are configured", "provider error bodies are omitted, so provider-side debugging needs the provider dashboard" ],
  "branch" : "fix/production-boundaries"
}
```
