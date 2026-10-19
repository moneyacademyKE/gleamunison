#!/bin/bash
# Build a standalone escript for gleamunison.
# Produces a single file that runs with just Erlang/OTP installed.
# Usage: ./build_escript.sh && ./gleamunison_escript server
set -euo pipefail
cd "$(dirname "$0")"

SCRIPT="gleamunison_escript"
SCRIPT_PATH="$PWD/$SCRIPT"
GLEAM_BIN="${GLEAM_BIN:-gleam}"
ERLC_BIN="${ERLC_BIN:-erlc}"

if ! command -v "$GLEAM_BIN" >/dev/null 2>&1; then
  echo "error: Gleam compiler not found: $GLEAM_BIN" >&2
  exit 127
fi
if ! command -v "$ERLC_BIN" >/dev/null 2>&1; then
  echo "error: Erlang compiler not found: $ERLC_BIN" >&2
  exit 127
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "error: zip is required to build the escript" >&2
  exit 127
fi

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

printf 'Building gleamunison escript...\n'
"$GLEAM_BIN" build

shopt -s nullglob
for dir in build/dev/erlang/*/ebin; do
  if [[ -d "$dir" ]]; then
    find "$dir" -type f -name '*.beam' -exec cp {} "$build_dir"/ \;
  fi
done
shopt -u nullglob

# Build output may retain test BEAMs from the preceding test run. Remove
# test-origin modules by their source paths, not an incomplete name guess.
for source in test/*.gleam test/*.erl src/*_test.erl; do
  [[ -f "$source" ]] || continue
  module=$(basename "$source")
  module=${module%.*}
  rm -f "$build_dir/$module.beam"
done
find "$build_dir" -maxdepth 1 -type f \( \
  \( -name '*_test.beam' ! -name 'gleamunison@cli_test.beam' \) -o \
  -name '*_test_ffi.beam' -o \
  -name 'gleeunit*.beam' -o -name 'birdie*.beam' \
\) -delete

# The compiler derives this metadata from gleam.toml. Load it at escript
# startup rather than maintaining another version literal.
cp build/dev/erlang/gleamunison/ebin/gleamunison.app "$build_dir/"

# Compile raw Erlang genesis modules. Any failure aborts the build.
for source in src/m_*.erl; do
  [[ -f "$source" ]] || continue
  "$ERLC_BIN" -o "$build_dir" "$source"
done

beam_count=$(find "$build_dir" -maxdepth 1 -type f -name '*.beam' | wc -l | tr -d ' ')
if [[ "$beam_count" -eq 0 ]]; then
  echo "error: build produced no BEAM files" >&2
  exit 1
fi
printf '  Beams: %s\n' "$beam_count"

zip_path="$build_dir/$SCRIPT.zip"
(
  cd "$build_dir"
  zip -q "$zip_path" ./*.beam ./gleamunison.app
)

artifact_tmp="$build_dir/$SCRIPT"
{
  printf '#!/usr/bin/env escript\n%%! -noshell -sname gleamunison\n'
  cat "$zip_path"
} > "$artifact_tmp"
chmod +x "$artifact_tmp"

# Replace only after every build step succeeds; a failed build leaves the
# previous artifact untouched.
mv -f "$artifact_tmp" "$SCRIPT_PATH"
printf '  Size: %s bytes\n' "$(wc -c < "$SCRIPT_PATH" | tr -d ' ')"
printf '  Run: ./%s server\n' "$SCRIPT"
