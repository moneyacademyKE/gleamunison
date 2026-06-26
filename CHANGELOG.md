# Changelog — v0.3.0

Content-addressed language runtime prototype on the BEAM, built in Gleam.

---

## What's New in v0.3.0

This release completes Phase 0/1 of the prototype, delivering an integrated, end-to-end Content-Addressed VM with Hindley-Milner type inference, lexically scoped algebraic effects, dynamic BEAM bytecode compilation & hot code loading, and a three-phase pull sync protocol.

### 1. Robust Core VM & Type System
*   **Hindley-Milner Type Inference**: Support for Int, Float, Text, homogeneous Lists, and multi-argument curried application.
*   **Polymorphic sentinel**: Introduces a dedicated `TypeVar(-1)` sentinel for unknown apply evaluations, preventing index collisions with local binders.
*   **Structural Content-Addressability**: Complete hash-addressed codebase. Hashing of type declarations and ability declarations is structurally serialized using deterministic inspect logic, ensuring unique identity and zero collisions.

### 2. Lexically Scoped Algebraic Effects
*   **Process Dictionary Handler Stack**: Effect handlers are dynamically managed on a thread-local stack in the process dictionary.
*   **Erlang Effects Dispatcher (`gleamunison_effets.erl`)**: Fully implements dynamic `do_op/4` and `handle_comp/2` with trailing-block call semantics and key normalization (matching both atom and binary keys).
*   **Exception Safety**: Employs `try ... after` blocks to guarantee stack restoration in case of runtime computation errors.

### 3. Isolated Content-Addressed Storage
*   **Erlang ETS-backed storage**: Implemented inside `gleamunison_storage.erl`.
*   **Background process ownership**: Spawns an unsupervised background thread to permanently hold table memory. Data survives caller process terminations (e.g. transient web requests or unit test workers).

### 4. 3-Phase Pull-based Sync Protocol
*   **Protocol Flow**: Advertise local refs → receive remote diff → request missing definitions.
*   **Hash Integrity**: Received payloads transmit `(hash_hex, compiled_beam)` pairs, enabling the receiver to hex-decode and reconstruct the canonical `DefinitionRef` directly instead of incorrectly hashing compiled bytecode.

### 5. Packaging & standalone binary
*   **Standalone escript**: Packages all compiled BEAM bytecode (including dependencies like `gleam_stdlib`) into a single executable `gleamunison` (~350KB).
*   **Zero dependencies**: Runs on any machine with Erlang/OTP installed, without requiring Gleam at runtime.

---

## Verification Results
*   **Test Suite**: 26 passed unit and integration tests covering codebase hashing, sync diffing, effect stack execution, and storage lifecycle.
*   **Constraint Verification**: 100% compliance with the strict codebase limit of <100 lines per `.gleam` file.
