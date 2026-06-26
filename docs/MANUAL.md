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
./build_escript.sh && ./gleamunison
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
AST defines 12 term constructors: literals, homogenous lists, variables, function applications, lambdas, let bindings, case matching, and handlers.

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

## 6. Library Integration Guide
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
