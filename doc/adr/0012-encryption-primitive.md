# 0012. Encryption is implemented in pure Lua with ChaCha20 and HMAC-SHA256

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

Neovim has no built-in encryption. Three options were weighed, and the first two were measured rather than
assumed.

An external tool fails on availability. `openssl` is not present on a clean Windows installation: on the
development machine it exists only inside Git Bash at `/mingw64/bin/openssl`, which is not on the PATH a Neovim
process inherits. `age` refuses to read a passphrase from a stdin that is not a terminal, which breaks headless
use, and an age identity file would need exactly the protection the master key already needs. Any external tool
also makes the vault unopenable on a machine that lacks it.

A pure Lua implementation was measured on Neovim 0.12.1 with LuaJIT 2.1:

- `vim.uv.random()` provides a cryptographically secure random source with no external tool.
- `vim.fn.sha256()` is byte exact. It hashes an embedded NUL correctly, differs from the same input with a
  newline in place of the NUL, and its output for `"\0"` and `"\xff"` matches the published SHA-256 vectors.
  Standard HMAC-SHA256 can therefore be built on the built-in hash instead of reimplementing SHA-256 in Lua.
- A ChaCha20 block function written with the `bit` library reproduces the RFC 8439 section 2.3.2 test vector and
  runs at roughly 294 MiB/s, three orders of magnitude more than a vault of a few kilobytes needs.

A hybrid of the two was rejected: two code paths, two formats to version and test, and a vault that opens on one
machine and not on another.

## Decision

Encryption is implemented in Lua inside the plugin, with no external tool. The construction is encrypt-then-MAC:
ChaCha20 for confidentiality (RFC 8439), HMAC-SHA256 for authentication (RFC 4231) built on `vim.fn.sha256`, and
HKDF-SHA256 for key derivation (RFC 5869). All randomness comes from `vim.uv.random()`. Tags are compared in
constant time. `crypto.lua` is the only module that knows the primitive, and it spawns no process.

## Consequences

The vault opens on any supported system with no tool detection and no installation step, and no secret can leak
through a process argument because no process is involved. The cost is that the plugin owns cryptographic code,
which is the one place where a mistake is silent. That is contained by using only specified primitives, by
landing the official test vectors before any plugin code calls them, by verifying the tag before decrypting, and
by deriving a fresh encryption key on every write so that nonce reuse is structurally impossible.

One implementation note: LuaJIT prints a negative int32 through `string.format("%08x")` as a sign-extended
sixteen-digit value, so `bit.tohex` is used for word formatting.
