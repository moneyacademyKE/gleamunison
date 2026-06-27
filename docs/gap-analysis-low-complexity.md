# Gap Analysis: High-Utility Low-Complexity Builtins

> **Status: IMPLEMENTED (v0.8.0).** All recommended builtins were implemented: Math ability (numeric operations), Show ability (display/formatting), JSON parse (`json-parse` via gleam_json), HTTP get (`http-get` via gleamunison http client), and File read (`file-read` via simplifile). See ADR-0030 (Curried BEAM List Fold FFI) and ADR-0031 (Modular FFI Decomposition) for implementation details. This document is retained as historical record of the analysis that informed the implementation.

A Rich Hickey-style Gap Analysis comparing the prototype stubs for experimental builtins and capabilities (Levels 89, 90, 96, 97, 98) with actual production-grade FFI implementations on the BEAM.

---

## 1. Feature Set Differences & Gap Analysis

| Feature / Builtin | Specification / Expected Goal | Current Placeholder State | Proposed FFI Implementation | Benefit & Trade-off |
|---|---|---|---|---|
| **`Math` Ability (Level 89)** | Multi-operation effect handler for `add`, `sub`, `mul` arithmetic dispatch. | Mocked via placeholder cases to prevent REPL exceptions. | Bootstrap `Math` in `repl.gleam` and implement a process-dictionary-based math handler stack in `gleamunison_repl_ffi.erl`. | **Benefit:** Validates multi-op dispatch without custom handlers compiled on the fly. <br>**Trade-off:** Minimal overhead in process dictionary state. |
| **`Show` Ability (Level 90)** | Parametric operation `show : (a) -> Text` rendering any term. | Mocked via placeholder cases. | Bootstrap `Show` and map its operation to a general-purpose FFI call utilizing Erlang's native `io_lib:format("~p", [Val])`. | **Benefit:** Allows debugging of any data structure in the REPL. <br>**Trade-off:** Output string reflects BEAM representation rather than native AST. |
| **JSON Parse (Level 96)** | `(json-parse json-str)` parsing nested JSON to S-expression structures. | Bypassed. | Builtin `json-parse` calling Erlang OTP 27+ native `json:decode/1` and mapping resulting maps/lists to Lisp structures. | **Benefit:** High utility for external data exchange. <br>**Trade-off:** JSON parsing speed is native BEAM speed. |
| **HTTP Get (Level 97)** | `(http-get url)` returning response body text. | Bypassed. | Builtin FFI mapping to Erlang's standard `:httpc` module request client. | **Benefit:** Enables direct external network requests. <br>**Trade-off:** Synchronous blocking call. |
| **File Read (Level 98)** | `(file-read path)` returning file content. | Bypassed. | Builtin FFI calling Erlang's native `file:read_file/1`. | **Benefit:** Access to filesystem data. <br>**Trade-off:** Blocking file I/O operations. |

---

## 2. Complexity vs. Utility

| Element | Complexity | Utility | Actionable Recommendation |
|---|---|---|---|
| **Erlang native `json:decode` mapping** | Low (30 lines of Erlang) | High | **Implement**: Maps natively to nested FFI list structures. |
| **Erlang `:httpc` client wrapper** | Low (10 lines of Erlang) | High | **Implement**: Enables networked Unison nodes. |
| **Erlang `file:read_file` FFI** | Low (5 lines of Erlang) | High | **Implement**: Unlocks file access for scripting. |
| **Dynamic `Math`/`Show` Effect stacks** | Low (20 lines of Erlang/Gleam) | High | **Implement**: Certifies parametric effect resolution. |

---

## 3. Actionable implementation Plan

We will proceed with implementing these five capabilities:
1. Register `Math` and `Show` abilities inside `repl.gleam`.
2. Add FFI handlers `MathHandler` and `ShowHandler` composed in the evaluation environment.
3. Write FFI bindings for `json_parse`, `http_get`, and `file_read` in `m_00000033.erl`, `m_00000034.erl`, `m_00000035.erl` respectively, mapping to the appropriate genesis hashes.
4. Remove these levels from `make_placeholders.clj` and run tests.
