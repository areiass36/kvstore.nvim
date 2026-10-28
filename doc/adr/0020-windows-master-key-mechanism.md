# 0020. The Windows and WSL master key is protected with DPAPI

- Date: 2026-10-28T15:02:39Z
- Status: Accepted

## Context

The Windows backend was planned as the Credential Manager driven through PowerShell. Measured on the development
machine with PowerShell 7.6.5, there is no in-box cmdlet that reads a credential's secret back. `cmdkey.exe` can
store a credential but cannot print one. Neither the `CredentialManager` module nor
`Microsoft.PowerShell.SecretManagement` is installed, and requiring either would add a dependency the user has to
install. The only remaining route to the Credential Manager is to compile a C# P/Invoke wrapper for `CredRead` at
run time with `Add-Type`, which is slow on every read and fragile across runtimes.

DPAPI is the service the Credential Manager is itself built on. `System.Security.Cryptography.ProtectedData` is
part of the in-box .NET surface; a `CurrentUser` round trip was verified on the development machine and produced
a 246-byte blob.

## Decision

On Windows, and on WSL through `powershell.exe`, the master key is protected with DPAPI at `CurrentUser` scope
and the resulting blob is stored in the plugin's data directory. Both the PowerShell script and the key itself
are passed on stdin, so neither appears in an argument list. WSL is detected with the `WSL_DISTRO_NAME`
environment variable.

## Consequences

No module to install and no run-time C# compilation. The blob is useless to another user and on another machine,
which is the protection the Credential Manager would have given. It also means the master key cannot be carried
to another machine, which matches a vault that is not portable anyway. Because the protected blob is a file, it
sits next to the vault in the data directory, so deleting that directory loses the key together with the vault.
The credential does not appear in the Windows Credential Manager interface, so the help file documents where it
lives and how to remove it.
