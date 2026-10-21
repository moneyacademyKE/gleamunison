#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
expected=$(sed -n 's/^version = "\([^"]*\)"/\1/p' gleam.toml)
actual=$(./gleamunison_escript version)
printf 'artifact_version=%s declared_version=%s\n' "$actual" "$expected"
test "$actual" = "$expected"
# unzip returns 1 for a valid archive with an escript preamble (extra bytes).
listing=$(unzip -Z1 ./gleamunison_escript 2>/dev/null || test "$?" -eq 1)
for source in test/*.gleam test/*.erl src/*_test.erl; do
  test -f "$source" || continue
  module=$(basename "$source")
  module=${module%.*}
  if printf '%s\n' "$listing" | grep -qx "$module.beam"; then
    printf 'test-only module in archive: %s\n' "$module" >&2
    exit 1
  fi
done
# cli_test implements the shipped `test` command; it is production code.
if printf '%s\n' "$listing" | grep -v '^gleamunison@cli_test.beam$' | grep -E '(^|/)(gleeunit|birdie)|_test\.beam$|_test_ffi\.beam$'; then
  echo 'test BEAMs in archive' >&2
  exit 1
fi
printf '%s\n' "$listing" | grep -qx gleamunison.app
# The datalog engine is Lisp source: if it is not in the archive, the CLI and
# the three MCP index tools cannot load it outside the repo root (bk-389b).
engine_count=$(printf '%s\n' "$listing" | grep -c '^priv/datalog/.*\.lisp$' || true)
printf 'artifact_engine_modules=%s\n' "$engine_count"
test "$engine_count" -eq 13
printf 'artifact_test_modules=0\n'
./gleamunison_escript --help > /dev/null
