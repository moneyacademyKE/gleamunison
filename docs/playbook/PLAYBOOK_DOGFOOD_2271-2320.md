# Playbook Dogfood Batch 23 — Handle, Patterns, Full Pipeline, Storage Stress

## Levels 2271–2320

### Theme

Close remaining coverage gaps with more complex integration tests. This batch
targets four major untested areas: the `Handle` expression term, all untested
pattern variants (`PatText`, `PatCons`, `PatEmptyList`, `PatAs`, `PatConstructor`),
full pipeline stress-tests (parse→elaborate→typecheck→compile→load→eval chains
with multi-definition Units), and storage adapter strain (partitioned_dets,
mnesia, get_adapter roundtrip).

### Levels

- **2271**: `Handle` expression — construct Handle AST, compile via compile_only
- **2272**: `Handle` with Lambda handler — Handle + Lambda compiled together
- **2273**: `Handle` with nested `Do` — Handle computation containing a Do
- **2274**: `Handle` with Match inside computation
- **2275**: `Handle` with Let inside handler term

- **2276**: `Match` with `PatText` — match on a string literal pattern
- **2277**: `Match` with `PatCons` — list head/tail destructuring
- **2278**: `Match` with `PatEmptyList` — empty list pattern
- **2279**: `Match` with `PatAs` — as-pattern binding
- **2280**: `Match` with `PatConstructor` — constructor pattern matching

- **2281**: `Match` with `PatText` + `PatVar` catch-all
- **2282**: `PatCons` + `PatEmptyList` in same match
- **2283**: Parser — cons list syntax roundtrip
- **2284**: `PatAs` with `PatVar` inner
- **2285**: `PatAs` with `PatInt` inner

- **2286**: `Match` with `GuardTerm` guard — simple integer guard
- **2287**: `Match` with `GuardTerm` + multiple cases
- **2288**: Match guard — Erlang rejects unbound var in guard (expected compile err)

- **2289**: Full pipeline: `Int` literal through parse→elab→tc→compile→load→eval
- **2290**: Full pipeline: `Float` literal through full pipeline
- **2291**: Full pipeline: `Text` literal through full pipeline
- **2292**: Full pipeline: `List` literal through compile + load_and_eval
- **2293**: Full pipeline: `Lambda` through compile + load_and_eval

- **2294**: Multi-def Unit: 3 `TermDef`s in one Unit through codebase insert
- **2295**: Multi-def Unit: TypeDef + TermDef together
- **2296**: Multi-def Unit: AbilityDecl + TermDef together
- **2297**: Codebase `get_adapter` roundtrip

- **2298**: `TypeDef Unique` — compile a unique type declaration
- **2299**: `lower` module — `type_ref_to_type` on TypeRefBuiltin variants
- **2300**: `lower` module — `lower_type_ref` on TVar and TBuiltin

- **2301**: `type_pretty` — pretty_print Int, Float, Text, Bool types
- **2302**: `type_pretty` — pretty_print Fn type with params
- **2303**: `type_pretty` — pretty_print App type with args
- **2304**: `type_pretty` — pretty_print TypeVar and AbilityVar
- **2305**: `type_pretty` — pretty_print List and Handler builtins

- **2306**: Storage `partitioned_dets` — create, insert, list_refs
- **2307**: Storage `mnesia` — create, insert, list_refs
- **2308**: Storage adapter roundtrip with 100 inserts
- **2309**: Storage `dets` with large binary values
- **2310**: Codebase insert_raw + get_adapter

- **2311**: REPL `eval_string` — integer literal evaluation
- **2312**: REPL `eval_string` — float literal evaluation
- **2313**: REPL `eval_string` — text literal evaluation
- **2314**: REPL `eval_string` — `define` blocked (API limitation documented)
- **2315**: REPL `eval_string` — builtins unavailable (API gap documented)

- **2316**: `check_linearity` on `Handle` term
- **2317**: `infer_term` on `Handle` with empty cache
- **2318**: `hash_of_definition` on `Handle` term def
- **2319**: Pipeline error path: malformed ref through elaborate
- **2320**: Certification — batch 23 complete

### Success Criteria

All 50 levels pass. New coverage:
- `Handle` term: 100% compile coverage (0→5 levels)
- Pattern variants: `PatText`, `PatCons`, `PatEmptyList`, `PatAs`, `PatConstructor` tested (0→7 levels)
- `GuardTerm` in guard clause (0→3 levels, including expected compile error for Erlang guard limitations)
- Full pipeline: Int, Float, Text, List, Lambda through compile+load+eval (new pathways)
- Multi-def Units with 3+ definitions (new pathway)
- `TypeDef Unique` compile (new pathway)
- `lower` module: first direct tests
- `type_pretty`: first direct tests with all 6 builtins + Fn + App + TypeVar + AbilityVar
- Storage: partitioned_dets, mnesia, 100 inserts, large DETS, insert_raw (new adapters)
- REPL: literal evaluation through eval_string, API limitation documented (define blocked, no builtins)
- `check_linearity`, `infer_term`, `hash_of_definition` on Handle
- Error paths: malformed parse input
- **Gap found**: `eval_string` API does not bootstrap builtins or support `define` — only literal expressions work
