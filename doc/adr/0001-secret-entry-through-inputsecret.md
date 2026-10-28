# 0001. Secret values are only entered through inputsecret()

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

A command argument is visible on the command line while it is typed, is recorded in the command history where
`q:` and the arrow keys recall it, and is written to the ShaDa file, so it would outlive the session in plain
text on disk. `inputsecret()` reads a line without echoing it and without adding it to any history.

## Decision

A value is only ever read with `vim.fn.inputsecret()`. `:KVStore` accepts a key and the optional `--global` flag
and nothing else; a second positional argument is rejected with an error. No command, option or public function
accepts a value as an argument.

## Consequences

A value can never be supplied non-interactively, so `:KVStore` cannot be scripted or driven from a headless
session. That is accepted: a scripted store would need the value to already sit somewhere a script can read it,
which is the problem this plugin exists to remove. Tests drive the prompt through a stub instead of arguments.
