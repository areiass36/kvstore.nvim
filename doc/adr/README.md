# Architecture Decision Records

Every architecture decision in this repository is recorded here as a separate file named `<id>-<slug>.md`.
Ids are sequential and never reused or renumbered. An accepted record is never edited: to change a decision,
add a new record and mark the old one as superseded.

| Id | Title | Status |
| --- | --- | --- |
| 0001 | [Secret values are only entered through inputsecret()](0001-secret-entry-through-inputsecret.md) | Superseded by 0022 |
| 0002 | [An empty value cancels the operation](0002-empty-value-cancels.md) | Accepted |
| 0003 | [Secret values reach external tools through stdin](0003-secrets-through-stdin.md) | Accepted |
| 0004 | [KVGet prints without touching the message history](0004-kvget-prints-without-history.md) | Accepted |
| 0005 | [The project scope is the resolved working directory](0005-project-scope-is-the-working-directory.md) | Accepted |
| 0006 | [Global keys require the --global flag](0006-global-keys-require-a-flag.md) | Superseded by 0022 |
| 0007 | [KVStore confirms before overwriting a key](0007-overwrite-confirmation.md) | Accepted |
| 0008 | [One encrypted vault, independent of the operating system](0008-single-encrypted-vault.md) | Accepted |
| 0009 | [The master key lives in the native keystore with a file fallback](0009-master-key-storage.md) | Accepted |
| 0010 | [macOS, Windows and Linux are supported equally](0010-supported-systems.md) | Accepted |
| 0011 | [Threat model: accidental leaks](0011-threat-model.md) | Accepted |
| 0012 | [Encryption is implemented in pure Lua with ChaCha20 and HMAC-SHA256](0012-encryption-primitive.md) | Accepted |
| 0013 | [Vault format version 1](0013-vault-format.md) | Superseded by 0023 |
| 0014 | [The minimum supported Neovim version is 0.12](0014-minimum-neovim-version.md) | Accepted |
| 0015 | [Tests run on plenary.nvim](0015-test-runner.md) | Accepted |
| 0016 | [The public Lua API exposes only setup() and get()](0016-public-lua-api.md) | Superseded by 0022 |
| 0017 | [The value is entered once by default](0017-value-double-entry.md) | Accepted |
| 0018 | [Key name rules](0018-key-name-rules.md) | Accepted |
| 0019 | [Vault writes are serialised with a lock file](0019-concurrent-instances.md) | Accepted |
| 0020 | [The Windows and WSL master key is protected with DPAPI](0020-windows-master-key-mechanism.md) | Accepted |
| 0021 | [The master key is read once per command](0021-master-key-lifetime.md) | Accepted |
| 0022 | [The Lua API stores values, always in the global scope](0022-lua-api-stores-configuration.md) | Accepted |
| 0023 | [Vault format version 2](0023-vault-format-version-2.md) | Accepted |
