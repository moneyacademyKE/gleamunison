#!/bin/bash
# Build a standalone escript for gleamunison.
# Produces a single file that runs with just Erlang/OTP installed.
# Usage: ./build_escript.sh && ./gleamunison_escript server
set -e
cd "$(dirname "$0")"

SCRIPT="gleamunison_escript"
echo "Building gleamunison escript..."
gleam build 2>&1 | tail -1

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Collect all beam files
for dir in build/dev/erlang/*/ebin; do
  [ -d "$dir" ] && find "$dir" -name '*.beam' -exec cp {} "$TMPDIR" \; 2>/dev/null || true
done

rm -f "$TMPDIR"/gleamunison_test.beam "$TMPDIR"/gleeunit*.beam 2>/dev/null

# Compile and include raw Erlang genesis modules (m_*.erl)
for f in src/m_*.erl; do
  [ -f "$f" ] && erlc -o "$TMPDIR" "$f" 2>/dev/null || true
done

# Build a main wrapper module that escript can call
echo "  Beams: $(ls "$TMPDIR"/*.beam 2>/dev/null | wc -l)"

cd "$TMPDIR"
zip -q "${SCRIPT}.zip" *.beam
cd "$OLDPWD"

printf '#!/usr/bin/env escript\n%%! -noshell -sname gleamunison\n' > "${SCRIPT}"
cat "$TMPDIR/${SCRIPT}.zip" >> "${SCRIPT}"
chmod +x "${SCRIPT}"

echo "  Size: $(wc -c < "${SCRIPT}") bytes"
echo "  Run: ./${SCRIPT} server"
