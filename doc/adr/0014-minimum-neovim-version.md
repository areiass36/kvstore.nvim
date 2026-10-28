# 0014. The minimum supported Neovim version is 0.12

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

The plugin needs `vim.uv` for the CSPRNG and for filesystem calls, `vim.system` for argument-list process
spawning, `vim.fs.joinpath` and `vim.fs.normalize` for paths, `vim.fn.inputsecret`, and `nvim_echo` with a
history flag. All of these exist in 0.10 and later, so the choice is about how far back to support rather than
about capability. The development machine runs 0.12.1, and supporting an older series means either pinning an
older runner or shipping untested claims.

## Decision

The minimum supported version is Neovim 0.12. The guard is `vim.fn.has("nvim-0.12") == 1`, which is the
idiomatic check and means 0.12.0 or later. Continuous integration pins v0.12.1, the version the plugin is
developed against. No API introduced after 0.12.0 is used, and no deprecated API is used.

## Consequences

Users on 0.10 and 0.11 are excluded, which is a real cost and the reason this is recorded rather than assumed.
In exchange there is one Neovim version in the matrix, no version branching in the code, and the newest stable
API is available. `setup()` fails with a clear message on an older version instead of breaking somewhere deeper.
Lowering or raising this bound later is a new record.
