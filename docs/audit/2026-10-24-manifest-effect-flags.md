# Audit — manifest effect flags

**Date:** 2026-10-24 EAT (UTC+3)
**Tracking:** Bankai `bk-026d`
**Status:** implemented and verified
**Scope:** Package manifest serialization, publish/install evidence gating, legacy parsing, and tests.
**Method:** Fresh source inspection plus clean suite and production-boundary receipts. No runtime package publication, push, release, deploy, tag, or merge action was performed.

## Verdict

The confirmed medium package-admission defect is fixed: publish now carries per-definition effectfulness into the versioned manifest, and installation applies the stored flag instead of reconstructing every definition as pure. Legacy manifests remain readable and conservative: missing metadata parses as `effectful: False` and preserves the legacy hash.

The implementation is verified by the full clean suite (**617 passed, 0 failures**) and the integrated production-boundary gate (**all gates PASS**). No package was published and no release/deploy action was performed.

## Evidence

### Publish carries the computed flags

`src/gleamunison/cli_publish.gleam` produces `List(#(String, String, Bool))` from `hash_defs`. The third field is the transitive effectful result from `compute_effectful`, which walks `ast.Do` terms and their intra-batch dependencies. `pkg.publish_to_store_with_policy` receives the same triple shape, passes it to `turnstile.check_with_policy`, and now stores it with `manifest.add_def_with_effect`.

### Versioned manifests preserve effect flags

Current manifests serialize as:

```text
pkg:2:<name>:<version>:<name>=<hash>=pure|effectful,...:<deps>:<yes|no>
```

The format marker makes the parser branch explicit, and the effect token is part of the canonical content hash. Definition ordering remains deterministic. Legacy `pkg:<name>:<version>:<name>=<hash>,...:<deps>:<yes|no>` entries parse as pure and serialize back to their original legacy form, so old refs retain their historical identity.

### Install applies the stored flags

`src/gleamunison/pkg.gleam` fetches the manifest and maps each `ManifestDef` into `turnstile.check_with_policy` with its stored `effectful` boolean. Effectful definitions can therefore use Io evidence after transfer; pure definitions still require Test evidence. The existing turnstile remains the sole admission-policy owner.

## Compatibility constraints

- Existing manifest refs are content hashes of serialized canonical text. New manifests use the explicit `pkg:2:` representation; old refs remain fetchable because parsed legacy manifests retain `format_version: 1` and re-serialize with legacy bytes.
- Legacy `name=hash` entries have no effect metadata. They parse as `effectful: False`, preserving historical pure-gate behavior rather than guessing from definition bytes.
- Current effect tokens are restricted to `pure` and `effectful`; unknown or malformed entries refuse instead of defaulting to effectful.
- The current delimiter grammar is intentionally narrow: names, versions, hashes, and dependency refs must not contain the structural `:`, `,`, or `=` delimiters. The parser rejects ambiguous shapes; no escaping grammar is invented in this cycle.
- Package dependencies remain manifest refs; only the definition-entry encoding changed.
- No operator secret/configuration change is involved.

## Smallest design

Use a format version in the manifest canonical payload and carry the boolean in each definition entry. Keep the parser as an explicit legacy branch. The shipped implementation uses:

```text
pkg:2:<name>:<version>:<name>=<hash>=<effect>,...:<deps>:<evidence>
```

where `<effect>` is the canonical `pure` or `effectful` token. Names and versions are not escaped; the current parser rejects ambiguous structural delimiters rather than silently producing a payload that cannot round-trip. `Manifest.defs` is one named `ManifestDef` value carrying name, hash, and effectful state; no parallel effect list exists.

An alternative is to add a parallel `effectful_defs` list while retaining `defs`. That creates two sources of truth and makes hash/serialization drift likely; reject it.

## Required tests and actual coverage

The implementation includes the required behavior checks:

1. Current-format serialize/parse round trip preserves mixed pure/effectful flags (`manifest_effect_flags_round_trip_test`).
2. Legacy text parses all entries as pure and re-serializes byte-canonically (`legacy_manifest_defaults_defs_to_pure_test`).
3. Pure definition with only Io evidence remains refused after install (`install_pure_def_refuses_io_only_evidence_test`).
4. Effectful definition with only Io evidence is admitted after install (`install_effectful_def_uses_io_evidence_test`).
5. Publish/fetch preserves the effectful bit (`publish_preserves_effect_flag_test`).
6. Canonical ordering remains deterministic and insertion-order independent (`manifest_hash_order_independent_test`).
7. Unknown or malformed effect tokens refuse through the current parser shape; the parser does not default unknown values to effectful.
8. Existing dependency closure and recursive install tests remain green.

## Rich Hickey certification

One dropped fact now crosses one versioned data boundary; the existing turnstile remains the sole admission owner. Legacy refs retain their bytes and conservative pure semantics. No second policy, peer protocol, escaping subsystem, or parallel metadata list was introduced.

## Verification receipts

- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam clean && gleam test` — exit 0; **617 passed, 0 failures**.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam format --check src test` — exit 0.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; gleam check --target erlang` — exit 0; one pre-existing unused `None` import warning in `test/sync_accept_test.gleam`.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; bb scripts/verify_production_boundaries.clj` — exit 0; integrated gate PASS, all listed gates PASS, including artifact and LOC checks.
- `export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH; git diff --check` — exit 0.
- Changed production files are below the hard 500-line ceiling: `src/gleamunison/manifest.gleam` **314 lines**; `src/gleamunison/pkg.gleam` **301 lines**.

The boundary gate regenerated `docs/verification/production-boundaries-2026-10-24.md`. The pre-existing `docs/verification/production-boundaries-2026-10-23.md` and `gleamunison_escript` were not staged or intentionally changed by this cycle. Their post-gate checksums were recorded before commit review. No push, release, deploy, tag, publish, or merge occurred.
