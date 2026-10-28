# 0022. The Lua API stores values, always in the global scope

- Date: 2026-10-28T17:03:58Z
- Status: Accepted

Supersedes 0001, 0006 and 0016.

## Context

Records 0001 and 0016 were written for a plugin that only held secrets a person typed. Record 0001 forbade any
public function from accepting a value as an argument, and record 0016 therefore exposed no setter: the argument
was that a setter is the path by which a value arrives from a configuration file or a script, which is the
exposure the plugin exists to prevent.

The plugin is now also meant to be a light store for configuration data, with a single interface other plugins
and configurations read from. A plugin that wants to keep an API key, or any setting, needs to write it from Lua.
Under the old records that was impossible, so the need could only be met by reaching into internal modules,
which is worse: unsupported, unvalidated and invisible to the documentation.

Configuration is not per directory. A setting written by another plugin that disappeared when the user changed
the working directory would be a defect, not a feature, so a programmatic write has no business choosing a
scope.

The old reading rule then becomes a trap. Record 0006 gave the commands two scopes with no fallback, and the Lua
`get()` inherited the project-first default. With writes always global, `set("api-key", v)` followed by
`get("api-key")` would answer nothing at all.

## Decision

The Lua API is the configuration interface and it reads and writes the global scope:

- `require("kvstore").set({key}, {value})` stores {value} under {key}, always in the global scope. There is no
  scope option. A value of `nil` is rejected, because an absent value is not a value; use `:KVDelete --global`
  to remove a key. Any value `vim.json` can encode is accepted, per record 0023.
- `require("kvstore").get({key})` looks in the project scope first and answers from the global scope when the
  project has no such key. `get({key}, { global = true })` reads the global scope only.

What the superseded records decided still holds everywhere else, and is restated here so nothing is lost:

- The commands never accept a value as an argument. `:KVStore` takes a key and the optional `--global` flag and
  nothing else, and a second positional argument is still refused.
- A value typed by a person is still only ever read with `inputsecret()`, and empty input still cancels.
- The commands still have no fallback between scopes. `:KVGet token` reads the project and reports a missing key
  rather than answering from the global scope. The fallback belongs to the Lua interface alone, where the caller
  asked for a configuration value rather than for a specific scope.
- There is still no public `delete`.

## Consequences

A value can now reach the vault from a configuration file or a script. That is a deliberate widening of the
threat model and the reason this record exists: a caller that writes a literal secret into `init.lua` and then
stores it has not protected anything, because the plaintext is still in the file and usually in version control.
The help file says so where `set()` is documented. The plugin can no longer claim that a stored value was never
anywhere else, only that the vault itself does not leak it.

Reading has a precedence rule where it had none, so a key present in both scopes answers from the project and
the global value becomes unreachable through the default read. This is the ambiguity record 0006 avoided on
purpose, accepted here because a configuration reader wants the most specific value and does not want to know
which scope held it. Anyone needing certainty passes `global = true`.

`set()` writing only to the global scope means a project-scoped value can still only be created by `:KVStore`,
which keeps the interactive path as the only way to get a per-project secret.
