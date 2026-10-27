# ADR 0075: MCP graph queries are direct datom operations

- **Status:** Accepted
- **Date:** 2026-10-27 (EAT)
- **Tracking:** Bankai `bk-9a58`
- **Implementation:** `ad0afa9`, `e583630`
- **Related:** [ADR 0062](0062-native-content-addressed-datalog-database.md), [ADR 0068](0068-durable-agent-read-model.md)

## Context

The MCP tools `callers_of`, `deps_of`, and `defs_by_kind` are fixed filters
over the session's definition datoms: match `def/dep`, `def/name`, or
`def/kind`, then join to names. Until this decision they were answered by
generating an index program in Gleamunison's own S-expression language,
loading the thirteen-module Datalog engine, evaluating the program, printing
the bindings, and parsing that printed output back into strings.

ADR 0062 describes that engine as a user-space showcase written in the
bootstrapped language. The MCP path inverted the relationship: runtime
infrastructure depended on the showcase. Each query paid a program build, an
engine evaluation, and a text-decode round trip, and the argument had to be
escaped into a literal via `lisp_literal` before it could be filtered on.
The result decoder (`gleamunison_index_result`) existed only to validate this
round trip.

### Gap analysis

| Option | Reason and trade-off |
|---|---|
| Keep engine-backed queries | No code change, but runtime query correctness depends on a showcase engine and a print/parse round trip. |
| Cache index results | Adds invalidation complexity on top of the same evaluation path; the query is not expensive, the mechanism was. |
| Direct datom filters | The three queries are fixed joins over an in-memory list; answer them as data operations. |
| Delete the Datalog engine | Removes a working user-space capability and the self-hosting showcase for no correctness gain. Rejected. |

The recommendation weights **data over mechanisms**: when the query is fixed
and the facts are already in memory, evaluate the join directly instead of
generating, executing, and parsing a program to do it.

## Decision

1. **Fixed graph filters are data operations.** `callers_of`, `deps_of`, and
   `defs_by_kind` compose `codebase_graph` over the selected session's
   definition datoms. No program is generated, loaded, or evaluated to
   answer them.
2. **Established results are contract.** The observed answer order
   (newest-defined first) and dependency de-duplication are pinned by a
   characterization test, not "improved" during the extraction.
3. **A traced regression guards the boundary.** The graph tests count
   `eval_index_source` calls while answering all three queries; the required
   count is zero.
4. **The Datalog engine remains user-space software.** `gleamunison_datalog`,
   its CLI, its genesis module, and its own test suite are untouched. ADR
   0062's showcase claim is now strictly true: nothing in the runtime query
   path depends on it.
5. **The round-trip decoder is deleted.** `gleamunison_index_result.erl` and
   its self-test had no remaining production caller once MCP stopped
   printing and parsing. The MCP-only `index_entries` renderer is removed
   for the same reason.

## Consequences

- `mcp_session` no longer imports `lisp_literal` or the index evaluator; its
  graph tools delegate to one small module with no engine dependency.
- The engine is no longer transitively required to answer a graph question,
  so an engine defect can no longer break basic MCP introspection.
- Answers remain strings in the established order; MCP JSON responses are
  unchanged in shape.
- Future graph capability that genuinely needs rules or recursion becomes a
  deliberate decision about where evaluation belongs, not a default that
  already happened.

## Alternatives rejected

- **Cache evaluated queries:** optimizes a mechanism that should not run.
- **Keep the engine call for fidelity:** behavior-identical but preserves a
  runtime dependency on a showcase and a string-format contract.
- **Move the engine out of the repository:** deletes a working user-space
  capability; the removal target was the dependency, not the software.

## Verification

Red before green: the traced regression initially counted three
`eval_index_source` calls for three queries and failed. After the
implementation the count is zero, ordering and de-duplication regressions
pass unchanged, and the full suite is green.

An end-to-end probe exercised the real MCP RPC handler for all three tools
and confirmed the JSON responses, including newest-first ordering.

**Rich Hickey check:** the query was fixed and the facts were already data;
generating and evaluating a program to filter a list was mechanism standing
in for the missing simplicity. The engine keeps its place as user space, not
runtime plumbing.
