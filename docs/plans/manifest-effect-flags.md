# Manifest effect flags implementation plan

**Date:** 2026-10-24 EAT (UTC+3)
**Tracking:** Bankai `bk-026d`
**Audit:** `docs/audit/2026-10-24-manifest-effect-flags.md`
**Status:** implemented and verified; this plan records the shipped design

## Goal

Preserve the effectfulness fact already computed at publish time through the content-addressed manifest boundary so package installation applies the same evidence rule as direct publish. Pure definitions continue to require Test evidence; effectful definitions may use Io attestation. Existing manifests remain readable and retain their historical pure semantics.

## Design decision

Use one versioned canonical manifest payload with one definition-entry representation. Keep the legacy parser as an explicit compatibility branch:

- **Legacy:** `pkg:<name>:<version>:<name>=<hash>,...:<deps>:<evidence>`; every parsed entry becomes `effectful: False`.
- **Current:** `pkg:2:` plus each entry's canonical `pure` or `effectful` token. The parser rejects malformed entry shapes and unknown effect tokens; no escaping grammar is added.
- **Internal data:** use one named `ManifestDef` value carrying name, content hash, and effectful boolean. Do not retain a parallel list of effectful names.
- **Hashing:** canonical sorting includes the serialized effect token, so changing pure/effectful status changes the manifest ref.
- **Install:** pass the parsed boolean into `turnstile.check_with_policy` instead of reconstructing `False` for every entry.

The format marker is required so a current manifest cannot be mistaken for a legacy payload. No in-place rewrite or migration of old manifest refs is performed: immutable refs remain immutable, and newly published packages use the current format.

## File changes

### `[MODIFY] src/gleamunison/manifest.gleam`

- Current `pkg:2:` serialization/parsing.
- Legacy byte-preserving parse path with `effectful: False` defaults.
- Named `ManifestDef` data and accessors.
- Deterministic canonical sorting and strict effect-token/entry-shape parsing.

### `[MODIFY] src/gleamunison/pkg.gleam`

- Publish stores the supplied effectful flag.
- Install passes the parsed flag to the existing turnstile policy.
- Dependency recursion, cycle detection, branch commits, trust policy, and closure transfer remain unchanged.

### `[MODIFY] test/manifest_test.gleam`

- Current/legacy round trips preserve the intended representation.
- Canonical ordering remains deterministic.
- Malformed and unknown effect tokens refuse.

### `[MODIFY] test/pkg_test.gleam`

- Publish/fetch preserves effect flags.
- Effectful package installation succeeds with only Io evidence under a fixture policy.
- Pure package installation with only Io evidence refuses.
- Existing package recursion, cycle, closure, and no-evidence regressions remain green.

### `[MODIFY] docs/operations/compatibility.md`

- Documents the versioned manifest format, legacy-read behavior, conservative pure semantics, and immutable refs.

### `[NEW] docs/audit/2026-10-24-manifest-effect-flags.md`

- Final re-audit with actual receipts; uploaded to Telegram topic 10282.

### `[MODIFY] docs/verification/production-boundaries-2026-10-24.md`

- Regenerated integrated boundary witness; uploaded to Telegram topic 10282.

## Execution and verification receipts

1. Manifest and package regressions were added, then repaired against the real parser constraints.
2. `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam format --check src test` — exit 0.
3. `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam check --target erlang` — exit 0.
4. `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam clean && gleam test` — exit 0; **617 passed, 0 failures**.
5. `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; bb scripts/verify_production_boundaries.clj` — exit 0; integrated gate PASS.
6. `git diff --check` — exit 0; `manifest.gleam` 314 LOC and `pkg.gleam` 301 LOC.
7. Final audit and boundary witness were uploaded to Telegram topic 10282. No release/deploy/publish/push/tag/merge action occurred.

## Compatibility and rollback

- Legacy manifests parse as pure. Missing metadata never grants the Io admission path.
- New manifests have new refs because their canonical bytes include the format marker and effect token.
- A failed upgrade can roll back the code without rewriting the store; old and new refs remain immutable data.
- The current package protocol still transfers manifest refs and definition refs; no peer API change is required.

## Verification contract

- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam format --check src test` exits 0.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam check --target erlang` exits 0.
- Focused `manifest_test` and `pkg_test` cover current/legacy parsing, mixed flags, Io-only effectful admission, pure refusal, and recursive installs.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam clean && gleam test` exits 0 with zero failures.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; bb scripts/verify_production_boundaries.clj` exits 0 with all required gates passing.
- `git diff --check` exits 0 and all changed production files remain below 500 LOC.
- No `gleamunison_escript`, 2026-10-23 witness, push, release, deploy, tag, publish, or merge is part of this plan.

## Rejected alternatives

- **Infer effectfulness during install from stored AST:** rejected; it duplicates publish analysis, makes legacy behavior dependent on decoder details, and creates a second source of truth.
- **Add a parallel effectful-name list:** rejected; names and flags can drift, and canonical hashing becomes unclear.
- **Treat all manifests as effectful:** rejected; it weakens the evidence boundary and lets Io attestations replace tests for pure definitions.
- **Treat all manifests as pure:** rejected; it is the current bug and makes effectful packages unusable after transfer.
- **Rewrite legacy manifests in place:** rejected; content-addressed refs are immutable and migrations must not silently change identity.
- **Invent a new production trust or peer protocol:** rejected; neither is needed to carry an already-computed boolean through a local format boundary.

## Rich Hickey recommendation

Carry data once, canonically, and let the existing turnstile decide once. A version marker plus a legacy parser is less complected than inference, parallel metadata, or an in-place migration pretending immutable content is mutable.
