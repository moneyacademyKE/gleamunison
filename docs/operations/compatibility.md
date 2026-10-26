# Compatibility Matrix

What “supported” means here: the configured CI workflow exercises the
combination, or a dated local witness explicitly names the environment. A green
local run on one OTP/OS pair does not certify the rest of the matrix.

| Component | Supported | Notes |
|---|---|---|
| Erlang/OTP | 27, 28, 29 | 27 is the floor: the readiness report uses the OTP 27 `json` module |
| Gleam | 1.19.1 | pinned in CI |
| macOS | `macos-latest` in CI; arm64 locally verified | local witness records the exact OTP/toolchain |
| Linux | `ubuntu-latest` in CI | release gates run on this target / OTP 29; no separate arm64 CI claim |
| Windows | unsupported | no CI, no claim |
| Hex deps | gleam_stdlib <2, gleamy_structures <3, simplifile <3, glam <3 | runtime closure; birdie/gleeunit are dev-only and never ship in the artifact |

## Package manifest compatibility

Package manifests are content-addressed. New manifests use a versioned payload with per-definition effect metadata:

```text
pkg:2:<name>:<version>:<name>=<hash>=pure|effectful,...:<deps>:<yes|no>
```

The effect token is part of the canonical bytes and therefore part of the manifest ref. Definition ordering is canonical. The parser accepts the original unversioned `name=hash` payload as legacy data, defaults each entry to `effectful: False`, and preserves its legacy serialization so existing refs remain fetchable under their original hashes. Legacy manifests are intentionally conservative: missing metadata never grants the Io evidence path.

The current delimiter grammar has no escaping layer. Ambiguous structural delimiters and unknown effect tokens are rejected rather than silently producing content that cannot round-trip. Manifest refs are immutable; no in-place rewrite or migration is performed.

## Versioning contract

- Artifact identity lives in `gleam.toml` and flows into the packaged
  `gleamunison.app`; `gleamunison version` reads it at runtime. There is no
  second version literal to forget.
- `gleamunison schema-version` prints the storage/codec schema integer.
  Stores are compatible across releases exactly while this is equal. A bump
  requires an explicit migration step named in the release notes.

## Reproducibility

Two clean builds of the same source on the same toolchain are
byte-identical. The build pins zip entry timestamps to the zip epoch floor
and strips file attributes; `test_release_contract.clj` rebuilds twice from
a clean `build/` and compares SHA-256. Cached builds are not claimed to
match clean builds — release from a fresh checkout.

## CI

`.github/workflows/test.yml` runs the suite, `gleam format --check`, the
escript build, and the artifact test across the matrix
{ubuntu-latest, macos-latest} × {OTP 27, 28, 29}. The release gates run on
ubuntu-latest / OTP 29 (they rebuild the artifact repeatedly; one cell keeps
the signal without multiplying wall time).
