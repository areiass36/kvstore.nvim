# 0021. The master key is read once per command

- Date: 2026-10-28T15:41:21Z
- Status: Accepted

## Context

Record 0009 keeps the master key in the native keystore, and record 0020 reaches the Windows keystore through
PowerShell. Reaching a keystore therefore costs a process, and the first implementation read the key on every
operation that needed it. A single command needs it several times: `:KVStore` checks that the vault is usable,
checks whether the key exists, reads the vault and writes it back.

Measured on the development machine against the real DPAPI backend, where `Add-Type` dominates the cost:

| Operation | Keystore reads | Measured |
| --- | --- | --- |
| one keystore read | 1 | 360 ms |
| `:KVGet` | 1 | 362 ms |
| `:KVStore` | 4 | 702 ms |
| `:KVDelete` | 3 | 1046 ms |

Caching the key for the whole session was rejected: the security rules say a secret is kept in memory only as
long as strictly needed, and a session lasts for days. Not caching at all makes `:KVDelete` take a second and
makes command completion, which decrypts the vault on every keypress, visibly slow.

## Decision

A vault instance reads the master key at most once and holds it for its own lifetime. A failure is not held, so
a keystore that was momentarily unavailable can be retried. The command layer builds a fresh vault for every
command, so the key is read once per command and is dropped when the command ends.

## Consequences

Each command performs exactly one keystore read, which removes two to three process spawns from `:KVStore` and
`:KVDelete`. The key is in memory for the duration of one command rather than for a session, which is the
shortest lifetime that still serves the command needing it. Nothing holds a vault instance across commands, and
any future code that wants to must weigh this record again. The public `get()` builds its own vault per call, so
a configuration that reads several keys pays one keystore read per key.
