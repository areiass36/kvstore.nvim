# 0006. Global keys require the --global flag

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

A command that silently fell back from the project scope to the global scope would make `:KVGet token` answer
differently depending on the working directory, with no way to tell which scope answered.

## Decision

The scope is explicit. Without `--global` a command addresses the project scope only. With `--global` it
addresses the global scope only. There is no fallback between them.

## Consequences

A value needed in several projects is stored once with `--global` and always read with `--global`. A missing key
is reported as missing instead of being quietly answered from another scope. The same name can exist in both
scopes without ambiguity, at the cost of the user remembering which scope holds what.
