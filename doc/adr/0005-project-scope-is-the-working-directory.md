# 0005. The project scope is the resolved working directory

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

Keys need to be separated per project. The candidate anchors were the git root, a marker file, or the working
directory. A git root does not exist for every project and would make a key's scope depend on whether a
directory happens to be a repository. The working directory is always defined, is what `:pwd` reports, and is
what the user already thinks of as where they are.

## Decision

The project is Neovim's current working directory, read at the moment each command runs, resolved through
symlinks with `vim.uv.fs_realpath()` and then normalised. The stored name is
`project:<sha256 of the resolved directory>:<key>`.

## Consequences

Resolving symlinks means the same physical directory reached through different links shares one set of keys.
Reading the directory per command means `:cd` changes the active scope immediately, which is consistent with
`:pwd`. Renaming or moving a project directory changes the hash, so its keys appear to vanish, and opening
Neovim in a subdirectory gives a different scope for the same reason; both are documented limitations.
