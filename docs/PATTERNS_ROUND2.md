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

## 3. Hash-Partitioned Routing (Storage Pattern)
Dynamically compute the partition index from the first 4 bits of the cryptographic hash ref and route the operations to the corresponding table registered under that prefix:
```erlang
<<N:4, _/bitstring>> = Ref,
Tab = erlang:binary_to_atom(<<"gleamunison_dets_", Dir/binary, (hex(N))>>, utf8)
```

## 4. LRU Cache Loader Eviction (Loader Pattern)
Evict the least recently used modules in a loader sequence when exceeding constraints, purging them from the BEAM VM memory space:
```gleam
let #(keep, evict) = list.split(next_order, ld.max_size)
list.each(evict, fn(evicted_ref) {
  let evicted_mod = module_name_for(evicted_ref)
  let _ = unload_binary(evicted_mod)
})
```

## 5. Dynamic Stack Guards (Safety Pattern)
Enforce handler stack validation checks on pushing and popping operations to safeguard stack integrity and yield debuggable errors on stack corruption:
```erlang
validate_stack(List) when is_list(List) ->
    lists:foreach(fun(H) ->
        case validate_handler(H) of
            true -> ok;
            false -> error({corrupted_handler_stack, H})
        end
    end, List),
    ok.
```

## 6. Position-Tracked Tokenizer (Parsing Pattern)
Track coordinates (line & col offsets) dynamically during lexical passes and bind them to token instances:
```gleam
pub type TokenInfo {
  TokenInfo(token: Token, line: Int, col: Int)
}

## 7. Dry-Run Preflight Verification (Deployment Pattern)
Perform dry-run remote executions first to validate authentication, remote status, and credentials without side-effects or partial changes:
```sh
env -u GITHUB_TOKEN git push --dry-run
```
This isolates local keychain overrides and validates host network and authentication states safely.

```
