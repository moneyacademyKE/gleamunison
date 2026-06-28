# ADR 0043: Dynamic Code Shipping for Process Migration

## Context
1. **Live Process Migration**: One of the flagship distributed use cases for `gleamunison` is Live Process Migration, where running actor closures are serialized and shipped to another node.
2. **Dynamic Code Loading Prerequisites**: For a remote node to resume executing a migrated closure, it must have access to all transitive code dependencies. In standard Erlang/Gleam, trying to execute uncompiled/unloaded code results in `undef` errors.
3. **Merkle Sync Integration**: The remote node must be able to detect missing modules, pull their compiled bytecode using content-addressed hashes, load them dynamically, and resume execution without crashes.

## Decision
1. **Prototype Validation**: Create a dedicated test suite `test/migration_test.gleam` to verify the VM's ability to:
   - Compile a term to `m_<hash>.beam`.
   - Load and evaluate the code.
   - Unload the code to simulate a target node not possessing the dependency.
   - Confirm that subsequent execution attempts fail gracefully.
   - Ship (reload) the binary.
   - Verify that execution successfully resumes.
2. **Separate Test Module**: Keep the test logic in a dedicated module `test/migration_test.gleam` to maintain strict LOC limits (<250 LOC).

## Consequences
* Validates the core dynamic shipping pipeline required for distributed migration topologies.
* Certifies that Erlang's dynamic loader can be driven securely using content-addressed hashes.
