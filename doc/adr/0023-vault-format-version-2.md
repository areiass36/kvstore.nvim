# 0023. Vault format version 2

- Date: 2026-10-28T17:03:58Z
- Status: Accepted

Supersedes 0013.

## Context

Record 0013 defined a format whose entries map a stored name to a string, because every value came from a
prompt. Record 0022 makes the plugin a configuration store written from Lua, where a caller wants to keep a
number, a flag, or a whole table of options, and wants it back as the type it stored.

The values could have been left as strings with each caller serialising its own, but then every plugin using
kvstore would invent a different encoding and `:KVGet` would print something different for each one.

Allowing other types changes what a reader of the file must expect, so the version byte has to move. Measured on
Neovim 0.12.1, `vim.json` round-trips what is needed: an integer stays an integer, a float stays a float, a
boolean and a string keep their type, `null` becomes `vim.NIL` and back, a plain empty table and
`vim.empty_dict()` each come back as themselves, and a value it cannot serialise fails with a clear message
rather than writing something broken.

## Decision

The vault is `<stdpath("data")>/kvstore/vault.kvs`, built with `vim.fs.joinpath`.

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | magic, `KVST` |
| 4 | 1 | format version, `0x02` |
| 5 | 32 | salt, fresh from `vim.uv.random()` on every write |
| 37 | N | ciphertext |
| 37 + N | 32 | authentication tag |

- `enc_key || mac_key = HKDF-SHA256(ikm = master key, salt = salt, info = "kvstore vault v1")`, 64 bytes. The
  info string is unchanged: it names the key derivation, not the payload shape, and changing it would make
  every existing vault unreadable for no benefit.
- The ciphertext is ChaCha20 over the plaintext with an all-zero nonce and the counter starting at 1.
- `tag = HMAC-SHA256(mac_key, magic || version || salt || ciphertext)`, verified in constant time before
  anything is decrypted.
- The plaintext is `{"entries": {"<stored name>": <value>}}` encoded as JSON, where `<value>` is any value
  `vim.json` can encode. Key names stay inside the ciphertext.
- The whole payload is encrypted as a single blob. There is no per-entry encryption.
- A write goes to a temporary file in the same directory, is flushed, and is renamed over the target.

Version 1 is still read, because its entries are strings and a string is a valid version 2 value. Every write
produces version 2, so a vault migrates the first time it is written to, with nothing for the user to do. A
version the plugin does not know is still refused as such rather than read as corruption.

## Consequences

A caller gets back the type it stored, and a plugin keeping a table of options needs no encoding of its own.

A vault written by this version cannot be read by a plugin built against version 1, which is the point of the
version byte: the older code refuses the file instead of handing a table to something expecting a string. The
upgrade is one way, and a user who downgrades the plugin after any write will be told the format is unsupported.

`:KVGet` has to print something for a value that is not a string, so it prints the JSON encoding. That keeps the
output round-trippable and unambiguous, and it still goes through `nvim_echo` with no history.

A value that cannot be serialised is rejected by `set()` before the vault is touched, so a bad call cannot leave
the file in a state where the whole vault fails to encode.
