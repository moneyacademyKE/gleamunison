# Upgrade and Rollback

The gate that proves this procedure is `bb scripts/test_upgrade_rollback.clj`;
it installs the previous release from its git tag, upgrades, corrupts the
install, and rolls back, with receipts. This document is the operator half.

## Identity

An installed artifact proves what it is from its packaged metadata:

```sh
unzip -p ./gleamunison gleamunison.app | grep vsn
./gleamunison version          # v3.23.0 and later
./gleamunison schema-version   # storage/codec schema integer
```

## Storage compatibility gate

Stores are compatible exactly while `schema-version` is equal across the two
releases. While the codec stays at version 1, an upgrade needs no migration:
point the new binary at the old store and start. A schema bump refuses
silent compat: the release notes must name the migration step, and this gate
turns red until it exists.

## Upgrade

1. Back up the installed binary (`cp gleamunison gleamunison.prev`).
2. Build the new artifact: `./build_escript.sh` (atomic — a failed build
   never touches the previous artifact).
3. Gate it: `bb scripts/test_release_contract.clj`.
4. Stop the service (see Drain), install the new binary, start, verify
   `version` and `schema-version`.

## Failed upgrade

A corrupt artifact fails loudly at startup (the escript loader rejects it);
it never half-serves traffic. Detection is part of the gate: the script
truncates the install and requires a non-zero exit.

## Rollback

1. Stop the service.
2. Restore the backup over the install (`cp gleamunison.prev gleamunison`).
3. Start, verify identity (`unzip -p ... vsn`) and liveness.
4. If the upgrade changed `schema-version` (it must not without a migration
   step), the store may already be migrated forward; rollback then requires
   the store backup taken before the upgrade. Take one.

## Drain

`gleamunison_http:drain(TimeoutMs)` closes the listen socket and stops the
acceptor first — no new connections — then waits for in-flight workers to
finish up to the timeout, returning `drained` or `{timeout, Remaining}`.
The server process survives; supervision or `stop_server/0` completes the
shutdown. Drain before every upgrade and rollback: the goal is zero
in-flight work crossing a binary swap.

## Hot-loading limits

Hot code loading is supported for exactly one thing: user definition modules
(`m_*`) delivered through sync, which are compiled, loaded, unloaded, and
reloaded per definition (see `test/migration_test.gleam`). Everything else —
runtime modules, supervisors, the evaluator, this CLI — requires a full
restart. There is no partial upgrade of the runtime inside a live node; do
not build one.
