# 0008. One encrypted vault, independent of the operating system

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

Storing every entry in the native keystore would tie the data to one system, limit key names to what each
keystore allows, and expose how many items are stored. The native keystores also differ in capability, which
would push per-system behaviour into the storage layer.

## Decision

All entries live in a single encrypted file. A strong master key is generated from the system CSPRNG on first
use. The file format and every behaviour above it are identical on all systems; only where the master key is
kept differs.

## Consequences

One file to back up, and one place where corruption affects every entry, which is what makes authenticated
encryption and atomic writes mandatory rather than optional. The number of entries is not exposed to the
operating system. Losing the master key makes the vault unrecoverable, which is documented. The storage layer
has no per-system branches.
