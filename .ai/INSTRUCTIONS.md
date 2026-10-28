# Project Instructions

Rules for every change made in this repository. This is a Neovim plugin written in Lua that stores encrypted values, so security and portability rules are strict.

## Boundaries

**Always**
- Run the formatter and the linter before committing.
- Add or update tests for every behavior change.
- Record every architecture decision as an ADR before implementing it.
- Read `doc/adr/` before proposing a change that touches architecture.

**Ask first**
- Adding a dependency of any kind, including external executables.
- Changing command names, flags or any other public interface.
- Changing the vault format or any cryptographic choice.
- Raising the minimum supported Neovim version.

**Never**
- Commit secrets, keys, tokens or `.env` files.
- Skip hooks (`--no-verify`) or force push to a shared branch.
- Edit an accepted ADR. Supersede it with a new one.
- Edit generated files such as `doc/tags`.
- Commit anything that names or credits an AI tool or model. See [Commits](#commits).

## Language

- All code is written in English: identifiers, strings, error messages and comments.
- All documentation is written in English.

## Code Style

- Follow Clean Code: small functions, one responsibility per module, intention-revealing names.
- Format with StyLua and lint with luacheck. Their config files are versioned in the repository root.

```bash
stylua .
stylua --check .
luacheck lua tests
```

## Comments

- Keep comments to the minimum possible.
- Make the code self-explanatory through naming and structure.
- Comment only when the reason behind a decision is not obvious from the code.
- Never comment what the code already says.

## Tests

- Tests live in `tests/` and mirror the structure of `lua/kvstore/`: `lua/kvstore/foo.lua` is tested by `tests/foo_spec.lua`.
- The test runner is defined by an ADR.
- Tests must never use real secrets and must never write to the real OS keystore or the real vault. Use fakes and temporary directories.

## Security Rules

These rules must never be broken, even for convenience, debugging or refactoring.

- A secret value is only ever read with `inputsecret()`. Commands never accept it as an argument.
- A secret value is passed to external tools through stdin, never through command-line arguments or environment variables.
- A secret value is never written to a register, the command history, the ShaDa file, a log, a notification or an error message.
- The only exception is `:KVGet`, which prints the value with `nvim_echo(chunks, false, {})` so it is not added to the message history.
- A secret value is never stored anywhere except the encrypted vault.
- Empty input cancels the operation. It is never stored as a value.
- Keep secret values in memory only as long as strictly needed.

## Cross-Platform

The plugin is developed on macOS, Windows and Linux. Code must behave the same on all three.

- Build paths with `vim.fs` and `vim.uv`. Never concatenate paths with a hardcoded `/` or `\`.
- Never assume a shell. Run external processes with an argument list, never a shell string.
- Never assume tools exist. Detect them and fail with a clear error message.
- Keep file names lowercase so `require` behaves the same on case-insensitive filesystems.
- Keep line endings as LF. See `.gitattributes`.
- File permission handling must have an equivalent for Windows.

## Neovim Version

- The minimum supported Neovim version is recorded in an ADR.
- Do not use APIs introduced after that version, and do not use deprecated APIs.

## Documentation

- All documentation lives in `doc/`. Do not create documentation files elsewhere.
- The `:help` file is `doc/kvstore.txt`. Update it whenever a command, flag or behavior changes.
- Keep documentation in sync with the code. Outdated documentation is a bug.

## Architecture Decision Records

- Every architecture decision is an ADR in `doc/adr/`.
- Each ADR is a separate file named `<id>-<slug>.md`, where `<id>` is a zero-padded sequential number (`0001`, `0002`, ...) and `<slug>` is a short kebab-case title.
- Ids are never reused or renumbered.
- `doc/adr/README.md` lists all ADRs ordered by id.
- Each ADR starts with its creation date and time, always in UTC+00 (ISO 8601, `YYYY-MM-DDTHH:MM:SSZ`).
- An accepted ADR is not edited. To change a decision, create a new ADR and mark the old one as superseded.
- Use this structure:

```markdown
# <id>. <Title>

- Date: YYYY-MM-DDTHH:MM:SSZ
- Status: Proposed | Accepted | Superseded by <id>

## Context

## Decision

## Consequences
```

## Commits

Commits follow Conventional Commits: `<type>(<scope>): <subject>`.

**Types**
- `feat`: new behavior visible to the user
- `fix`: bug fix
- `refactor`: code change with no behavior change
- `perf`: performance improvement
- `test`: add or change tests
- `docs`: documentation only, including ADRs
- `build`: build system or dependencies
- `ci`: continuous integration
- `chore`: maintenance that fits no other type
- `revert`: revert a previous commit

**Scopes**
- `commands`: the `:KVStore`, `:KVGet` and `:KVDelete` commands
- `vault`: encrypted storage and the master key
- `backend`: operating system keystore integrations
- `scope`: global and project key resolution
- `docs`: files in `doc/`
- `adr`: files in `doc/adr/`
- `tests`: test infrastructure
- `repo`: repository configuration such as `.gitignore` and `.gitattributes`

A commit that touches several scopes should be split. If that is impossible, omit the scope.

**Subject**
- Imperative mood: "add", not "added" or "adds".
- Lowercase, no trailing period, at most 50 characters.

**Body**
- Optional. Separate it from the subject with a blank line and wrap it at 72 characters.
- Explain why the change was made, not what it does.

**Footer**
- Breaking changes use `!` after the scope and a `BREAKING CHANGE:` footer.
- Reference the related decision with `Refs: ADR-<id>`.

**Rules**
- One logical change per commit.
- Every commit must leave the repository passing format, lint and tests.
- Never rewrite the history of a pushed shared branch.

**AI attribution is forbidden**
- Never commit anything that names or credits an AI tool, assistant or model. This applies to commit messages, trailers, code, comments, documentation, file names and branch names.
- Never add `Co-authored-by` trailers or "generated with" lines.

## Branches

Format: `<type>/<short-description>`.

- `type` is one of the commit types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`.
- The description is lowercase kebab-case, ASCII only, at most 40 characters.
- Describe the change, not the person or the ticket number alone: `feat/global-keys`, `fix/windows-path-hash`, `docs/adr-vault-format`.
- Branch from `main` and keep branches short-lived.
- Delete the branch after it is merged.
