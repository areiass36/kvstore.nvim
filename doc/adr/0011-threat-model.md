# 0011. Threat model: accidental leaks

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

The strength of the whole design depends on what it defends against. Two targets were weighed. The first is
accidental exposure: a value committed to a repository, carried into a backup or a sync folder, read over a
shoulder, or recalled from a history file. The second is active attack by code already running as the same user,
which requires a master passphrase and a key derivation function, and therefore a prompt in every session and no
unattended headless use.

## Decision

The plugin defends against accidental exposure. The master key is unlocked by the operating system with no
prompt. There is no master passphrase.

## Consequences

`:KVGet` and the public `get()` keep working in headless sessions and at config time, which is the main use.
Anything already running as the user can reach the master key through the same keystore the plugin uses, so the
plugin does not defend against that, and the help file says so plainly rather than implying protection it does
not provide. Adding a passphrase later would change the vault format and so requires a new record.
