# 0017. The value is entered once by default

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

`inputsecret()` shows no feedback at all, so a typo is invisible and is usually discovered much later, when the
stored value fails somewhere else. Asking for the value twice catches the typo but doubles the typing on every
store, and a wrong value can always be corrected by storing the key again.

## Decision

The value is entered once by default. `setup({ confirm_value = true })` asks a second time and aborts without
writing if the two entries differ.

## Consequences

The default path stays short. Users who store long values, or who have been bitten once, can opt in per
configuration rather than per command. A mismatch aborts rather than asking again, so a confused session cannot
end with a half-typed value stored. The cost is one more branch in the store flow and in its tests.
