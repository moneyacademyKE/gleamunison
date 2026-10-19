# Gleamunison Production Gap Audit

**Date:** 2026-10-19 (EAT)
**Scope:** live `/Users/moe/gleamunison` tree after loop-9 hardening; read-only source audit plus bounded CLI/runtime probes.
**Bankai:** `bk-14de` — Audit remaining gleamunison production gaps.
**Decision:** no source fix, release, merge, Hex publish, or tag action was taken during this audit.

## Executive verdict

The repository is functionally productive but not release-safe yet. The green unit suite is real — **421 passed, no failures** — but it does not cover several hostile-input, lifecycle, artifact, and verification boundaries. The most important failures are not missing features; they are places where invalid input can crash the VM, a timeout can leave user work alive, or a verification command can report success while the underlying process failed.

**Readiness score: 62/100.** This is an operational-gap score, not a test pass rate.

| Area | Score | Basis |
|---|---:|---|
| Core behavior and tests | 18/20 | 421 passing tests; format and diff checks green. |
| Security and input admission | 8/20 | Static path escape, unchecked hex decoding, narrow HTTP auth scope, and branch-pointer binding gaps. |
| Lifecycle and resource control | 8/15 | Evaluation timeout kills only the worker; HTTP/MCP lifecycles are hand-rolled and unsupervised. |
| Protocol/API correctness | 9/15 | MCP request validation and JSON escaping are incomplete; malformed peer input can crash. |
| Release artifact and verification | 7/15 | Artifact prints `development`, bundles 77 test-like BEAMs, and playbook verification is false-green. |
| Observability/readiness | 8/10 | Readiness and metrics hardening is useful and bounded, but does not cover the above boundaries. |
| Documentation/operability | 4/5 | Architecture and operations docs exist; release claims and runner semantics still diverge from reality. |

## Verified baseline

- Branch: `fix/loop9-truthful-verification`.
- HEAD: `b9267ec` (`origin/fix/loop9-truthful-verification` agrees).
- PR #15 is open; GitHub reports the required `test` check completed successfully.
- `gleam.toml` declares version `3.23.0`.
- Local tags stop at `v3.22.0`; GitHub release listing has no `v3.23.0` release.
- Before this report was written, the only tracked working-tree change was the rebuilt `gleamunison_escript`; it remains intentionally uncommitted and must not be discarded.

Receipts:

- `PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH gleam test` → `421 passed, no failures` (exit 0).
- `PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH gleam format --check src test` → exit 0.
- `git diff --check` → exit 0.
- `gh pr view 15 --repo moneyacademyKE/gleamunison ...` → PR open, `test` conclusion `SUCCESS`.

## Findings

### F-001 — Static asset path traversal (P1, high confidence) — [CLOSED]

`serve_static/2` routes `/static/<path>` to `handle_static_file/2` (`src/gleamunison_http_routes.erl:103-104`). The handler rejects only the literal byte sequence `../`, then passes the caller-controlled path to `filename:join(["priv", "static", FilePath])` (`:128-141`). A leading slash makes the final component absolute, so the static root is discarded.

Safe resolver-only reproduction (no file was read):

```text
erl -noshell -eval 'io:format("resolved=~p~n", [filename:join(["priv", "static", "/etc/passwd"])]), halt().'
resolved="/etc/passwd"
```

The current listener binds loopback (`src/gleamunison_http.erl:42`), which limits present network exposure, but the token gate protects only `/eval`, `/define`, and `/mcp` (`src/gleamunison_http.erl:152-177`). A reverse proxy, port-forward, or future bind change turns this into arbitrary local-file disclosure.

**Remediation:** reject absolute paths and decoded traversal, resolve against a fixed absolute root, enforce a prefix boundary, and add a regression test for `/static//etc/passwd`, encoded traversal, and backslash variants.

### F-002 — Invalid content hashes crash low-level FFI (P1, high confidence) — [CLOSED]

`manifest.ref_from_hex/1` calls `identity.hex_to_bytes/1` without validating length or characters (`src/gleamunison/manifest.gleam:60-63`; `src/gleamunison/identity.gleam:23-24`). The FFI directly calls `binary:decode_hex/1` (`src/gleamunison_ffi.erl:132-134`). The same unchecked conversion is used by namespace and sync paths.

Reproduction with the production signer gate bypassed only by a harmless test value:

```text
GLEAMUNISON_EVIDENCE_SIGNING_KEY=x ./gleamunison_escript pkg install nope
... binary:decode_hex(<<"nope">>) ...
exit=127
```

Without the signer, the command prints the missing-key error and exits 0, which is separately tracked as F-004.

**Remediation:** make hex parsing return `Result`, require exactly 64 hex characters for SHA-256 refs, and map malformed CLI/peer values to typed errors instead of exceptions.

### F-003 — Malformed TCP peer port crashes the command (P1, high confidence) — [CLOSED]

`parse_host_port/1` splits at the last colon and calls `list_to_integer/1` without validation (`src/gleamunison_ffi_io.erl:80-88`). The sync CLI passes user input into that path (`src/gleamunison/cli_sync.gleam:54-60`).

```text
./gleamunison_escript sync bad:abc
... list_to_integer("abc") ...
exit=127
```

This is both a CLI reliability defect and a network-boundary input defect. Port range, empty host, IPv6 literals, and multiple-colon forms are not validated here.

**Remediation:** parse a dedicated peer type, validate host/port/range before FFI dispatch, and return `sync: invalid peer ...` with a non-zero CLI exit.

### F-004 — CLI failures commonly exit zero (P1, high confidence) — [CLOSED]

Several command modules print an error or usage string and return `Nil` without calling the existing `halt_failure` boundary. Representative sources: MCP (`src/gleamunison/cli_mcp.gleam:11-18`), formatter (`src/gleamunison/cli_fmt.gleam:9-13,16-30`), replay (`src/gleamunison/cli_replay.gleam:34-45`), evidence (`src/gleamunison/cli_evidence.gleam:22-39`), find (`src/gleamunison/cli_find.gleam:13-24,53-57`), sync (`src/gleamunison/cli_sync.gleam:19-21,54-72`), and package install (`src/gleamunison/cli_pkg.gleam:117-120,184-200`).

Live artifact probes:

| Command | Output class | Exit |
|---|---|---:|
| `mcp --bad` | unknown argument | 0 |
| `fmt` | usage | 0 |
| `replay` | usage | 0 |
| `evidence` | usage | 0 |
| `find` | usage | 0 |
| `llm` | usage | 0 |
| `pkg install nope` without signer | production policy error | 0 |
| unknown top-level command | `Unknown command` | 1 |

Automation cannot distinguish refusal, malformed input, and success. This also makes CI and agent loops trust lies by default.

**Remediation:** use one typed command-result boundary that halts non-zero for every `Error`/usage/refusal, and test each subcommand's exit status through the standalone artifact.

### F-005 — Playbook verifier can report green after failures (P1, high confidence) — [CLOSED]

The runner checks only whether stdout contains `Level N: OK`; it ignores the subprocess exit code (`scripts/run_playbook_tests.clj:58-62`). Timeout counts are incremented and the session is restarted, but the final exit condition checks only `failed`, not `timed-out` (`:158-171`). The runner also destroys the REPL process in `finally` before it prints its summary (`:140-170`).

The latest recorded run printed `958 passed, 0 failed, 42 skipped`, then emitted `escript: Internal error: badarg ... code_server`; the shell exit was still 0. The source explains why: a timeout or subprocess crash does not necessarily increment `failed`, and `run-real-level` does not inspect `:exit`.

**Remediation:** require exit 0 plus the expected marker, make timeout/non-zero/runner exceptions fail the process, and report skipped levels as an explicit non-green state unless an allowlist explains them.

### F-006 — Evaluation timeout leaves spawned descendants alive (P1, high confidence) — [CLOSED]

`run_with_timeout/1` monitors a worker and kills only that worker on deadline (`src/gleamunison_repl_ffi.erl:118-149`). The evaluated code can spawn unlinked processes; the timeout path has no process-group or descendant ownership model.

Probe result:

```text
result={error,<<"evaluation_timeout">>}
child_alive_after_timeout=true
exit=0
```

The probe compiled a module whose evaluation spawned a sleeping child and then slept itself. The worker was killed, but the child remained alive until the probe explicitly killed it.

**Remediation:** execute evaluations under a supervisor-owned capability/process scope, link or monitor permitted children, and terminate the scope on timeout. Do not rely on killing one root process to contain arbitrary effectful code.

### F-007 — Standalone artifact is not release-self-describing (P1, high confidence) — [CLOSED]

`build_escript.sh` copies every BEAM from the build ebin directories and removes only `gleamunison_test.beam` and `gleeunit*.beam` (`:32-42`). It does not remove the other test modules. The current artifact contains **329 BEAM entries, including 77 test-like entries**.

The version FFI reads `application:get_key(gleamunison, vsn)` and falls back to `development` (`src/gleamunison_ffi.erl:196-201`), while the escript builder packages BEAMs but no application manifest (`build_escript.sh:57-67`).

```text
./gleamunison_escript version
 development
exit=0
```

CI only checks that the command runs (`.github/workflows/test.yml:24-25`); it does not assert `3.23.0`, the absence of test BEAMs, or a release artifact manifest.

**Remediation:** embed a generated version/application metadata module or `.app` manifest, exclude all `*_test.beam` and test-only FFI modules, and make CI assert version equality and artifact contents.

### F-008 — Namespace loading does not verify content identity (P1, high confidence) — [CLOSED]

Manifest fetches re-hash stored bytes before accepting them (`src/gleamunison/manifest.gleam:145-173`), but namespace loading only parses bytes returned for the requested ref (`src/gleamunison/namespace.gleam:106-115`). It does not compare `hash(bytes)` with the requested namespace ref. A mutable/trusted adapter or corrupted disk can therefore feed a structurally valid but identity-mismatched namespace.

Branch import has a related binding gap: pointer chunks are accepted if `parse_head/1` succeeds, but the parsed branch name is ignored (`src/gleamunison/namespace.gleam:74-93` and `:356-383`). A valid head for another branch can be stored under the name-derived pointer key.

**Remediation:** verify namespace bytes against the requested ref, require the expected branch name when importing a pointer, and make branch import atomic or journaled across storage failures.

### F-009 — HTTP and MCP lifecycle are hand-rolled, not supervised (P1, medium/high confidence) — [CLOSED]

The HTTP server spawns an unlinked listener and one unlinked process per request (`src/gleamunison_http.erl:14-18,34-61`). `stop_server/0` exits only the registered listener (`:24-31`); the control loop remains blocked and the persistent listener term is not cleared. MCP similarly checks `whereis`, then spawns/registers a session without a supervisor or race-proof reservation (`src/gleamunison_mcp_session.erl:8-21,31-50`).

The MCP route sends a request to the session and waits up to 30 seconds (`src/gleamunison_http.erl:195-210`). If the session dies after the lookup, callers wait for timeout; incoming requests can accumulate in its mailbox.

**Remediation:** put HTTP acceptor/request supervision and MCP session ownership under OTP supervisors, clear lifecycle state on terminate, cap concurrency/mailbox pressure, and make stop/start idempotent.

### F-010 — MCP and dashboard JSON boundaries are incomplete (P2, medium confidence) — [CLOSED]

The MCP decoder does not validate a `jsonrpc` field/version and turns malformed `tools/call` arguments into an empty dictionary (`src/gleamunison/mcp.gleam:44-71,110-126`). Tool schemas are emitted as only `{"type":"object"}` (`:98-107`), so clients cannot discover required arguments. Several response builders concatenate unescaped user-controlled strings (`src/gleamunison/mcp_session.gleam:289-302,448-461`; `src/gleamunison/codebase_index.gleam:119-139`).

The dashboard inserts API data with `innerHTML` rather than text nodes (`priv/static/js/dashboard.js:127-131,141-148,161-168`). Notebook names/expressions originate from the local `/define` route (`src/gleamunison_http_routes.erl:43-65,154-173`), so a local crafted value can become script-capable dashboard markup.

**Remediation:** use one JSON encoder, validate JSON-RPC 2.0/request shapes, emit real tool schemas, and use `textContent`/DOM construction for all API data.

## Healthy patterns worth preserving

- CAS admission verifies raw content and decoded definitions before network insertion (`src/gleamunison_cas.erl:6-24`; batch validation `:26-49`).
- TCP sync uses bounded frames and `binary_to_term(..., [safe, used])` (`src/gleamunison_tcp_sync.erl:20-28,104-118,169-179`).
- HTTP request headers/body have explicit byte/count limits (`src/gleamunison_http.erl:3-5,98-129`).
- Readiness checks run in a bounded worker and return 503 when required checks fail (`src/gleamunison_readiness.erl:42-60`; `:25-28`).
- Production evidence requires a configured signer and HMAC verification (`src/gleamunison/evidence.gleam:48-82,164-193,247-278`).
- The current full Gleam suite and format gate are green; those are useful foundations, not proof that the negative paths above are closed.

## Prioritized follow-up queue

### P0 — stop release work until these are closed

1. **Input-boundary hardening:** safe hex parser plus safe peer parser; no malformed CLI/network input may raise `badarg` or exit 127.
2. **Static/admin HTTP boundary:** close path traversal and define/authenticate the complete route surface.
3. **Evaluation containment:** kill or supervise descendants when a bounded evaluation expires.

### P1 — required for a trustworthy production artifact

4. **CLI and verifier exit semantics:** make refusals, usage errors, timeouts, subprocess crashes, and skipped verification fail closed.
5. **Release artifact proof:** embed version metadata, remove test BEAMs, and assert artifact contents/version in CI.
6. **CAS/branch integrity:** re-hash namespace loads, bind imported pointers to branch names, and decide on atomic storage semantics.
7. **OTP lifecycle:** supervise HTTP/MCP acceptors and request workers; make stop/restart state truthful.

### P2 — hardening after the P0/P1 boundary work

8. **Protocol/output correctness:** MCP JSON-RPC validation and schemas; centralized JSON escaping; dashboard DOM-safe rendering.
9. **Resource policy:** bound HTTP request concurrency, SSE clients, trace retention, MCP mailbox depth, and large-store list operations.
10. **Release and security review:** TLS/reverse-proxy contract, distributed Erlang cookie/epmd threat model, dependency/CVE audit, and crash-recovery drills.

Any implementation bead should open or link a GitHub issue before source changes, then carry its Bankai ID in the commit and verification witness.

## Not examined in this pass

- TLS termination, reverse-proxy configuration, firewall/launchd hardening, and production host permissions.
- Hex credential validity, actual Hex publication, release tagging, or public package API compatibility; publication was intentionally not attempted.
- Full dependency CVE/license audit and reproducible-build provenance.
- Hot-code-upgrade behavior under a live distributed cluster.
- Windows/OTP-version portability, IPv6 peer behavior, and large (>1 MiB) store performance.
- Complete MCP conformance against the current protocol test suite.
- Crash-recovery behavior when Mnesia/DETS initialization fails during daemon boot.

**Rich Hickey check:** the next move is not another framework layer. It is a handful of composable boundary functions — parse, validate, admit, supervise, and report — with hostile-input tests at each seam. That deletes incidental complexity instead of decorating it.

## Closure update — 2026-10-19 (EAT)

The findings above are the historical baseline captured at `b9267ec`. The implementation pass is now closed on `f569ca6`; this section is the current status and does not erase the original evidence or scores.

| Finding | Current status | Fix commit(s) | Verification evidence |
|---|---|---|---|
| F-001 static path traversal | **Closed** | `5a06fe1`, `efe085e` (`bk-b086`) | `bk-b086-green.log`; live traversal probes return 403 |
| F-002 malformed content hashes | **Closed** | `e3efcc6` (`bk-ba7b`) | `bk-ba7b-green.log`; malformed refs are typed failures |
| F-003 malformed peer ports | **Closed** | `e3efcc6` (`bk-ba7b`) | `bk-ba7b-green.log`; malformed peer exits non-zero |
| F-004 false-zero CLI failures | **Closed** | `e2ac0a2`, `e06c68b` (`bk-f0e7`, `bk-4212`) | `bk-9e6c-cli-errors-final.log`; 0 failures, expected failures exit 1 |
| F-005 playbook false-green | **Closed** | `7344668`, `4e9b2a1` (`bk-d978`) | `bk-9e6c-playbook-default.log`; 928 passed, 0 failures/timeouts |
| F-006 orphaned evaluation descendants | **Closed** | `ccaa6ac` (`bk-1486`) | `bk-1486-green.log`; child and grandchild dead after timeout |
| F-007 misleading escript artifact | **Closed** | `4a05bc7` (`bk-95a8`) | `bk-9e6c-artifact-probes.log`; version 3.23.0, app present, no disallowed test BEAMs |
| F-008 namespace/branch identity gaps | **Closed** | `c42a417` (`bk-3848`) | `bk-3848-green.log`; tamper and cross-branch regressions pass |
| F-009 unsupervised HTTP/MCP lifecycle | **Closed** | `f569ca6` (`bk-a20e`) | `bk-a20e-mcp-live.log`, `bk-a20e-final.log`; live HTTP 200 and stop cleanup `{undefined,undefined}` |
| F-010 incomplete MCP/dashboard JSON boundaries | **Closed** | `5a06fe1`, `f569ca6` (`bk-b086`, `bk-a20e`) | `bk-a20e-mcp-live.log`, `bk-a20e-final.log`; JSON-RPC initialize returns 200 |

### Current gate summary

- `gleam test`: exit 0, **440 passed, no failures**.
- `gleam format --check src test`: exit 0.
- `git diff --check`: exit 0.
- `./build_escript.sh`: exit 0; 253 BEAMs, 1,335,302 bytes.
- CLI error battery: exit 0; 0 failures.
- CLI truth battery: exit 0; 19 checks passed.
- Default playbook: exit 0; 928 passed, 72 source-pinned exclusions, 0 failures/timeouts.
- Strict playbook: exit 1 by policy because the same 72 manual/non-executable cases are reported as skipped; it does not hide them as passes.
- Live `/api/live` and `/mcp` probes: HTTP 200; MCP protocol `2025-06-18`; server version `3.23.0`.

The rebuilt `gleamunison_escript` is intentionally left uncommitted. Release remains frozen: **no tag, no Hex publish, and no merge** were performed.

**Rich Hickey closure check:** each gap now has one boundary owner and one receipt trail. The fix is composition — parse, validate, supervise, verify — not a new orchestration layer wearing a larger hat.
