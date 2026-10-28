# 0019. Vault writes are serialised with a lock file

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

A write is a read-modify-write over the whole vault: decrypt, change one entry, re-encrypt, replace the file. Two
Neovim instances storing different keys at the same time would both start from the same plaintext, and the last
writer would silently drop the other's entry. An atomic replacement prevents a torn file but not a lost update.

## Decision

A lock file next to the vault, created with an exclusive open, is held for the whole read-modify-write. A lock
older than ten seconds is treated as stale and taken over, so a crashed instance cannot block the vault forever.
The new vault is written to a temporary file in the same directory, flushed, and renamed over the target. Reads
do not take the lock.

## Consequences

Concurrent writes serialise instead of losing data, and an instance that cannot take the lock reports a clear
error rather than waiting indefinitely. Reads stay lock-free because the atomic rename means a reader always sees
one complete version of the file. The stale takeover is a deliberate trade: a write that genuinely took longer
than ten seconds could be overlapped, which cannot happen for a vault of a few kilobytes.
