# Compatibility Matrix

What "supported" means here: the full test suite and both release gates
(`test_release_contract.clj`, `test_upgrade_rollback.clj`) run green in CI on
the combination. Anything else may work; it is not claimed.

| Component | Supported | Notes |
|---|---|---|
| Erlang/OTP | 27, 28, 29 | 27 is the floor: the readiness report uses the OTP 27 `json` module |
| Gleam | 1.19.x | pinned in CI as 1.19.1 |
| macOS | arm64 (Apple Silicon) | local development target |
| Linux | x86_64, arm64 | CI runs ubuntu-latest |
| Windows | unsupported | no CI, no claim |
| Hex deps | gleam_stdlib <2, gleamy_structures <3, simplifile <3, glam <3 | runtime closure; birdie/gleeunit are dev-only and never ship in the artifact |

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
