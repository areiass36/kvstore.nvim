# 0016. The public Lua API exposes only setup() and get()

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

Reading a stored value from Lua is the point of the plugin for other plugins and for user configuration: a token
fetched in a config is the common case. A Lua setter is a different matter. It would be the obvious path for a
value to arrive from a configuration file, a script or a repository, which is exactly what record 0001 exists to
prevent.

## Decision

The public API is `require("kvstore").setup(opts)` and `require("kvstore").get(key, opts)`. `get` returns the
value, or nil and an error message. Nothing else is public: no `set`, no `delete`, and no access to `vault`,
`crypto`, `scope` or `keyring`, which may change without notice.

## Consequences

Reading is automatable and writing stays interactive, which keeps record 0001 enforceable. Internal modules can
be refactored freely. A user who wants to seed a vault from a script cannot do so, which follows from 0001 and is
accepted. A caller that passes a value to `get` by mistake gets an error about the key name rather than silently
storing anything.
