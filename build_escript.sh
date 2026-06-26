#!/bin/bash
# Build a standalone escript for gleamunison.
# Produces a single file that runs with just Erlang/OTP installed.
# Usage: ./build_escript.sh && ./gleamunison
set -e
cd "$(dirname "$0")"

echo "Building gleamunison escript..."
gleam build 2>&1 | tail -1

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Collect all beam files
for dir in build/dev/erlang/gleamunison/ebin build/dev/erlang/gleam_stdlib/ebin; do
  [ -d "$dir" ] && find "$dir" -name '*.beam' -exec cp {} "$TMPDIR" \; 2>/dev/null || true
done
rm -f "$TMPDIR"/gleamunison_test.beam "$TMPDIR"/gleeunit*.beam 2>/dev/null

# Build a main wrapper module that escript can call
cat > "$TMPDIR"/main.erl << 'EOF'
-module(main).
-export([main/1]).
main(Args) -> gleamunison:main(Args).
EOF
erlc -o "$TMPDIR" "$TMPDIR"/main.erl 2>&1

echo "  Beams: $(ls "$TMPDIR"/*.beam 2>/dev/null | wc -l)"

cd "$TMPDIR"
zip -q gleamunison.zip *.beam
cd "$OLDPWD"

printf '#!/usr/bin/env escript\n%%! -noshell -sname gleamunison -main main\n' > gleamunison
cat "$TMPDIR/gleamunison.zip" >> gleamunison
chmod +x gleamunison

echo "  Size: $(wc -c < gleamunison) bytes"
echo "  Run: ./gleamunison"
