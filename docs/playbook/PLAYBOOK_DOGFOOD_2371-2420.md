# Playbook Dogfood Batch 25 — REPL API Depth, Effects Runtime, Error Recovery, Loader Stress

## Levels 2371–2420

### Theme

Deepen coverage of the REPL API surface (eval_string, eval_string_unique, handle_define, do_eval,
bootstrap_defs, serialize_term/deserialize_term), effects runtime (nested Handles, multi-ability dispatch,
Handle+Do continuation-returning handlers), error recovery at every pipeline stage (parse, elab, compile,
load, eval), loader stress (eviction, memoization, limit-constrained), and cross-module+effects combined.

### Levels

- **2371**: repl:eval_string integer literal
- **2372**: repl:eval_string text literal
- **2373**: repl:eval_string float literal
- **2374**: repl:eval_string parse error (unclosed paren)
- **2375**: repl:eval_string empty input
- **2376**: repl:eval_string_unique with int literal
- **2377**: repl_eval:handle_define + do_eval chain (define a, define b, eval sum)
- **2378**: repl_eval:handle_define error path (undefined var)
- **2379**: pipeline:parse_only + elaborate_only on int literal
- **2380**: pipeline:compile_only + load_and_eval roundtrip (int)

- **2381**: Two abilities Handle+Do compile+load+eval
- **2382**: Handle with ability module + cross-ref
- **2383**: Handle with nested Let + Lambda
- **2384**: Handle with List inside computation
- **2385**: Handle with text result
- **2386**: Handle with Match inside works at runtime
- **2387**: Handle with Do — runtime dispatch with continuation handler
- **2388**: Two Handles on different abilities (nested)
- **2389**: Handle with Float result
- **2390**: Effects + cross-module combined

- **2391**: parse_only empty input
- **2392**: elaborate_only with unbound variable
- **2393**: elaborate_only on a lambda
- **2394**: elaborate_only on a let expression
- **2395**: elaborate_only with define-blocked check
- **2396**: elaborate_only cross-ref between defs (multi-def unit)
- **2397**: compile_only on empty list term
- **2398**: compile_only + load_and_eval on int-like
- **2399**: compile_only on Apply identity
- **2400**: serialize_term + deserialize_term roundtrip

- **2401**: Loader new_loader_with_limit(1) + 2 defs
- **2402**: Loader is_loaded after eviction (limit 2, 3 loaded)
- **2403**: Loader CompileFailed memoization
- **2404**: serialize_term on multiple types (string, int, list)
- **2405**: bootstrap_defs with 5 defs
- **2406**: bootstrap_defs + do_eval after bootstrap
- **2407**: compile_only on Let expression roundtrip
- **2408**: elaborate_only with prev defs
- **2409**: Loader error — CompileFailed path
- **2410**: elaborate_only on complex expression

- **2411**: Loader limit 2 + 3 defs (from original plan)
- **2412**: Loader is_loaded after eviction
- **2413**: Loader CompileFailed memoization retest
- **2414**: serialize_term on int
- **2415**: serialize_term on list
- **2416**: bootstrap_defs smoke test
- **2417**: bootstrap_defs with multiple defs
- **2418**: do_eval with non-empty prev_defs
- **2419**: Loader is_loaded with fresh loader
- **2420**: Certification — batch 25 complete

### Success Criteria

All 50 levels pass. New coverage:
- REPL API: eval_string 5 variants, eval_string_unique, handle_define+do_eval chain, parse_only+elaborate_only, compile_only+load_and_eval roundtrip
- Effects runtime: two abilities, cross-ref Handle, Handle+Let+Lambda, Handle+List/Text/Float/Match, Handle+Do continuation dispatch, nested Handles, effects+cross-module combined
- Error recovery: parse_only empty, elab unbound var, lambda/let elab, define-blocked, multi-def elab, empty list compile, identity apply, serialize/deserialize
- Loader stress: new_loader_with_limit, is_loaded after eviction, CompileFailed memoization, fresh-loader is_loaded check
- Serialization: string/int/list roundtrip via serialize_term/deserialize_term
- bootstrap_defs: smoke test with 1-5 defs, post-bootstrap do_eval

### Version

v3.7.0 — closes REPL API depth, effects runtime nesting, error recovery pipeline, loader stress, and serialization coverage gaps.
1443 verifications (1390 dogfood + 53 unit tests) across 25 playbook files.
