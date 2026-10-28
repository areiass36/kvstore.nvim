# Manual checks

The test suite never touches a real keystore, a real vault or a real secret: it uses fakes and temporary
directories throughout. These checks are what covers the rest, and they are run by hand on each supported
system before a release.

Record the result in the release notes as `system / Neovim version / date`.

## Preparation

Point Neovim at a throwaway data directory so nothing here touches your own vault:

```bash
export XDG_DATA_HOME="$(mktemp -d)"
nvim --clean -c 'lua vim.opt.runtimepath:prepend("/path/to/kvstore.nvim"); require("kvstore").setup()'
```

Confirm the directory is the throwaway one with `:echo stdpath("data")` before storing anything.

## 1. Backend detection

```vim
:lua print(require("kvstore.keyring").detect().name)
```

| System | Expected | Needs |
| --- | --- | --- |
| macOS | `macos` | `security`, part of the system |
| Windows | `windows` | `powershell.exe` |
| WSL | `wsl` | `powershell.exe` reachable through interop |
| Linux desktop | `linux` | `secret-tool` and a running session bus |
| Linux over SSH, headless | `file` | nothing |

If a Linux desktop reports `file`, check `secret-tool --version` and `echo $DBUS_SESSION_BUS_ADDRESS`. That
combination is the documented reason for the fallback, not a defect.

## 2. Master key round trip on the real keystore

```vim
:lua local k = require("kvstore.keyring"); local b = k.detect()
:lua print(b.exists(), #(b.get() or ""))
```

- Before anything is stored, `exists()` is `false`.
- After the first `:KVStore`, `exists()` is `true` and `get()` returns 32 bytes.
- The key survives restarting Neovim: `:KVGet` still works in a new session.
- The key survives a reboot. This is the check that catches a keystore item stored per session.

## 3. The commands end to end

```vim
:KVStore demo          " type a value, note what you typed
:KVGet demo            " prints exactly what you typed
:KVStore demo          " answer No, then check the value is unchanged
:KVStore demo          " answer Yes, store something else, check it changed
:KVStore --global demo " a different value
:KVGet demo            " still the project value
:KVGet --global demo   " the global value
:KVDelete demo
:KVGet demo            " an error naming the project scope
```

Also confirm by eye:

- The value is not echoed while typing it.
- Pressing `<CR>` at an empty prompt cancels and stores nothing.
- The overwrite question defaults to No, and `<Esc>` ends the command.
- `:KVStore demo somevalue` is refused, and the refusal does not show `somevalue`.
- Pressing `<Tab>` after `:KVGet ` completes `--global` and the stored key names.

## 4. The leak sweep

With a value stored and printed at least once in the session:

```vim
:messages                       " the value must not appear
:registers                      " the value must not appear
:lua vim.cmd("wshada!")
```

Then, outside Neovim, search the files for the value you typed:

```bash
grep -c 'the-value-you-typed' "$XDG_DATA_HOME"/nvim/shada/* 2>/dev/null
grep -c 'the-value-you-typed' "$XDG_DATA_HOME"/nvim-data/kvstore/vault.kvs 2>/dev/null
```

Both must report `0`. Also grep the vault for the key name: it is encrypted too, so `demo` must not appear
either.

## 5. The master key never reaches an argument list

While a `:KVStore` is running, the keystore tool is a child process. On a system with `ps`, watch for it:

```bash
while true; do ps -eo args | grep -E 'security|secret-tool|powershell' | grep -v grep; sleep 0.05; done
```

No line may contain the master key in base64. The suite asserts this against a fake runner for every backend;
this check confirms the same against the real one.

## 6. File fallback permissions

Force the fallback and inspect the file:

```vim
:lua require("kvstore").setup({ backend = "file" })
:KVStore fallback-demo
```

- A warning appears once per session, saying the protection is weaker and naming the file.
- Unix: `ls -l "$XDG_DATA_HOME"/nvim/kvstore/master.key` shows `-rw-------`.
- Windows: `icacls master.key` shows no inherited entries and only your account.

## 7. Two instances at once

Open two Neovim sessions on the same machine:

1. In the first, store `one`.
2. In the second, store `two`.
3. In either, confirm both keys are present.

Neither write may lose the other. If a write reports that the vault is locked, retrying must succeed.
