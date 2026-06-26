# Design Patterns — Round 2

## 1. ETS-Captured Closures (State Pattern)
To implement a mutable storage adapter while preserving a pure interface, capture an ETS table reference inside the returned record of closures.
```gleam
pub fn inmemory() -> StorageAdapter {
  let tab = ffi_new()
  StorageAdapter(
    insert: fn(ref, bytes) { ffi_insert(tab, ref, bytes) },
    lookup: fn(ref) { ffi_lookup(tab, ref) },
    ...
  )
}
```

## 2. Stateless Multi-Param Substitution (Inference Pattern)
When type-checking functions of arity N applied to 1 argument, perform substitution on both the return type and the remaining parameters recursively:
```gleam
let ret2 = substitute(ret, target, replacement)
let rest2 = list.map(rest, substitute(_, target, replacement))
```
This reduces the function arity from N to N-1.
