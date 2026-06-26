# Design Patterns — Roadmap

## 1. Closed DETS Resource Management (Resource Pattern)
To prevent lock contention and slow database repairs on startup, expose explicit lifecycle controls (`close` and `dets_delete_file`) on the storage adapter record instead of relying entirely on VM process exit hooks.
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

## 2. Recursive-Descent S-Expression Parsing (Parsing Pattern)
Implement parsing by first tokenizing the string input into flat list tokens, then using recursive-descent helper functions to build abstract expression trees (SExpr), and finally compiling those trees into the target AST structure (SurfaceTerm).
```gleam
pub fn parse_string(input: String) -> Result(SurfaceTerm, String) {
  case parse_sexpr(tokenize(input)) {
    Ok(#(sexpr, [])) -> sexpr_to_term(sexpr)
    Ok(#(_, _)) -> Error("Extra tokens after expression")
    Error(e) -> Error(e)
  }
}
```

## 3. Cryptographic SHA256 Identity (Identity Pattern)
Upgrade identity hashes to a fixed 32-byte boundary using Erlang's `crypto:hash(sha256, Bytes)`. Genesis stubs are padded to the 256-bit boundary using binary construction operators (`<<1:256>>`).
```gleam
pub fn builtin_int_add() -> DefinitionRef {
  Ref(Hash(<<1:256>>))
}
```
