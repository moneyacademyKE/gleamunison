# Building the standalone escript

`./gleamunison_escript` packages Gleamunison and its BEAM dependencies in one
executable archive. It does **not** bundle the Erlang VM. Run it on Erlang/OTP
27, 28, or 29; Gleam is not required at runtime.

The artifact's byte size is a build measurement, not a compatibility promise.
Use the artifact and release gates below rather than an old size breakdown.

## Build requirements

- Bash
- Gleam 1.19.1
- Erlang/OTP with `erlc` and `escript`
- `zip`
- The runtime dependencies from `gleam.toml`

```sh
gleam deps download
./build_escript.sh
```

The script fails early when Gleam, `erlc`, or `zip` is missing. `GLEAM_BIN` and
`ERLC_BIN` can select alternate executables.

## What the build packages

1. `gleam build` compiles the application and dependencies.
2. The script copies BEAM files, removing test-origin modules and dev-only test
   frameworks from the artifact.
3. It compiles checked-in `src/m_*.erl` genesis implementations.
4. It synchronizes the self-hosted Datalog source into `priv/datalog/` and
   packages that source, dogfood level data, and dashboard static assets.
5. It regenerates `gleamunison.app` from the declared version, runtime
   dependencies, and actual packaged modules.
6. It creates a zip with normalized entry metadata, prepends the escript
   launcher, and atomically replaces `./gleamunison_escript` only after a
   successful build.

A failed build leaves the previous artifact in place. That does not make the
old artifact a successful build of the current source: check the command exit
and artifact evidence.

## Run

```sh
./gleamunison_escript --help
./gleamunison_escript repl
./gleamunison_escript server 8080
```

The CLI reads store, branch, profile, bind, authentication, evidence, and
provider settings from the environment as documented in `docs/OPERATIONS.md`.
An artifact is not preconfigured with a safe deployment profile or credentials.

## Verify the artifact

```sh
bash scripts/test_artifact.sh
bb scripts/test_release_contract.clj
bb scripts/test_upgrade_rollback.clj
```

These gates cover distinct contracts:

- **Artifact:** declared version, runtime dependencies, genesis/Datalog/static
  content, absence of test modules, and CLI behavior from the packaged file.
- **Release:** artifact contents plus byte-identical clean builds of the same
  source.
- **Upgrade/rollback:** the declared previous-version and recovery behavior,
  including loud refusal of a corrupt artifact.

The full `bb scripts/verify_production_boundaries.clj` run also builds the
escript and records a dated witness. Do not infer a new artifact hash from a
source commit alone; measure the artifact produced by the gate.

## Troubleshooting

### `escript: command not found`

Install a supported Erlang/OTP release and ensure `escript` is on `PATH`.
Check `erl -version` and `command -v escript`.

### Missing module or asset at runtime

Rebuild from the current tree and run `bash scripts/test_artifact.sh`. The
artifact must include more than BEAM files: Datalog source, dogfood data, and
static assets are runtime inputs too.

### Failure after a previous successful build

The build script preserves the previous artifact on failure. Read the failing
step, then verify the replacement artifact's version/hash and rerun the
artifact contract. Do not treat the mere existence of `gleamunison_escript` as
proof that the latest build succeeded.

### Reproducibility mismatch

Use a clean checkout at the same source revision and the pinned toolchain,
then run `bb scripts/test_release_contract.clj`. Do not compare an escript left
by an unrelated dirty-tree build with a clean release artifact.
