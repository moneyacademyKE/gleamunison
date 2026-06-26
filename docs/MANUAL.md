# Gleamunison Reference Manual

Gleamunison is a content-addressed language runtime with algebraic effects running on the Erlang BEAM, implemented in Gleam.

---

## 1. Core Philosophy & Concepts

### 1.1 Content-Addressability
Unlike traditional programming languages where code is identified by names, directories, or package versions, Gleamunison identifies all definitions (terms, type declarations, abilities) by the **cryptographic-like hash** of their serialized Abstract Syntax Tree (AST) structure.
- **Identity = Hash**: If the implementation of a function does not change, its hash remains identical.
- **Decoupled Names**: Names are merely metadata mappings (pointers) pointing to hashes. Renaming a function has zero runtime compile/dependency cost.
- **No Builds**: Once type-checked and compiled to BEAM bytecode, a definition is immutable and cached forever.

### 1.2 Algebraic Effects (Abilities)
Side effects and environment operations are declared as **Abilities**. Functions requiring abilities are typed with effect requirements.
- **Resumable Continuations**: When an ability operation is triggered via `Do`, computation yields to the nearest handler in the call stack.
- **Process Dictionary Stack**: Effect handlers are dynamically scoped and maintained on a thread-local stack in the Erlang process dictionary.

---

## 2. Command Line Interface (CLI)

The compiled standalone binary `gleamunison` runs with zero dependencies on any machine with Erlang/OTP installed.

```sh
./gleamunison [args]
```

### Build & Package Standalone Binary
To compile all Gleam code, Erlang FFI files, and stdlib dependencies into a single executable escript:
```sh
./build_escript.sh
```

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

### 3.1 Term Types
The AST defines 12 core term constructors:
- `Int(Int)` / `Float(Float)` / `Text(BitArray)`: Basic literal expressions.
- `List(List(Term))`: Homogeneous lists.
- `LocalVarRef(LocalVar)`: Local variable references bound by de Bruijn indices.
- `RefTo(DefinitionRef)`: Content-addressed pointer to another definition.
- `Apply(function: Term, arg: Term)`: Curried function application.
- `Lambda(binder: LocalVar, body: Term)`: Anonymous function binders.
- `Let(binder: LocalVar, value: Term, body: Term)`: Scoped variable declarations.
- `Match(scrutinee: Term, cases: List(Case))`: Scoped pattern matches.
- `Do(ability: DefinitionRef, operation: LocalVar, args: List(Term))`: Triggers an algebraic operation.
- `Handle(computation: Term, handler: Term, ability: DefinitionRef)`: Binds an effect handler around a computation.

---

## 4. Algebraic Effects Tutorial

### 4.1 Declaring an Ability
To define a new capability, declare it as an `AbilityDeclaration` with operations:

```gleam
let read_op = ast.Operation(
  name: Local(0),
  inputs: [ast.TypeRefBuiltin(ast.IntType)],
  output: ast.TypeRefBuiltin(ast.TextType)
)
let ability = ast.AbilityDecl(
  ast.AbilityDeclaration(name: Local(0), operations: [read_op])
)
```

### 4.2 Handling Abilities
Handlers are functions (or maps of functions) executed when operations yield.
```erlang
% erlang handler function format
Handler = fun(Args, Cont) -> 
    [Arg1] = Args,
    % resume computation with result
    Cont(<<"read result">>)
end.
```
Compiled `Handle` terms push this handler onto the execution stack:
```
gleamunison_effets:handle_comp({AbilityKey, Handler}, Thunk)
```

---

## 5. Hashing & Codebase Persistence

### 5.1 Verification on Insert
Every insertion into the codebase verifies that `hash_of_definition(def)` matches the target `DefinitionRef`. If the computed hash does not match, the insertion fails with `HashMismatch`.

### 5.2 Storage Backends
By default, Gleamunison uses the `inmemory` adapter. Custom storage backends must implement the `StorageAdapter` record:
```gleam
pub type StorageAdapter {
  StorageAdapter(
    insert: fn(DefinitionRef, BitArray) -> Result(Nil, StorageError),
    lookup: fn(DefinitionRef) -> Result(Option(BitArray), StorageError),
    list_refs: fn() -> Result(List(DefinitionRef), StorageError),
  )
}
```

---

## 6. Pull-based Node Syncing

Gleamunison uses a pull-based distributed protocol to sync definitions between nodes:

1. **Advertise**: Connect to peer and exchange lists of local hashes (`sync_send_refs`).
2. **Calculate Diff**: Peer computes the diff of hashes missing locally (`sync_receive_diff`).
3. **Request & Persist**: Request missing definition binaries (`sync_request_defs`) and insert them into local storage (`codebase.insert_raw`).
