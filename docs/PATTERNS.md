# Design Patterns

Patterns used throughout the gleamunison architecture.

---

## 1. Opaque type with module-private constructor

Used for types that must maintain invariants.

```gleam
pub opaque type Hash {
  Hash(contents: BitArray)
}
```

**Applied in:** `identity.gleam` (Hash), `codebase.gleam` (Codebase), `loader.gleam` (Loader)

---

## 2. Decomposed service

Split a service into sub-services with different concerns, orchestrated by a
thin coordinator.

```gleam
pub type Loader {
  Loader(
    compiler: Compiler,
    loaded: Set(DefinitionRef),
    failed: Dict(DefinitionRef, LoaderError),
  )
}
```

**Applied in:** `loader.gleam`

---

## 3. Three-result cache

A cache that distinguishes three states: known-good, known-bad, and unknown.

```gleam
pub type Loader {
  Loader(
    loaded: Set(DefinitionRef),              // known good
    failed: Dict(DefinitionRef, LoaderError), // known bad — don't retry
  )
}
```

**Applied in:** `loader.gleam`

---

## 4. Genesis builtins

Primitives are seeded into every codebase with pre-computed hashes from a
genesis block, rather than having a special "builtin" type.

**Applied in:** `elaborate.gleam`, `identity.gleam`

---

## 5. Dynamic scope stack with cleanup guarantee

Effects handlers are pushed onto a per-process stack. Cleanup is guaranteed
by try/catch in the Erlang runtime.

```
Push handler → Try computation → Catch → Pop handler → Re-raise
                                → Success → Pop handler → Return
```

**Applied in:** `gleamunison_effets.erl`

---

## 6. Positional operation indexing

Operations within an ability are identified by index (position into the
operations list), not by name.

```gleam
Do(ability: DefinitionRef, operation: LocalVar, args: List(Term))
```

**Applied in:** `ast.gleam`, `types.gleam`, `compile.gleam`

---

## 7. de Bruijn indices for binder identity

Local variables are identified by their distance from the binding site,
not by name.

```gleam
pub type LocalVar {
  Local(index: Int)
}
```

**Applied in:** `identity.gleam`, `elaborate.gleam`

---

## 8. Erlang source generation via recursive string building

Instead of generating Erlang abstract syntax trees (`compile:forms/2`),
generate Erlang source text via recursive string concatenation.

```gleam
fn emit_term(t: ast.Term) -> String {
  case t {
    ast.Int(n) -> int.to_string(n)
    ast.Apply(f, a) -> "(" <> emit_term(f) <> ")(" <> emit_term(a) <> ")"
    ast.Lambda(binder: Local(i), body:) -> "fun(V" <> int.to_string(i) <> ") -> " <> emit_term(body) <> " end"
    ...
  }
}
```

**Properties:** Debuggable output (readable Erlang), no abstract format
knowledge needed, simple to extend with new Term variants.

**Applied in:** `compile.gleam`

---

## 9. Catch-all FFI guard for OTP compatibility

Erlang FFI functions use a catch-all clause to handle type mismatches
between Gleam and Erlang representations:

```erlang
load_binary(Mod, Binary) ->
    ModuleAtom = case is_binary(Mod) of
        true -> binary_to_atom(Mod, utf8);
        false when is_list(Mod) -> list_to_atom(Mod);
        false -> binary_to_atom(iolist_to_binary(Mod), utf8)
    end.
```

**Properties:** Graceful handling of Gleam's binary string representation,
compatible with both `binary()` and `list()` module names.

**Applied in:** `gleamunison_ffi.erl`

---

## 10. OTP 29 compile file readback

OTP 29's `compile:file/2` with `return` option returns `{ok, Mod, []}`
instead of `{ok, Mod, Binary}` or `{ok, Mod}`. The empty list means the
binary was written to disk. Pattern:

```erlang
case compile:file(File, [{outdir, Dir}, return]) of
    {ok, _Mod} -> read_beam_file(File);          %% pre-OTP 29
    {ok, _Mod, Bin} when is_binary(Bin) -> Bin;  %% binary returned
    {ok, _Mod, _} -> read_beam_file(File);        %% OTP 29: {ok, Mod, []}
    ...
end
```

**Applied in:** `gleamunison_ffi.erl`

---

## 11. escript binary packaging

Create a standalone escript by prepending the shebang line to a zip
archive of all beam files:

```sh
zip gleamunison.zip *.beam
printf '#!/usr/bin/env escript\n%%! -noshell -sname gleamunison\n' |
  cat - gleamunison.zip > gleamunison
chmod +x gleamunison
```

The escript runtime finds the zip by scanning for `PK` magic bytes.

**Applied in:** `build_escript.sh`

---

## 12. StorageAdapter function-record pattern

Pluggable backends via function-record:

```gleam
pub type StorageAdapter {
  StorageAdapter(
    insert: fn(DefinitionRef, BitArray) -> Result(Nil, StorageError),
    lookup: fn(DefinitionRef) -> Result(Option(BitArray), StorageError),
    list_refs: fn() -> Result(List(DefinitionRef), StorageError),
  )
}
```

**Applied in:** `codebase.gleam`

---

## 13. Lightweight type substitution
Perform lightweight, state-free substitution on polymorphic type parameters during application:
```gleam
fn substitute(typ: ast.Type, target_index: Int, replacement: ast.Type) -> ast.Type
```

**Applied in:** `inference.gleam`

---

## 14. LOC-capped Module Decomposition
Orchestrate complex logic (like elaboration) by splitting it into specialized helper modules, keeping each strictly <100 LOC and avoiding cycles via functional combinators.

**Applied in:** `elaborate.gleam`, `elab_pat.gleam`, `elab_term.gleam`

---

## 15. Alpha-Equivalence Type Normalization

Re-index all free type variables sequentially starting at 0 based on depth-first discovery order before executing a structural equality check.

**Applied in:** `typecheck.gleam`

---

## 16. Stateful Type Variable Lowering

Thread a stateful mapping of string names to sequential integers during type lowering, ensuring multi-variable parameters resolve to unique de Bruijn indices.

**Applied in:** `lower.gleam`, `elab_def.gleam`

---

## 17. Dynamic Purging / Redefinition Lifecycle

To support interactive redefinitions in the REPL, the code server must unload existing compiled modules to prevent collision errors. This is handled by force-unloading the existing BEAM module before compiling and loading the new binary:
```gleam
let _ = unload_binary(mod_name)
// Compile and load the new binary...
```

**Applied in:** `repl.gleam`

---

## 18. Process-Isolated State FFI

Leverage process-scoped storage (Erlang process dictionary) inside external FFI functions to provide mutable state to functional code. This isolates state strictly within the active Erlang process, ensuring concurrency safety.

**Applied in:** `gleamunison_ffi.erl`, `http.gleam`

---

## 19. Genesis Module Escript Packaging

Build process compiles all genesis modules (`src/m_*.erl`) and includes their BEAM files inside the escript archive zip. This ensures that the standalone escript can evaluate all levels without needing external source compilation or path resolution at runtime.

**Applied in:** `build_escript.sh`

---

## 20. Index Map Threading for lowering

Threading type variable translation dictionaries when transforming AST nodes guarantees unique variable matching.

**Applied in:** `lower.gleam`

---

## 21. Structured Recursive Hash Serialization

Determining cryptographic definition hashes by canonical recursive traversal over AST structures, rather than fallback string inspections.

**Applied in:** `codebase.gleam`

---

## 22. Named public ETS tables for global mutations

Using public named ETS tables for global mutable count tracking, preserving process isolation while avoiding persistent_term GC halts.

**Applied in:** `gleamunison_http.erl`



