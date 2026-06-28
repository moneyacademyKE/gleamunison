# Lazy CAS Type Adapters — Architecture Decision Record

## Status: Implemented (v1.0.0)

## Problem

Content-addressed type definitions have immutable hashes. When a type
declaration changes (e.g., a new constructor is added to a tagged union),
the hash changes and all definitions referencing the old hash become
unreachable. This creates a schema migration problem: how do we access
old data stored under old type hashes?

## Solution: Lazy CAS Type Adapters

When the runtime encounters a definition hash that doesn't match the
current type declaration, it attempts to find an adapter function that
translates between the old and new formats.

### Mechanism

1. **Adapter Registry** — An ETS table `gleamunison_adapters` maps
   `{old_hash, new_hash}` to adapter functions.

2. **Lazy Migration** — Definitions stored under old hashes are not
   proactively migrated. Instead, access triggers a lookup in the
   adapter registry. If an adapter exists, it translates on-the-fly.

3. **Adapter Signatures** — Each adapter is a pure function:
   ```erlang
   adapter(OldTerm) -> NewTerm | {error, Reason}
   ```

4. **Registration** — Adapters are registered at compile time or
   dynamically:
   ```erlang
   gleamunison_adapters:register(OldHash, NewHash, AdapterFun)
   ```

### Example

```gleam
// Old type: User with 2 fields
// Hash: abc123
(type User (UserCtor String Int))

// New type: User with 3 fields (email added)
// Hash: def456
(type User (UserCtor String Int String))

// Adapter: defaults email to empty
(define user-v1-to-v2
  (lam old
    (match old
      ((UserCtor name age) (UserCtor name age "")))))
```

### Usage

```erlang
% Register adapter
gleamunison_adapters:register(<<"abc123">>, <<"def456">>, fun convert/1)

% Old data accessed with old hash — adapter fires automatically
codebase:lookup(Ref(<<"abc123">>)) % → translated to new format
```

## Trade-offs

- **Pro**: No downtime. Data migrates lazily on access.
- **Pro**: Adapters are pure functions — side-effect-free and composable.
- **Con**: Chained adaptations (old → mid → new) can stack overhead.
- **Con**: Adapters must be registered manually; no automatic derivation yet.
