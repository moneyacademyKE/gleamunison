# Component removal gap analysis: remove the jet registry

**Date:** 2026-10-27

**Repository state:** `23cb93c` on `fix/component-audit-2026-10-24`

**Task:** `bk-065c`

**Scope:** source-backed analysis only; no production behavior changed

## Recommendation

Remove the current **jet registry and jet dispatch path**. Do not remove
process builtins, native FFI, content-addressed compilation, or the storage
adapter pattern.

This is the best removal because the jet layer is simultaneously:

1. a second authority for what a definition means;
2. a duplicate implementation of existing genesis builtins;
3. the cause of a reachable process-builtin failure; and
4. an optimization mechanism without current production performance evidence.

The language becomes smaller and more truthful: a content ref again has one
definition, resolved through the ordinary genesis/CAS path.

## Method

I inventoried current Gleam and Erlang modules, traced callers, read the core
pipeline and candidate subsystems, searched current benchmarks and verification
material, and ran focused local behavior probes. Historical ADRs and audits
were used as context, not as evidence of current behavior.

No full test-suite claim is made here: this was an analysis, not an
implementation. The focused probes below did execute against the current
build.

## Component map and removal candidates

| Candidate | Current responsibility | Coupling or duplication | Capability if removed |
|---|---|---|---|
| Jet registry and dispatch | Overrides compilation by hard-coded ref; supplies alternate loading | Compiler, loader, dependency resolver, sandbox policy; duplicates genesis process builtins | Loses experimental hash-triggered overrides, including the test Fibonacci jet |
| Built-in Datalog engine | General user-space database demo; backs three MCP graph filters | Generates/evaluates Lisp and reparses printed results; two identical 1,142-line source trees plus locator/artifact machinery | Full removal loses the `datalog` CLI and general engine; extraction can retain it as a package |
| Mnesia and partitioned DETS backends | Alternative byte-store implementations behind `StorageAdapter` | Four backend variants across constructors, active storage, sync FFI, readiness, and tests | Loses those adapters and requires migration for any external stores |
| `run_closure` / `run_ref` | Dependency loading versus evidence-checked execution | Names look similar, but responsibilities are distinct | Removing either breaks the main execution path; rejected |

The storage **adapter** should remain even if backend choices are later reduced:
it separates byte persistence from codebase semantics. Unused constructors are
not sufficient grounds to collapse that boundary.

## Why jets fail the language's central invariant

`docs/ARCHITECTURE.md` defines identity as the canonical term plus inferred
type. The jet path adds a hidden third input: membership in a hard-coded host
registry.

- `src/gleamunison/compile.gleam:43-47` replaces a referenced definition with
  jet-provided Erlang source.
- `src/gleamunison/compile.gleam:151-157` chooses the jet body before even
  reading the stored definition body.
- `test/jets_test.gleam:13-15` makes the consequence explicit: the AST “can be
  anything” because it is ignored.
- `src/gleamunison/loader.gleam:81-97` fabricates an inert `Int(0)` definition
  to load a jet, further demonstrating that the definition is not authoritative.
- `src/gleamunison/run_closure.gleam:107-119` adds a separate resolution rule
  for refs absent from the store.
- `src/gleamunison/sandbox_policy.gleam:38-49,107-114` carries a policy switch
  for this extra execution mechanism.

A semantics-preserving optimization can be legitimate. This implementation
does not establish semantic equivalence; it permits arbitrary replacement by
construction. ADR 0044 asserts performance and purity benefits, but a search
of current dogfood benchmarks and verification material found no production
benchmark demonstrating the former and no equivalence mechanism establishing
the latter.

### The duplicate process builtins are observably wrong

The registry is not only an unused Fibonacci experiment. It also intercepts
`spawn`, `self`, `send`, and `recv` (`src/gleamunison/jets.gleam:13-25`), even
though checked-in genesis modules already implement all four.

The declarations and canonical native modules disagree with the jets:

| Builtin | Declared/canonical behavior | Jet behavior |
|---|---|---|
| `self` | A process value: `bootstrap_terms.gleam:67`; `m_00000006.erl` returns `erlang:self()` | `fun(_) -> erlang:self() end`, requiring an argument |
| `recv` | A host value: `bootstrap_terms.gleam:73`; `m_00000008.erl` receives immediately | `fun(_) -> receive ... end`, requiring an argument |
| `spawn` | `m_00000005.erl` handles zero- and one-argument functions explicitly | A different one-argument wrapper |

Focused probes against the current build confirmed the reachable failure:

- Evaluating `self` in the ordinary REPL returned `#Fun<...>`, not a pid.
- Evaluating `(send self "hi")` failed at runtime with `error:badarg` because
  `send` received that function instead of a pid.
- Calling the existing genesis modules directly returned a pid and completed
  a `send`/`recv` round trip with `<<"hi">>`.

The direct genesis probe establishes that the retained native capability
works; it is not a claim that removal has already been implemented or tested
end to end.

## Gap comparison

| Criterion | Remove jets | Extract built-in Datalog | Reduce storage backends |
|---|---|---|---|
| Correctness benefit | **High:** restores one definition authority and fixes process behavior | Medium: simplifies working query machinery | Low: no core semantic defect found |
| Coupling removed | Compiler, loader, resolver, policy, registry, test FFI | Runtime evaluator, source generation, result parser, locator, duplicate packaging | Backend branches across storage, active storage, sync FFI, readiness |
| Capability retained | All four process builtins and ordinary native FFI | MCP filters can become direct data queries; Datalog can move to a package | ETS, DETS, application journal, and adapter boundary remain |
| Migration cost | Moderate: central but small call graph; jet-only conformance must change | High: working CLI/MCP/artifact contracts move together | High and uncertain: external persisted stores and compatibility need discovery |
| Main risk | External users of undocumented custom jets; stale jet playbook cases | Accidentally deleting useful Datalog capability instead of extracting it | Breaking stores or topologies not visible in this repository |
| Rank | **1 — remove now** | **2 — design extraction next** | **3 — defer pending usage/migration evidence** |

## Recommended removal shape

This is a design for a subsequent implementation task, not work performed by
this analysis.

1. Add a red surface-level regression proving the `self` → `send` → `recv`
   round trip through the ordinary evaluator. Cover `spawn` through the same
   path so this is a behavior change, not merely deleted registry tests.
2. Remove jet lookup from `compile.gleam`; always emit the supplied canonical
   definition and ordinary references.
3. Remove `ensure_loaded_jet` and the jet branch in `run_closure`. Genesis
   availability remains through the existing bootstrap/module path.
4. After explicit deletion approval, remove `jets.gleam` and the six-line test
   Fibonacci FFI module. Do not delete `src/m_00000005.erl` through
   `src/m_00000008.erl`.
5. Remove the obsolete `native_jets` policy field/refusal while preserving the
   untrusted-execution refusal and all direct-host-FFI controls.
6. Replace jet-only unit/playbook cases with process-builtin behavior cases.
   Add a new ADR superseding ADR 0044; do not rewrite that historical decision.
7. Run the full unit, playbook, format, Erlang, diff, and artifact gates. No
   release, tag, merge, push, or deployment is implied.

The key acceptance rule is: **registered-looking refs must behave exactly like
other refs**. No hash may select an unrelated host body.

## Rejected alternatives

- **Only fix `self` and `recv` in the jet table.** This repairs two entries
  while preserving arbitrary AST replacement and the second authority.
- **Keep jets for a future optimization.** That is speculative complexity.
  Reintroduce an optimization only after a measured bottleneck and an
  equivalence contract exist.
- **Remove Datalog first.** It is substantial packaging and query-path
  simplification, but it requires moving working capabilities and does not fix
  a comparably direct violation of definition identity.
- **Collapse the storage adapter.** That would complect persistence with
  codebase semantics. Backend reduction, if justified, is a separate decision.

## Follow-up: Datalog without the runtime dependency

After jets, the next simplification should extract Datalog from MCP's fixed
`callers_of`, `deps_of`, and `defs_by_kind` queries. Those operations are fixed
filters/joins over `codebase_index.Datom`; they do not require a general
Datalog evaluator. Keep the engine as user-space software or a package rather
than making the runtime locate, load, evaluate, and reparse it for every fixed
query.

That is a good second project. It is not a reason to preserve the jet layer.

## Verdict

**Remove the current jet component.** It is the smallest candidate whose
removal improves both architecture and observed language behavior. Keep the
canonical genesis builtins and the single compile/load/execute pipeline.

Rich Hickey check: this removes a competing meaning of a value instead of
adding another compatibility layer around it. That is subtraction with a
semantic payoff, not line-count gardening.
