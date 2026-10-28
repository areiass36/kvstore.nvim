# 0013. Vault format version 1

- Date: 2026-10-28T15:02:39Z
- Status: Superseded by 0023

## Context

Record 0008 puts every entry in one encrypted file and record 0012 fixes the primitives. The format still has to
say where the file lives, how it is versioned for later migrations, how it is replaced without a window in which
it is half written, and whether key names are protected.

Encrypting only the values would leave the names and the per-project hashes readable, which leaks what the user
stores and which projects exist. Readable names were considered because command completion could then list them
without the master key. By records 0009 and 0011 the master key is available without a prompt, so completion can
simply decrypt the vault. There is no trade to make: the names are encrypted and completion still works.

## Decision

The vault is `<stdpath("data")>/kvstore/vault.kvs`, built with `vim.fs.joinpath`.

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | magic, `KVST` |
| 4 | 1 | format version, `0x01` |
| 5 | 32 | salt, fresh from `vim.uv.random()` on every write |
| 37 | N | ciphertext |
| 37 + N | 32 | authentication tag |

- `enc_key || mac_key = HKDF-SHA256(ikm = master key, salt = salt, info = "kvstore vault v1")`, 64 bytes.
- The ciphertext is ChaCha20 over the plaintext with an all-zero nonce and the counter starting at 1.
- `tag = HMAC-SHA256(mac_key, magic || version || salt || ciphertext)`, verified in constant time before
  anything is decrypted.
- The plaintext is `{"entries": {"<stored name>": "<value>"}}` encoded as JSON, so key names sit inside the
  ciphertext.
- The whole payload is encrypted as a single blob. There is no per-entry encryption.
- A write goes to a temporary file in the same directory, is flushed, and is renamed over the target.

## Consequences

Key names are protected at rest and completion still works, because completion decrypts. The all-zero nonce is
safe only because the salt, and therefore the derived encryption key, is fresh on every write; no future change
to this format may reuse a salt. The version byte lets a later format be recognised as such instead of being
read as corruption. Rewriting the whole file on every change is linear in vault size, which is irrelevant at a
few kilobytes. A bad tag is reported as a corrupt vault or a wrong master key, with no partial decryption. A
single blob does mean one corrupted byte loses every entry, which is why the write is atomic and why the help
file tells users to back the file up.
