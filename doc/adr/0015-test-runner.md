# 0015. Tests run on plenary.nvim

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

The instructions require a test runner to be chosen by a record. Three were weighed. plenary.nvim is the de facto
standard for Neovim plugins, gives busted-style `describe` and `it`, runs under `nvim --headless`, and its
`<module>_spec.lua` convention already matches the naming the instructions require. mini.test is lighter and has
first-class child-Neovim testing, which would suit the headless cases, but has a smaller community. busted
through vusted is the most standard Lua tooling but needs a luarocks toolchain on all three systems, which is
heaviest on Windows.

## Decision

Tests run on plenary.nvim. Specs live in `tests/` as `<module>_spec.lua`, mirroring `lua/kvstore/`. The runner is
invoked as `nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ ..."`.
plenary is cloned into the gitignored `.tests/` directory and is never a runtime dependency of the plugin.

## Consequences

Contributors need nothing beyond git and Neovim, and continuous integration needs no language toolchain for the
test job. The harness in `tests/minimal_init.lua` disables the swap file and sets the ShaDa file to NONE, so a
test can never persist anything it handled. plenary's assertion library is luassert, so its vocabulary is what
specs use.
