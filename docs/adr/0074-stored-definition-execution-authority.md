# ADR 0074: Stored definitions are the only execution authority

- **Status:** Accepted; supersedes [ADR 0044](0044-content-addressed-jet-registry.md)
- **Date:** 2026-10-27 (EAT)
- **Tracking:** Bankai `bk-86c1`
- **Implementation:** `1b1d22e`, `f905006`
- **Related:** [ADR 0001](0001-content-addressed-identity.md), [ADR 0003](0003-genesis-builtins.md), [ADR 0067](0067-production-boundaries.md)

## Context

ADR 0044 proposed a registry that would replace selected content-addressed
terms with native Erlang bodies during compilation. The implementation also
overrode references, fabricated an inert definition in the loader, and added a
separate dependency-resolution path for registry hits.

That made definition identity insufficient to determine behavior. The former
Fibonacci regression explicitly allowed any stored AST because the registry
could ignore it. Registry entries for `self` and `recv` also changed values
into one-argument functions; `self` consequently made `send` fail with
`badarg`. Genesis modules already provided all four process builtins without
this second authority.

No measured production bottleneck justified keeping the experiment. Native
FFI remains necessary at explicit host boundaries; arbitrary hash-triggered
replacement is a different mechanism with different semantics.

### Gap analysis

| Option | Reason and trade-off |
|---|---|
| Keep the registry | Retains an unmeasured optimization hook, but stored content is not authoritative and process behavior is wrong. |
| Fix only `self` and `recv` entries | Repairs two symptoms while preserving arbitrary AST replacement. |
| Add equivalence checks around every jet | Creates a second compiler/admission problem before demonstrating a performance need. |
| Remove dispatch, retain genesis/native FFI | One definition path; keeps the required host capabilities and deletes only the conflicting authority. |
| Remove all native modules | Would delete working host capabilities rather than the duplicate dispatch mechanism. Rejected. |

The recommendation weights **semantic correctness first, operability second,
and speculative optimization last**. A future optimization must earn its
complexity with a measured bottleneck and an equivalence contract.

## Decision

1. **The supplied definition is authoritative.** `compile_definition` emits
   the supplied term, type declaration, or ability declaration. A reference
   always emits a call to the referenced hash-named module; registry
   membership cannot substitute another body.
2. **There is one loading path.** `ensure_loaded` compiles and loads a supplied
   definition. There is no `ensure_loaded_jet`, fabricated `Int(0)` stand-in,
   or registry-specific dependency fallback.
3. **Absence has only the established exceptions.** A missing store entry may
   resolve as a declared bootstrap type or an available genesis builtin.
   Other missing refs fail rather than acquiring meaning from a host table.
4. **Genesis and native FFI remain.** Checked-in `m_*.erl` modules are explicit
   builtin implementations, not a generic override registry. In particular,
   `spawn`, `self`, `send`, and `recv` retain their genesis behavior.
5. **Obsolete policy is removed.** `native_jets` and `NativeJetDenied` disappear
   because there is no jet mechanism to admit. Untrusted execution still
   requires an approved external executor and refuses direct host FFI;
   resource budgets are unchanged.
6. **Former registry hashes are ordinary refs.** Stored content at those refs
   executes its own AST. The experimental Fibonacci FFI module and registry
   module are deleted; historical ADR 0044 remains as decision history.
7. **Future acceleration is a new decision.** It must demonstrate a measured
   need and preserve observable behavior. It must not make a hash select an
   unrelated host definition.

## Consequences

- A content ref and the ordinary bootstrap environment again determine one
  execution path. Compilation no longer has a hidden registry input.
- The ordinary evaluator and stored-content `run_ref` path can perform a
  `self` → `send` → `recv` round trip; `spawn` remains available.
- The internal `SandboxPolicy` constructor loses one field. Construction sites
  must stop supplying it; this does not add a compatibility alias for a
  mechanism that no longer exists.
- Old jet-only conformance cases become stored-authority and process-builtin
  cases. Historical notebooks and ADR 0044 are not rewritten as current
  guidance.
- No claim is made that all possible native acceleration is undesirable. The
  rejected part is an unverified second definition authority, not native code
  itself.

## Alternatives rejected

- **Patch the incorrect process jets:** leaves the semantic defect intact.
- **Keep an unused registry for future needs:** speculative complexity with a
  live correctness cost.
- **Delete genesis/native FFI:** removes necessary host capabilities instead
  of the duplicate dispatch path.
- **Add a second compatibility authority:** would preserve precisely the
  ambiguity this decision removes.

## Verification

Red-before-green regressions at the implementation base proved three defects:
the legacy Fibonacci hash returned `55` instead of its stored lambda's `42`,
and both ordinary evaluation and stored-content execution failed the process
round trip with `badarg`. After the implementation, all three pass.

The final suite and conformance results are recorded in the implementation
witness rather than maintained as permanent counters here.

**Rich Hickey check:** one value, one meaning, one loading path. Native FFI
stays at the boundary; the rejected alternative complects identity with an
unverified host-side replacement table.
