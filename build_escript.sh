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
app_beam_list=$(mktemp)
trap 'rm -rf "$build_dir" "$app_beam_list"' EXIT

printf 'Building gleamunison escript...\n'
"$GLEAM_BIN" build

shopt -s nullglob
# Record exactly which beams belong to the gleamunison application at copy
# time; the regenerated .app's modules list is built from this, never from
# a name-prefix guess that rots when dependencies change their modules.
for dir in build/dev/erlang/*/ebin; do
  if [[ -d "$dir" ]]; then
    find "$dir" -type f -name '*.beam' -exec cp {} "$build_dir"/ \;
    if [[ "$dir" == "build/dev/erlang/gleamunison/ebin" ]]; then
      (cd "$dir" && ls *.beam) >> "$app_beam_list"
    fi
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

# The compiler-generated .app is a dev-mode file: it lists dev-only
# applications (birdie, gleeunit) and every *_test module. The release
# artifact carries a regenerated .app whose applications are exactly
# gleam.toml [dependencies] plus the OTP base, and whose modules are exactly
# the beams this script packages. Declared = contained.
for source in src/m_*.erl; do
  [[ -f "$source" ]] || continue
  "$ERLC_BIN" -o "$build_dir" "$source"
done

version=$(sed -n 's/^version = "\([^"]*\)"/\1/p' gleam.toml)
description=$(sed -n 's/^description = "\([^"]*\)"/\1/p' gleam.toml)
runtime_deps=$(awk '/^\[dependencies\]/{f=1;next} /^\[/{f=0} f && /^[a-z]/{print $1}' gleam.toml)

app_modules=""
module_names=$(
  {
    while IFS= read -r beamfile; do
      [[ -f "$build_dir/$beamfile" ]] && printf '%s\n' "${beamfile%.beam}"
    done < "$app_beam_list"
    for source in src/m_*.erl; do
      [[ -f "$source" ]] || continue
      m=$(basename "$source" .erl)
      [[ -f "$build_dir/$m.beam" ]] && printf '%s\n' "$m"
    done
  } | sort -u
)
for m in $module_names; do
  app_modules="$app_modules '$m',"
done
app_modules=${app_modules%,}

dep_apps=""
for dep in $runtime_deps; do
  dep_apps="$dep_apps, $dep"
done

cat > "$build_dir/gleamunison.app" <<EOF
{application, gleamunison, [
    {vsn, "$version"},
    {applications, [kernel, stdlib, crypto$dep_apps]},
    {description, "$description"},
    {modules, [$app_modules]}
]}.
EOF

beam_count=$(find "$build_dir" -maxdepth 1 -type f -name '*.beam' | wc -l | tr -d ' ')
if [[ "$beam_count" -eq 0 ]]; then
  echo "error: build produced no BEAM files" >&2
  exit 1
fi
printf '  Beams: %s\n' "$beam_count"

zip_path="$build_dir/$SCRIPT.zip"
(
  cd "$build_dir"
  # Reproducibility gate: zip stores file mtimes, and this temp dir's mtimes
  # are "now". Pin every entry to the epoch so two clean builds of the same
  # source produce byte-identical archives. Glob order is already sorted.
  find . -type f -exec touch -t 198001010000.00 {} +
  TZ=UTC0 zip -q -X "$zip_path" ./*.beam ./gleamunison.app
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
