# kvstore.nvim

Store values encrypted on your machine and read them back from Neovim — on macOS, Windows and Linux, with no
external program to install.

```vim
:KVStore github-token    " type the value at a prompt that does not echo it
:KVGet github-token      " print it, without leaving a copy in :messages
```

```lua
local token = require("kvstore").get("github-token")
```

## Why this exists

Every Neovim configuration eventually needs a value it should not contain. An API key for a completion plugin, a
token for a REST client, a database password for a query tool. The usual answers are all uncomfortable:

- **A literal in `init.lua`** — your configuration is normally a git repository, so the secret is in version
  control, in every backup, and on every machine you cloned it to.
- **An environment variable** — it has to be set before Neovim starts, which means it lives in a shell profile
  in plaintext anyway, and it is inherited by every child process Neovim spawns.
- **A plaintext file you `.gitignore`** — ignored by git, but still copied by your backup tool and your sync
  folder, and still readable by anything that can read your home directory.
- **An external password manager CLI** — the strongest option, but it has to be installed, it differs per
  system, and it often cannot unlock without a prompt, so it breaks headless and config-time reads.

kvstore takes the narrow path that covers the common accident: one encrypted file, a master key kept by the
operating system's own keystore, and no external program in the way. It unlocks without a prompt, so reading a
value from your configuration or from a headless session works. Encryption is implemented in the plugin itself,
so a vault opens on any supported system with nothing to install.

It also doubles as a small configuration store. Another plugin can keep its own settings in it and everything
reads them through one interface that behaves the same everywhere.

**Be clear about what this is not.** kvstore protects against *accidental* exposure — a value committed to a
repository, carried into a backup, read over your shoulder, recalled from a history file. It does not protect
you from code already running as your user: anything that can run as you can ask the same keystore for the same
master key. If that is your threat model, you want a password manager that requires a passphrase.

## Features

- **One encrypted file.** Values *and* key names live inside the ciphertext, so the file reveals neither what
  you store nor which projects you have.
- **No external dependencies.** ChaCha20 and HMAC-SHA256 are implemented in Lua against the published RFC test
  vectors; randomness comes from `vim.uv.random()` and hashing from `vim.fn.sha256()`.
- **The master key lives in your system keystore** — Keychain on macOS, DPAPI on Windows and WSL, Secret Service
  on Linux — with an owner-only file as a last resort, and a warning when that happens.
- **Per-project and global values.** The same key name can hold a different value in each project.
- **Secrets never pass through an argument.** Not a command argument, not a process argument, not an environment
  variable. A value typed at the prompt is read with `inputsecret()`, and anything handed to an external tool
  goes on stdin.
- **`:KVGet` leaves no copy.** It prints with `nvim_echo()` and no history, so `:messages` cannot recall it, and
  it never touches a register or the clipboard.
- **A light configuration store.** `set()` from Lua keeps strings, numbers, booleans and tables, and gives them
  back as the type you stored.

## Requirements

Neovim **0.12 or newer**. Nothing else — `setup()` refuses to run on anything older.

The system keystore is used when one is available, through the tool that ships with your system (`security`,
`powershell.exe`, `secret-tool`). When none is available, kvstore falls back to an owner-only file and says so
once.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "areiass36/kvstore.nvim",
  opts = {},
}
```

With Neovim 0.12's built-in plugin manager:

```lua
vim.pack.add({ "https://github.com/areiass36/kvstore.nvim" })
require("kvstore").setup()
```

With any other manager, point it at the repository and call `setup()` yourself.

`setup()` is what creates the commands, so it has to run before `:KVStore`, `:KVGet` and `:KVDelete` exist.
Requiring the plugin without calling it still gives you the Lua API with default options.

## Usage

### Commands

| Command | What it does |
| --- | --- |
| `:KVStore [--global] {key}` | Asks for a value at a prompt that does not echo it, and stores it. |
| `:KVGet [--global] {key}` | Prints the value. |
| `:KVDelete [--global] {key}` | Removes the key. |

All three complete `--global` and the key names of the scope you are addressing.

Storing over an existing key asks before it asks for the value, and the default answer is **No**, so an
absent-minded `<CR>` cannot destroy a value:

```
kvstore: 'github-token' already exists in the project scope. Overwrite?
```

An empty value cancels — nothing is written and an existing value is left alone. A value is never accepted as
an argument, so `:KVStore token hunter2` is refused, and the refusal does not echo what you typed.

### Scopes

Without `--global`, a key belongs to the **current project**, which is Neovim's working directory — the one
`:pwd` reports — with symbolic links resolved. Only the SHA-256 hash of that directory is stored, and the hash
itself is inside the encrypted file.

```vim
:cd ~/work/api
:KVStore database-password        " belongs to ~/work/api only

:KVStore --global github-token    " yours everywhere
```

For the commands the two scopes never mix: `:KVGet token` reads the project and reports a missing key rather
than quietly answering from the global scope.

A subdirectory is a **different** project, and renaming a project directory changes its hash, so its keys look
as though they vanished. They are still in the vault under the old hash.

### Lua API

```lua
local kvstore = require("kvstore")

-- read: the project first, falling back to the global scope
local token, err = kvstore.get("github-token")
if not token then
  vim.notify("kvstore: " .. err, vim.log.levels.WARN)
end

-- read the global scope only
local shared = kvstore.get("github-token", { global = true })

-- write: always global, any value vim.json can encode
kvstore.set("api-key", "k-123")
kvstore.set("retries", 3)
kvstore.set("hosts", { "a.example", "b.example" })
```

`get()` returns the value, or `nil` and a message. It never prints and never notifies — a caller decides what a
missing key means. `set()` returns `true`, or `nil` and a message.

`set()` always writes the **global** scope and takes no scope option: configuration that disappeared when you
changed directory would be a defect rather than a feature. Per-project values come from `:KVStore`.

A value given to `set()` is your responsibility. Storing a literal you wrote into your configuration protects
nothing — the plaintext is still in that file. `set()` is for configuration, and for secrets whose plaintext
source you are about to delete.

There is no public `delete`; use `:KVDelete --global`.

### A worked example

Keeping a token out of your configuration while still using it:

```vim
:KVStore --global github-token
```

```lua
require("some-plugin").setup({
  token = require("kvstore").get("github-token") or "",
})
```

And a plugin keeping its own settings:

```lua
require("kvstore").set("myplugin", { theme = "dark", retries = 3 })

local saved = require("kvstore").get("myplugin")
```

## Configuration

```lua
require("kvstore").setup({
  backend = "auto",
  confirm_value = false,
})
```

| Option | Default | Meaning |
| --- | --- | --- |
| `backend` | `"auto"` | Which keystore holds the master key. `"auto"` detects one. Force it with `"macos"`, `"windows"`, `"wsl"`, `"linux"` or `"file"` — useful to pin `"file"` on a machine whose session keyring is never unlocked. |
| `confirm_value` | `false` | When `true`, `:KVStore` asks for the value twice and stores nothing if the two differ. A prompt that does not echo gives no feedback, so a typo is otherwise invisible until the value fails elsewhere. |

## Where things are stored

Everything lives under `stdpath("data")/kvstore/` — run `:echo stdpath("data")` to see it:

```
vault.kvs       every value, encrypted
master.dpapi    the master key, on Windows and WSL
master.key      the master key, only when the file fallback is in use
```

The vault is a single file: a `KVST` magic, a format version, a fresh 32-byte salt per write, the ciphertext,
and an authentication tag. Each write derives a fresh encryption key from the master key with HKDF-SHA256, so no
key ever sees the same nonce twice; the tag is verified in constant time before anything is decrypted. Writes go
to a temporary file and are renamed over the target, so an interrupted write cannot leave a half-written vault,
and a lock file keeps two Neovim instances from losing each other's entry.

**Back up `vault.kvs` together with the master key.** Either one alone is useless, and if the master key is lost
the vault cannot be recovered.

## Limitations

- A subdirectory of a project is a different project, and moving a project directory hides its keys.
- Message plugins such as noice.nvim and nvim-notify keep their own history of what passes through them, so a
  value printed by `:KVGet` may be retained there. This is also why `:KVGet` never copies to a register — a
  clipboard manager is equally out of reach.
- The file fallback protects the master key from other users, not from programs running as you.
- A headless or SSH session on Linux usually has no Secret Service, so it uses the file fallback.
- `:KVStore` cannot be scripted, because a typed value is only ever read from a prompt. Reading is scriptable.
- No master key rotation, no command to list keys, and no way to move keys between projects or machines.

## Documentation

`:help kvstore` is the full reference. Every design decision is recorded in [`doc/adr/`](doc/adr/README.md),
including the ones that were reconsidered and what replaced them.

## Development

```bash
stylua --check .          # format
luacheck lua tests        # lint
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

Tests need [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) cloned into `.tests/plenary.nvim`. They never
touch a real keystore, a real vault or a real secret — fakes and temporary directories throughout. What the suite
cannot cover is written down in [`doc/manual-checks.md`](doc/manual-checks.md) and run by hand per system.

Before sending a change: run the formatter and the linter, add or update tests, and record any architecture
decision as an ADR first. The full rules are in [`.ai/INSTRUCTIONS.md`](.ai/INSTRUCTIONS.md).
