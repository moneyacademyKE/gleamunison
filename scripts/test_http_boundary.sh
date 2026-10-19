#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/bin:/Users/moe/.local/bin:$PATH
port=18105
GLEAMUNISON_HTTP_TOKEN= erl -pa build/dev/erlang/*/ebin -noshell -eval \
  "spawn(fun() -> gleamunison_http:start_server($port) end), receive after 15000 -> halt(1) end." &
server=$!
cleanup() { kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
for path in /static//etc/passwd /static/%2e%2e/%2e%2e/gleam.toml /static/..%5cgleam.toml; do
  code=$(curl --silent --show-error --path-as-is --max-time 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port$path")
  printf '%s => %s\n' "$path" "$code"
  case "$code" in 403|404) ;; *) exit 1 ;; esac
done
code=$(curl --silent --show-error --max-time 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/static/js/dashboard.js")
printf '/static/js/dashboard.js => %s\n' "$code"
test "$code" = 200
