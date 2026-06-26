# ADR-0013: escript standalone binary packaging

**Status:** Accepted

**Date:** 2026-06-26

## Context

The gleamunison runtime needs to run without requiring Gleam to be installed.
Users should be able to distribute the runtime as a single executable file.

The project is written in Gleam (compiled to Erlang BEAM). The Erlang OTP
distribution includes `escript`, a tool that bundles Erlang code into a
single executable script file that runs with just `erl` installed.

## Decision

Package the runtime as an escript — a single file with:
1. A `#!/usr/bin/env escript` shebang line
2. A `%%!` arguments line (`-noshell -sname gleamunison`)
3. A ZIP archive containing all `.beam` files (gleamunison + gleam_stdlib)

The escript is built by:
```sh
gleam build                                           # compile all modules
find ebin -name '*.beam' -exec cp {} tmp \;           # collect beams
zip -q gleamunison.zip *.beam                          # create zip
printf '#!/usr/bin/env escript\n%%! ...\n' |
  cat - gleamunison.zip > gleamunison                  # prepend header
chmod +x gleamunison                                   # make executable
```

The escript runtime finds the ZIP archive by scanning for the `PK` magic
bytes. The shebang line and Erlang arguments are plain text before the ZIP,
which escript handles correctly.

## Consequences

**Positive:**
- Single file, ~281KB for gleamunison + gleam_stdlib
- No Gleam dependency — only requires Erlang/OTP
- Portable across platforms
- ZIP can be inspected with standard tools

**Negative:**
- Requires Erlang/OTP to be installed (~200MB)
- Not a true native binary — still needs `erl` on `PATH`
- Module names with `@` character break `escript:create/2` (see ADR-0011)

**Alternatives considered:**
- **`escript:create/2` API**: The official Erlang API for creating escripts.
  Rejected because it rejects `@` in module names with `{error, einval}`.
  Also more complex — requires an Erlang module to generate the escript.
- **Burrito**: Wraps the entire Erlang VM into a native binary. Rejected
  for the prototype because it adds complexity and build-time dependencies.
  Worth revisiting for production when true standalone binaries are needed.
- **Mix release**: Creates a release directory with the Erlang runtime.
  Rejected because it's more complex than escript and still requires Erlang.
