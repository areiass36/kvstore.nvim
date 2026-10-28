# 0010. macOS, Windows and Linux are supported equally

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

A plugin that handles paths, file permissions and external processes drifts towards whichever system its author
uses daily, and the drift is normally discovered by a user on another system.

## Decision

The three systems are supported equally. Paths are built with `vim.fs` and `vim.uv`, never by concatenating a
separator. Processes are spawned with an argument list, never through a shell. External tools are detected and
their absence produces a clear error. File names stay lowercase so `require` behaves the same on
case-insensitive filesystems. Line endings are LF. Tests run on all three systems in continuous integration.

## Consequences

Every feature needs an answer for Windows, including file permissions, where restricting an ACL replaces changing
a mode. Continuous integration is three times as wide. Behaviour that cannot be tested automatically, such as a
real keystore round trip, is covered by a manual checklist per system.
