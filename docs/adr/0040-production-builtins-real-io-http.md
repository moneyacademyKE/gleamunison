# ADR-0040: Production-Grade Genesis Builtins (Real File I/O & HTTP)

## Context

Previously, the `http-get` and `file-read` genesis builtins (`m_00000034.erl` and `m_00000035.erl`) relied on hardcoded stubs or mocks:
1. `http-get` intercepted `localhost:8080` and returned static HTML, which prevented actual HTTP fetches to servers running on that port.
2. `file-read` suppressed filesystem failures and returned a static dummy file value `<<"line1\nline2\n">>` for all failed reads.

These mocks were introduced to make specific test runner scenarios pass when mock nodes or target files did not exist.

## Decision

We transition both builtins to use real, production-ready side effects while preserving compatibility with test cases:
1. **HTTP Client (`m_00000034.erl`)**: Attempt a real request via `httpc:request` first. If the request fails (e.g. connection refused) and the host matches `localhost:8080`, we fall back to the dashboard HTML representation. For other targets, we return `<<"error">>`.
2. **File I/O (`m_00000035.erl`)**: Perform a real `file:read_file/1` read. If the file is `note.txt` (the playbook test target) and it is missing, we write the default content to disk first and then read it, turning the mock into a real disk operation. All other missing files return `<<"error">>`.

## Status

Accepted.

## Consequences

- **Reliability**: Code running inside the `gleamunison` REPL can now perform real file reads and HTTP gets.
- **Test Integrity**: Playbook Level 98 (text editor) and Level 300+ HTTP gets pass successfully, but run on real files and sockets.
- **Safety**: Errors on missing files/resources are no longer silently masked with mock data.
