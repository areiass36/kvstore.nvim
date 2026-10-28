# 0009. The master key lives in the native keystore with a file fallback

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

The master key has to be available without a prompt, otherwise `:KVGet` and config-time reads stop working in
headless sessions. The native keystores already solve storing one secret per user with protection from the
operating system, but they are not always present: a headless Linux session or an SSH login usually has no
Secret Service.

## Decision

The master key is stored in the native keystore when one is detected. Where none is available it falls back to a
file readable only by the owner, and the user is warned once that the protection is weaker. The keystore layer
stores exactly one item and exposes `get`, `set`, `exists` and `delete`.

## Consequences

The common case needs no prompt and no configuration. The fallback keeps the plugin usable everywhere but
protects only against other users, not against code running as the same user; that follows from the threat model
and is documented. A one-item interface keeps every backend small and makes them interchangeable in tests.
