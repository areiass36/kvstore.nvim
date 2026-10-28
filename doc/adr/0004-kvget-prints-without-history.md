# 0004. KVGet prints without touching the message history

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

`print()`, `:echo` and `vim.notify()` all add their text to the message history, where `:messages` will show it
for the rest of the session. `nvim_echo` with its history flag set to false writes to the screen without
recording anything.

## Decision

`:KVGet` prints the value with `vim.api.nvim_echo(chunks, false, {})`. It never writes to a register, never
touches the clipboard, and never passes the value to `vim.notify`.

## Consequences

The value is on screen until the next redraw and nowhere else, and `:messages` cannot recall it. Message plugins
that wrap `nvim_echo`, such as noice.nvim and nvim-notify, may still keep their own copy; that is outside the
plugin's control and is documented as a limitation. Not copying to a register means the user selects the text
manually, which is the deliberate trade, and it keeps the value away from a clipboard manager that the plugin
cannot control.
