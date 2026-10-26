# Genesis Modules

**Checked-in Erlang genesis implementations** (`src/m_*.erl`), including the
numbered builtins and the `m_state` helper. The source directory and artifact
contract are the inventory; this page explains their role and naming scheme.

## What Are Genesis Modules?

Genesis modules are the gleamunison equivalent of language primitives. Following ADR-0003 (Genesis Builtins), there is no special "builtin" type or namespace. Every primitive operation has a content-addressed hash and a corresponding BEAM module that implements it.

Each genesis module:
- Is named `m_<hex>` where the hex digits come from the last 8 characters of the module's SHA256 hash
- Exports a single `$eval/0` function that returns the primitive value (usually a curried closure)
- Is written in raw Erlang (not Gleam) because they bootstrap the runtime — they must compile before the Gleam compiler itself is running
- Is compiled via `erlc` and bundled into the standalone escript (ADR-0013, Learning #23)

## Genesis Module Catalog

### Arithmetic & Comparison (`m_00000001`, `m_0000000b`–`m_00000014`)

| Module | Operation | Signature |
|---|---|---|
| `m_00000001` | `add` | `A → B → A + B` |
| `m_0000000b` | `sub` | `A → B → A - B` |
| `m_0000000c` | `mul` | `A → B → A * B` |
| `m_0000000d` | `div` | `A → B → A div B` |
| `m_0000000e` | `rem` | `A → B → A rem B` |
| `m_0000000f` | `eq` | `A → B → (A =:= B)` (boolean as 1/0) |
| `m_00000010` | `lt` | `A → B → (A < B)` |
| `m_00000011` | `gt` | `A → B → (A > B)` |
| `m_00000012` | `and` | `A → B → (A and B)` |
| `m_00000013` | `or` | `A → B → (A or B)` |
| `m_00000014` | `not` | `A → (A == 0)` |

### String Operations (`m_00000015`–`m_0000001e`)

| Module | Operation | Signature |
|---|---|---|
| `m_00000015` | `str_concat` | `A → B → A <> B` |
| `m_00000016` | `str_len` | `S → byte_size(S)` |
| `m_00000017` | `str_contains` | `Haystack → Needle → match?` |
| `m_00000018` | `str_slice` | `S → Pos → Len → binary:part(S, Pos, Len)` |
| `m_00000019` | `str_uppercase` | `S → uppercase(S)` |
| `m_0000001a` | `str_lowercase` | `S → lowercase(S)` |
| `m_0000001b` | `str_replace` | `S → Pattern → Rep → binary:replace` |
| `m_0000001c` | `str_split` | `S → Delim → binary:split` |
| `m_0000001d` | `str_trim` | `S → trim(S)` |
| `m_0000001e` | `str_to_int` | `S → binary_to_integer(S)` |

### List Operations (`m_0000001f`–`m_00000028`)

| Module | Operation | Signature |
|---|---|---|
| `m_0000001f` | `list_len` | `L → length(L)` |
| `m_00000020` | `list_reverse` | `L → reverse(L)` |
| `m_00000021` | `list_map` | `F → L → map(F, L)` |
| `m_00000022` | `list_filter` | `P → L → filter(P, L)` |
| `m_00000023` | `list_foldl` | `F → Acc → L → foldl(F, Acc, L)` |
| `m_00000024` | `list_concat` | `A → B → A ++ B` |
| `m_00000025` | `list_flatten` | `L → flatten(L)` |
| `m_00000026` | `list_contains` | `E → L → member(E, L)` |
| `m_00000027` | `list_range` | `From → To → seq(From, To)` |
| `m_00000028` | `list_sort` | `L → sort(L)` |

### Data Structures (`m_00000029`–`m_00000032`)

| Module | Operation | Signature |
|---|---|---|
| `m_00000029` | `pair` | `A → B → {pair, A, B}` |
| `m_0000002a` | `fst` | `pair → A` |
| `m_0000002b` | `snd` | `pair → B` |
| `m_0000002c` | `left` | `A → {left, A}` |
| `m_0000002d` | `right` | `B → {right, B}` |
| `m_0000002e` | `dict_new` | `→ maps:new()` |
| `m_0000002f` | `dict_get` | `M → K → maps:get(K, M, null)` |
| `m_00000030` | `dict_put` | `M → K → V → maps:put(K, V, M)` |
| `m_00000031` | `set_new` | `→ sets:new()` |
| `m_00000032` | `set_insert` | `S → E → sets:add_element(E, S)` |

### Concurrency Primitives (`m_00000005`–`m_0000000a`)

| Module | Operation | Signature |
|---|---|---|
| `m_00000005` | `spawn` | `Fun → erlang:spawn(Fun)` |
| `m_00000006` | `self` | `→ erlang:self()` |
| `m_00000007` | `send` | `Pid → Msg → Pid ! Msg` |
| `m_00000008` | `recv` | `→ receive Msg → Msg end` |
| `m_00000009` | `sleep` | `Ms → timer:sleep(Ms)` |
| `m_0000000a` | `now` | `→ erlang:system_time(millisecond)` |

### I/O & FFI Builtins (`m_00000002`, `m_00000033`–`m_00000035`)

| Module | Operation | Signature |
|---|---|---|
| `m_00000002` | `read_line` | `→ io:get_line("")` |
| `m_00000033` | `json_parse` | `JsonStr → parsed` (via gleam_json) |
| `m_00000034` | `http_get` | `Url → response` |
| `m_00000035` | `file_read` | `Path → file:read_file(Path)` |

### State Handler (`m_state`)

| Module | Operation | Signature |
|---|---|---|
| `m_state` | State ability bootstrap | Exports `state_get/1`, `state_put/2` for process-dictionary-backed mutable state |

## Why Erlang, Not Gleam?

Genesis modules are written in raw Erlang because they bootstrap the runtime. The bootstrap sequence is:

1. Erlang code (`m_*.erl`) is compiled to BEAM by `erlc` (Erlang compiler, no Gleam dependency)
2. Compiled `.beam` files are bundled into the escript zip
3. At runtime, genesis modules are loaded first via `code:load_binary/3`
4. User-defined Gleam code is then compiled by gleamunison's own compiler and loaded alongside genesis modules

If genesis modules were written in Gleam, they'd need the Gleam compiler to compile them — but the Gleam compiler IS the gleamunison runtime. This circular dependency is resolved by writing genesis modules in Erlang, the substrate that already exists before gleamunison starts.

## Module Naming

Module names use the `m_<last_8_hex_chars>` format (ADR-0011). For genesis modules, hashes are pre-computed and padded to 256-bit boundaries. The module name is derived from the last 8 characters of that hash. This naming scheme:
- Prevents collisions with Gleam modules (Gleam uses lowercase letters with single `_` separators)
- Produces valid Erlang atoms without quoting
- Ensures content-addressing: identical functionality → identical hash → identical module name across all deployments

## Adding or changing genesis builtins

1. Read `genesis.gleam`, `bootstrap_terms.gleam`, `bootstrap_types.gleam`, and
   the relevant bootstrap declaration in `bootstraps.gleam` first.
2. Add/change the `src/m_*.erl` implementation and its `'$eval'/0` contract.
3. Wire its ref, surface name, and **declared type** through the owning bootstrap
   modules. Do not add only a file and assume it becomes an admitted builtin.
4. Add identity, inference, compile/load, publication, and execution tests as
   appropriate. Builtin-dependent definitions must not acquire an unknown-type
   sentinel or fail CAS decoding.
5. Build and run the artifact contract so the implementation and Datalog/static
   assets are packaged correctly.

Changing an existing genesis implementation is not an ordinary local edit: it
can alter the meaning of content that already has a ref. Treat it as an
identity/compatibility decision with an ADR and migration analysis.
