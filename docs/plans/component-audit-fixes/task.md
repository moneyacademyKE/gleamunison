# Fix-all checklist mirror

The session checklist is the state machine; Bankai `bk-be00` is durable tracking. This is its file projection, not a second queue.

- [x] 1. Inventory components and boundaries.
- [x] 2. Audit source boundaries and hostile inputs.
- [x] 3. Audit suite, artifacts, CI, dependencies and docs.
- [x] 4. Write and upload the component audit.
- [x] 5. Close audit `bk-c0ba` with raw probes and corrected report.
- [x] 6. Retraction safety (`bk-9f57`) and Mnesia deletion (`bk-1201`).
  - [x] Commits `105d986`, `d4995f4`; 626 tests passed.
- [x] 7. Unicode LSP (`bk-1180`) and MCP Datalog literals (`bk-a8c4`).
  - [x] Commits `f6256dc`, `44ea8d8`; 636 tests passed, real LSP stdio probe 0 failures.
- [x] 8. Ranking (`bk-95f2`) and operation-local traversal snapshots.
  - [x] Commits `90ecc95`, `1dbdb92`, `6344350`, `d917be3`; 642 tests passed.
  - [x] At 1,000 docs: BM25 78,472→314 µs, hybrid 95,475→13,668 µs; warmed synthetic medians, not production p95.
  - [x] Evidence gate listings 20→1, report 3→1, namespace reads 3→1; dependency snapshot lists once.
- [x] 9. Shared source admission budgets (`bk-4e1f`).
  - [x] `ef7f95a`; 649 tests passed. Default playbook: 934 passed, 0 failed/timeouts, 238 explicit exclusions.
- [x] 10. CI contract and documentation parity (`bk-35a3`).
  - [x] Strict diff/LOC gates, LSP CI probe, publish prerequisites; README counts and trust boundaries refreshed.
- [x] 11. Clean full verification, benchmark comparison, final re-audit/upload.
  - [x] Final probe exit 0: storage refusal, transactional Mnesia deletion, UTF-8 byte framing, literal safety, and parser budget refusal.
  - [x] Clean suite 649 passed; format/check, contracts, playbook 934 passed + 238 explicit exclusions, and integrated 15-gate witness exit 0.
  - [x] Final report `docs/audit/2026-10-24-whole-codebase-component-audit.md` uploaded to Telegram topic `10282`; current README witness link uploaded too.

Current boundary: task 9 verified in `ef7f95a`. One source owner bounds bytes/tokens/depth/forms/token bytes before grapheme expansion; all native source consumers get explicit parse refusals. Generated index data is flat rather than deeply nested. Limits do not bound the initial file read or replace an OS sandbox. Task 10 is active.

Performance raw logs remain under `docs/audit/probes/2026-10-24-benchmark-{before,after}.log`; the default defect probe is repaired in task 11. Prepared session embeddings remain deferred pending repeated-query measurements.

No push, publish, release, deploy, merge or tag. Existing witness/escript dirt is excluded from commits.
