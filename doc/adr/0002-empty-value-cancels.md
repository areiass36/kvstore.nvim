# 0002. An empty value cancels the operation

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

`inputsecret()` returns an empty string both when the user confirms an empty line and when the prompt is
interrupted. The two cases are indistinguishable. An empty string is also useless as a stored secret.

## Decision

Empty input cancels the operation. Nothing is written, no existing entry is modified, and the user is told the
operation was cancelled.

## Consequences

A key cannot hold an empty value; clearing a key is `:KVDelete`. An interrupted prompt and a deliberate empty
line behave identically, which is the safe direction because both leave the vault untouched.
