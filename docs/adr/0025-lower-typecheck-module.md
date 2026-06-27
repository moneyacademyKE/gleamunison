# ADR 0025: Type Reference Lowering for Definition Elaboration

## Context
1. **Surface to Core Elaboration**: Elaboration compiles the surface language types (`TVar`, `TCon`, `TFun`, `TBuiltin`) into the AST core representation.
2. **Type Variables Binding**: Type variables (`TVar(String)`) in type definitions and ability signatures must be resolved to unique index-based identifiers (`TypeRefVar(LocalVar)`) during elaboration.
3. **Type Lowering Complexity**: Definition elaboration was growing large and complex, threatening to violate the strictly enforced 150 LOC limit on `elaborate.gleam` and `elab_def.gleam`.

## Decision
1. **Dedicated Lowering Module**: Extract the type lowering logic into a separate module `gleamunison/lower.gleam` under 50 LOC.
2. **Index Map Threading**: `lower_type_ref` threads a dictionary mapping type variable names (`String`) to unique sequential indices (`Int`), ensuring multiple references to the same variable name resolve to the same de Bruijn index.
3. **Core Mapping Helper**: Expose `type_ref_to_type` to map `TypeRef` constructors to core `Type` variants.

## Consequences
- Clean separation of concerns between definition structure validation and type reference mapping.
- Guarantees deterministic indexing of polymorphic parameters.
- Maintains modular structure under 150 LOC limits.
