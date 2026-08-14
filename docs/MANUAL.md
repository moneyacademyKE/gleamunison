# Gleamunison Reference Manual

Gleamunison is a content-addressed runtime with algebraic effects running on the Erlang BEAM, implemented in Gleam.

---

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
./build_escript.sh && ./gleamunison_escript
```

### 2.1 S-Expression Syntax
Gleamunison supports text input via a recursive-descent S-expression parser:
- Literals: `42`, `"hello"`
- Symbols: `x`, `y`
- Lists: `(1 2 3)`
- Scoped variables: `(let x 42 (add x 1))`
- Lambdas: `(lam x (add x 1))`

---

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

### 4.2 Storage Backends (DETS, ETS, Mnesia)
Persistence is managed via the `StorageAdapter` record, which supports disk-based DETS, in-memory ETS, and distributed Mnesia:
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

## 5. Pull-based Node Syncing & Network Transport
1. **Advertise**: Exchange lists of local hashes (`sync_send_refs`).
2. **Calculate Diff**: Peer computes missing hashes (`sync_receive_diff`).
3. **Request & Persist**: Request missing definition binaries (`sync_request_defs`) and insert them into local storage (`codebase.insert_raw`).
4. **Transport**: Supported via native Erlang Distribution (for `@` cluster peers) or framed TCP protocol (`gleamunison_tcp_sync.erl` with 1MB payload limits and safe decoding).

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

### 6.3 Supervision Trees
- **OTP integration**: `gleamunison_sup` manages worker process lifecycles with standard Erlang supervisor behavior.
- **Link isolation**: Supervisor processes are spawned in dedicated workers to prevent cascading termination during testing.

---

## 7. Standard Library (v1.1.0)

### 7.1 HTTP Client
```gleam
import gleamunison/http_client

let assert Ok(HttpResponse(status: 200, body: b)) =
  http_client.get("https://api.example.com/data")
```

### 7.2 JSON
```gleam
import gleamunison/json

let encoded = json.encode(term)
let decoded = json.decode(binary)
```

### 7.3 DateTime
```gleam
import gleamunison/datetime

let now = datetime.now()
let iso = datetime.to_iso8601(now)
```

### 7.4 Filepath
```gleam
import gleamunison/filepath

let p = filepath.from_string("/home/user/file.txt")
let ext = filepath.extension(p)
```

### 7.5 Crypto
```gleam
import gleamunison/crypto

let digest = crypto.hash(crypto.Sha256, data)
let key = crypto.random_bytes(32)
```

### 7.6 Template
```gleam
import gleamunison/template

let html = template.render("Hello {{name}}!", [#("name", "World")])
```

### 7.7 Structured Logging
```gleam
import gleamunison/log

log.info("Server started")
log.error_context("Connection failed", dict.from_list([#("port", "8080")]))
```

### 7.8 Configuration
```gleam
import gleamunison/config

let cfg = config.load()
let port = config.get_int(cfg, "PORT") |> result.unwrap(8080)
```

### 7.9 Health Checks
```gleam
import gleamunison/health

case health.run_all() {
  Healthy(msg) -> log.info(msg)
  Unhealthy(err) -> log.error(err)
}
```

### 7.10 Metrics
```gleam
import gleamunison/metrics

metrics.counter("requests", 1)
metrics.gauge("memory_mb", 256.0)
```

---

## 8. Native Content-Addressed Datalog Engine (`gleamunison_datalog/`)

Pure S-expression immutable database engine running entirely in GleamUnison user-space (ADR-0062):
- **EAVT / AVET Indexing**: Dual persistent map indexes mapping `[Entity -> Attr -> Values]` and `[Attr -> Value -> Entities]`.
- **Pure Transactions**: Functional assertions, retractions, and Compare-and-Swap:
```lisp
(let db1 (db-assert db-empty 1 "name" "Alice")
  (let db2 (db-assert db1 1 "age" 30)
    (db-query db2 (list (pair (q-var "?e") (pair "name" (q-val "Alice")))))))
```
- **Temporal & Historical Queries**: `db-history`, `db-as-of`, `db-since`, `db-diff`.
- **Deductive Logic Rules**: Fixpoint recursive rule solver for graph reachability and transitive relationships.
- **Graph & Search**: BFS, DFS, shortest path finding, PageRank, k-NN cosine vector similarity, and BM25 document ranking.
- **Actor Model Transactor**: Concurrency and serializability via Erlang actors (`spawn`, `send`, `recv`).

---

## 9. Web Dashboard & Tracing

```sh
./gleamunison_escript server   # Starts on http://127.0.0.1:8080
```

The embedded HTTP dashboard provides:
- **Node status**: Running processes, loaded module count, synced hashes.
- **Trace Inspector**: DETS-backed HTTP request capture, SSE push, `/api/traces` endpoint.
- **Mnesia table keys**: Browse all stored content-addressed definitions.

---

## 10. REPL Features

### 10.1 Multi-line Input
The REPL supports multi-line expressions, accumulating lines until parentheses balance:
```
> (define factorial
|   (lam n
|     (if (eq? n 0) 1
|       (mul n (factorial (sub n 1))))))
```

### 10.2 Spelling Suggestions
On name resolution errors, the REPL provides spelling suggestions using depth-limited Levenshtein distance.

### 10.3 Module Purging
Redefining a name in the REPL automatically purges old BEAM modules (`code:delete/1` + `code:purge/1`) before loading new compilations.

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

---

## 13. Library Integration Guide
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
