# Building the Standalone Escript

The `gleamunison_escript` is a standalone binary that bundles the entire gleamunison runtime into a single file. It requires only Erlang/OTP 29+ to run — no Gleam installation, no dependency resolution, no build step.

## How It Works

Escripts are Erlang's native packaging format. They work by prepending a shebang line to a zip archive containing BEAM bytecode files. When executed, the Erlang runtime:

1. Finds the `PK` magic bytes (zip header) after the shebang
2. Extracts BEAM files into memory
3. Executes the `main/1` function of the designated module

## Build Process

```sh
./build_escript.sh
```

The script performs these steps:

### 1. Gleam Compilation
```sh
gleam build
```
Compiles all Gleam source code (`src/gleamunison/*.gleam`, `src/*.gleam`) to BEAM bytecode. Output lands in `build/dev/erlang/*/ebin/`.

### 2. Collect All BEAM Files
All `.beam` files from every dependency directory are collected into a temp directory. Test beams (`gleeunit`, `gleamunison_test`) are excluded to keep the escript lean.

### 3. Compile Genesis Modules
```sh
for f in src/m_*.erl; do
  erlc -o "$TMPDIR" "$f"
done
```
The 52 genesis modules (`m_*.erl`) are compiled directly by `erlc` (Erlang compiler). This step is required because genesis modules are written in raw Erlang — they bootstrap the runtime before the Gleam compiler runs. See `docs/genesis-modules.md`.

### 4. Package into Escript
```sh
cd "$TMPDIR"
zip -q "${SCRIPT}.zip" *.beam
cd -
printf '#!/usr/bin/env escript\n%%! -noshell -sname gleamunison\n' > "${SCRIPT}"
cat "$TMPDIR/${SCRIPT}.zip" >> "${SCRIPT}"
chmod +x "${SCRIPT}"
```

The shebang line tells the OS to use `escript` as the interpreter. The `%%!` comment line passes flags to the escript runner: `-noshell` suppresses the Erlang shell, `-sname gleamunison` sets the node name for distributed features.

The zip is appended directly after the header. The escript runtime scans for `PK` magic bytes, ignoring the header text.

## Size Breakdown

| Component | Size |
|---|---|
| 52 genesis modules (compiled) | ~100 KB |
| 27 Gleam library modules | ~400 KB |
| 24 hex dependencies (stdlib, json, structures, etc.) | ~600 KB |
| Total zip | ~1.1 MB |
| Shebang + escript header | ~50 bytes |

**Why 1.1 MB?** BEAM bytecode is dense. The compiled `.beam` files total ~2.4 MB uncompressed; zip compression (LZ77) brings that down to ~1.1 MB. No VM is bundled — the escript relies on the system's existing Erlang installation.

## Running

```sh
./gleamunison_escript repl     # Interactive REPL
./gleamunison_escript server   # Web dashboard on :8080
```

## Troubleshooting

### "escript: command not found"
Erlang/OTP is not installed or not in `$PATH`. Install via:
```sh
# macOS
brew install erlang

# Ubuntu/Debian
apt install erlang

# Verify
erl -version  # Should show 29+
```

### "no beam file found for module X"
A dependency's `.beam` file is missing from the escript. Rebuild with:
```sh
gleam clean
gleam build
./build_escript.sh
```

### "function_clause" or "undef" at startup
A genesis module failed to compile or wasn't included. Check:
```sh
ls src/m_*.erl | wc -l   # Should show 52
```
If fewer than 52 genesis modules exist, some builtins are missing.

### Future: `gleam release`
Per the Phase 10 roadmap, the escript approach will eventually be replaced by `gleam release`, which will produce a standalone tarball including ERTS (Erlang Runtime System). This will eliminate the need for Erlang/OTP to be pre-installed on the target machine.
