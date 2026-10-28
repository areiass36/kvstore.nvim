# 0018. Key name rules

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

The stored name is built as `global:<key>` or `project:<hash>:<key>`, so a key containing a colon would make the
stored name ambiguous. Key names are also shown in command completion and in error messages, where a control
character or a newline could corrupt the display, and an unbounded name would bloat the vault for no benefit.

## Decision

A key name matches `^[%w._-]+$` in ASCII and is between 1 and 128 characters long. Anything else is rejected with
an error that states the rule. Validation happens in `scope.lua`, before any prompt and before the vault is read,
so every command enforces it identically.

## Consequences

The stored name can never be ambiguous, and a key name is always safe to show in a message or in completion.
Spaces and non-ASCII characters cannot be used in key names, which is a real restriction accepted for the
unambiguous separator. Validating before prompting means a typo in the key name never costs the user a typed
value.
