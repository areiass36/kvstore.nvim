# 0007. KVStore confirms before overwriting a key

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

Overwriting a stored secret is unrecoverable, because the previous value is kept nowhere. Asking after the value
has been typed would waste the input and tempt the user to confirm merely to avoid typing it again.

## Decision

`:KVStore` checks whether the key already exists before prompting for the value. If it does, it asks for
confirmation with "No" as the default. Declining, or pressing `<Esc>`, ends the command without prompting.

## Consequences

Overwriting costs one extra keystroke. The check requires a vault read before the prompt, which has the useful
side effect of surfacing an unreadable vault before the user has typed anything. The default answer being "No"
means an accidental `<CR>` cannot destroy a value.
