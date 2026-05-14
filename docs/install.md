# Install

GitHerd ships as a tiny PowerShell+WPF tool. There's no compiler step and no system services — every install mode is just "extract a folder, optionally put it on `PATH`."

## One-line install (recommended)

Open **PowerShell** (any version 5.1+) and run:

```powershell
irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1 | iex
```

What it does:

1. Looks up the latest release on GitHub.
2. Downloads `githerd-vX.Y.Z.zip` into a temp folder.
3. Extracts it to `%LOCALAPPDATA%\Programs\GitHerd`.
4. Adds that folder to your **user** `PATH` (so you don't need admin rights and other users on the machine aren't affected).
5. Broadcasts an environment-change notification so newly-opened terminals see the change.

After it finishes, **open a new terminal** and run:

```bat
githerd --config       :: open the GUI and set up your repos
githerd                :: sync everything in parallel
```

## Portable install

If you'd rather keep GitHerd self-contained in a folder (USB stick, project tree, etc.) and not touch your `PATH`, pass `-Mode Portable`:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1))) -Mode Portable -Dest C:\tools\githerd
```

You then run it directly:

```bat
C:\tools\githerd\githerd.cmd --config
C:\tools\githerd\githerd.cmd
```

## Install a specific version

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1))) -Version v0.1.0
```

## Skip the PATH update (User mode)

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1))) -NoPath
```

You can then add `%LOCALAPPDATA%\Programs\GitHerd` to your PATH manually whenever you're ready.

## Re-run / upgrade

The installer is **idempotent** — re-running it overwrites the install folder with the latest release. The PATH entry is added at most once. Your `config.json` (if you placed it next to `githerd.cmd`) is **preserved** across upgrades.

## Uninstall

There's no registry entry; just remove the folder and the PATH line.

```powershell
# Per-user install
$dir = "$env:LOCALAPPDATA\Programs\GitHerd"
Remove-Item -Recurse -Force $dir

# Remove from user PATH
$current = [Environment]::GetEnvironmentVariable('Path','User')
$cleaned = ($current -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $dir.TrimEnd('\') }) -join ';'
[Environment]::SetEnvironmentVariable('Path', $cleaned, 'User')
```

For a portable install, just delete the folder you chose.

## Troubleshooting

### `irm … | iex` errors with "execution policy"

Run PowerShell with the bypass flag for that one command:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1 | iex"
```

This does **not** change your machine-wide policy.

### `githerd` isn't recognised after install

You probably need a **new** terminal. The installer broadcasts a settings-change message but already-running shells (especially VS Code's integrated terminal) often cache `PATH` and need to be reopened.

### "Could not query GitHub releases API"

Either you're offline, or no release has been cut yet on the repo. Pass `-DevZip <localZip>` against a ZIP you built yourself (`scripts\build-release.ps1`), or `-Version vX.Y.Z` once a tag exists.

### "Cannot run scripts on this system" when you launch the UI

`sync.bat` and `config-ui.ps1` use the user `RemoteSigned` policy by default; if your org enforces `AllSigned`, ask IT for an exception or use the bypass-flag pattern above when launching.
