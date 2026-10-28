# 0003. Secret values reach external tools through stdin

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

Process arguments are readable by any process of the same user on all three supported systems, through `ps`,
`/proc/<pid>/cmdline` and the Windows process list. Environment variables are nearly as exposed and are
inherited by children. The plugin reaches the native keystores through external tools, so the master key has to
cross a process boundary.

## Decision

Every secret crossing a process boundary is written to the child's stdin. No secret is ever placed in an
argument list or in an environment variable. Processes are spawned with an argument list, never a shell string,
so nothing passes through a shell that could log or expand it.

## Consequences

Backends are limited to tools that can read a secret from stdin, which is why `security` is driven through its
interactive mode. A single module owns process spawning, so the rule is enforced and tested in one place, and a
test asserts that a sentinel secret appears in no recorded argument list and no environment.
