# Gleamunison Reference Manual

Gleamunison is a content-addressed runtime with algebraic effects running on the Erlang BEAM, implemented in Gleam.

---

## 10. Standard Library (v1.1.0)

### 10.1 HTTP Client
```gleam
import gleamunison/http_client

let assert Ok(HttpResponse(status: 200, body: b)) =
  http_client.get("https://api.example.com/data")
```

### 10.2 JSON
```gleam
import gleamunison/json

let encoded = json.encode(term)
let decoded = json.decode(binary)
```

### 10.3 DateTime
```gleam
import gleamunison/datetime

let now = datetime.now()
let iso = datetime.to_iso8601(now)
```

### 10.4 Filepath
```gleam
import gleamunison/filepath

let p = filepath.from_string("/home/user/file.txt")
let ext = filepath.extension(p)  // "txt"
```

### 10.5 Crypto
```gleam
import gleamunison/crypto

let digest = crypto.hash(crypto.Sha256, data)
let key = crypto.random_bytes(32)
```

### 10.6 Template
```gleam
import gleamunison/template

let html = template.render("Hello {{name}}!", [#("name", "World")])
```

### 10.7 Structured Logging
```gleam
import gleamunison/log

log.info("Server started")
log.error_context("Connection failed", dict.from_list([#("port", "8080")]))
```

### 10.8 Configuration
```gleam
import gleamunison/config

let cfg = config.load()
let port = config.get_int(cfg, "PORT") |> result.unwrap(8080)
```

### 10.9 Health Checks
```gleam
import gleamunison/health

case health.run_all() {
  Healthy(msg) -> log.info(msg)
  Unhealthy(err) -> log.error(err)
}
```

### 10.10 Metrics
```gleam
import gleamunison/metrics

metrics.counter("requests", 1)
metrics.gauge("memory_mb", 256.0)
```

---

## 11. Property-Based Testing (v1.1.0)
```erlang
% From Erlang FFI:
gleamunison_property:check(Generator, Property).

% Example: all reversed lists have same length as original
IntListGen = gleamunison_property:list_gen(gleamunison_property:int_gen()),
gleamunison_property:check(IntListGen, fun(L) ->
    length(L) =:= length(lists:reverse(L))
end).
```

---

## 12. Error Code Reference (v1.1.0)

| Code | Description |
|---|---|
| `[P001]` | Unexpected end of input — missing closing parenthesis |
| `[P002]` | Empty expression — type an S-expression |
| `[P003]` | Unclosed parentheses — every `(` needs `)` |
| `[P004]` | General parse error with line/column |
| `[E001]` | Undefined variable — with spelling suggestions |
| `[E002]` | Unknown operation in ability |
| `[E003]` | Undefined ability declaration |
| `[E004]` | Type error — could not type-check |
| `[E005]` | Unsupported type reference |

## 1. Core Philosophy & Concepts

### 1.1 Content-Addressability
Definitions (terms, type declarations, abilities) are identified by the **SHA256 hash** of their serialized AST structure.
- **Identity = Hash**: Unchanged implementations retain identical hashes.
- **Decoupled Names**: Names are merely metadata mappings pointing to hashes.
- **No Builds**: Once compiled to BEAM bytecode, a definition is immutable and cached.

### 1.2 Algebraic Effects (Abilities)
Side effects and environment operations are declared as **Abilities**.
- **Resumable Continuations**: triggers via `Do` yield to the nearest stack handler.
- **Process Dictionary**: Handlers are thread-locally scoped in process dictionaries.

---

## 2. Command Line Interface (CLI) & S-Expression Parser
The standalone binary runs with zero dependencies on any Erlang/OTP environment.
```sh
./build_escript.sh && ./gleamunison
```

### 2.1 S-Expression Syntax
Gleamunison supports text input via a recursive-descent S-expression parser:
- Literals: `42`, `"hello"`
- Symbols: `x`, `y`
- Lists: `(1 2 3)`
- Scoped variables: `(let x 42 (add x 1))`
- Lambdas: `(lam x (add x 1))`

## 3. Language AST & Definition Model
Definitions exist in three forms, represented in `ast.gleam`:
```gleam
pub type Definition {
  TermDef(term: Term, typ: Type)
  TypeDef(TypeDeclaration)
  AbilityDecl(AbilityDeclaration)
}
```
AST defines 15 term constructors: literals, homogenous lists, variables, function applications, lambdas, let bindings, case matching, handlers, holes, and use expressions.

### 3.1 Guard Clauses (v1.1.0)
Match cases support guard clauses for conditional pattern matching:
```
(match x ((n (< n 5)) (println "small"))
          ((n (> n 10)) (println "large"))
          (_ (println "medium")))
```
Guards are restricted to BEAM-guard-safe operations and compile to Erlang `when` clauses.

### 3.2 First-Class Typed Holes (v1.1.0)
Incomplete expressions can use `?` as a placeholder:
```
(lam x ?)
```
Holes compile to `erlang:error({hole, incomplete_expression})` at runtime, enabling live fill-and-resume workflows.

### 3.3 `use` Expression (v1.1.0)
Monadic sugar that desugars to lambda-passing:
```
(use x <- (some-monad 42) body)
;; equivalently: ((some-monad 42) (lam x body))
```

### 3.4 Labeled Arguments (v1.1.0)
Curried lambdas with named parameters and defaults:
```
(fn* ((host "localhost") (port 8080)) (connect host port))
;; desugars to: (lam host (lam port (connect host port))) with defaults
```

### 3.5 Type Aliases (v1.1.0)
Named type references with visibility control:
```
(type alias Id Int)         ;; private alias
(pub type alias UserId Int) ;; public alias
```

---

## 4. Hashing & Codebase Persistence

### 4.1 Verification on Insert
Insertions verify that `hash_of_definition(def)` matches the target `DefinitionRef`.

### 4.2 Storage Backends (DETS)
Persistence is managed via the `StorageAdapter` record, which supports disk-based DETS:
```gleam
pub type StorageAdapter {
  StorageAdapter(
    insert: fn(DefinitionRef, BitArray) -> Result(Nil, StorageError),
    lookup: fn(DefinitionRef) -> Result(Option(BitArray), StorageError),
    list_refs: fn() -> Result(List(DefinitionRef), StorageError),
    close: fn() -> Result(Nil, StorageError),
  )
}
```

---

## 5. Pull-based Node Syncing
1. **Advertise**: Exchange lists of local hashes (`sync_send_refs`).
2. **Calculate Diff**: Peer computes missing hashes (`sync_receive_diff`).
3. **Request & Persist**: Request missing definition binaries (`sync_request_defs`) and insert them into local storage (`codebase.insert_raw`).

---

## 6. Concurrency & Distributed Features

### 6.1 Concurrency Primitives
Gleamunison exposes Erlang's native process model through typed abilities:
- **spawn**: `(do Remote spawn (lam () body))` — creates a new process executing `body`. Returns a `Task`.
- **send**: `(do Remote send task value)` — sends `value` to the process identified by `task`.
- **recv**: `(do Remote recv)` — blocks until a message arrives, returns the received value.
- **self**: Returns the current process identifier.
- **sleep**: `(do Remote sleep ms)` — suspends the current process for `ms` milliseconds.
- **now**: Returns the current system time.

### 6.2 Distributed Compute
- **Remote ability**: `forkAt` ships a computation to a remote node by content-hash, `await` blocks on its result, `here` returns the current node location.
- **Location transparency**: `Location` wraps Erlang node names (e.g., `node@host`). Computations are location-agnostic until executed.
- **Code shipping**: Uses the pull-based sync protocol to verify and transfer content-addressed BEAM modules to remote nodes.
- **Serializable continuations**: Erlang's `term_to_binary/1` serializes closures; identical module hashes across nodes guarantee correct deserialization.

### 6.3 Mnesia Storage
- **Replicated codebase**: The Mnesia storage adapter provides ACID transactions and automatic replication across clustered nodes.
- **No external database**: Pure Erlang/OTP, no PostgreSQL or SQLite dependency.

### 6.4 Supervision Trees
- **OTP integration**: `gleamunison_sup` manages worker process lifecycles with standard Erlang supervisor behavior.
- **Link isolation**: Supervisor processes are spawned in dedicated workers to prevent cascading termination during testing.

---

## 7. Web Dashboard

```sh
./gleamunison_escript server   # Starts on http://localhost:8080
```

The embedded HTTP dashboard provides:
- **Node status**: Running processes, loaded module count, synced hashes.
- **Mnesia table keys**: Browse all stored content-addressed definitions.
- **Real-time updates**: ETS-backed counters with zero garbage collection overhead.

---

## 8. REPL Features

### 8.1 Multi-line Input
The REPL supports multi-line expressions. It tracks bracket depth and accumulates lines until parentheses balance:
```
> (define factorial
|   (lam n
|     (if (eq n 0) 1
|       (multiply n (factorial (subtract n 1))))))
```

### 8.2 Spelling Suggestions
On name resolution errors, the REPL provides spelling suggestions using depth-limited Levenshtein distance against all active environment definitions.

### 8.3 Module Purging
Redefining a name in the REPL automatically purges the old BEAM module (`code:delete/1` + `code:purge/1`) before loading the new compilation, preventing code server conflicts.

---

## 9. Library Integration Guide
Host applications must target Erlang (`--target erlang`) and use OTP 29+.
```gleam
import gleamunison/ast
import gleamunison/codebase
import gleamunison/loader

pub fn run_plugin(def: ast.Definition) {
  let cb = codebase.empty()
  let ld = loader.new_loader()
  let ref = codebase.hash_of_definition(def)
  case loader.ensure_loaded(ld, ref, def) {
    Ok(ld_updated) -> Ok(ld_updated)
    Error(err) -> Error(err)
  }
}
```
