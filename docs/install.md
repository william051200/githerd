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

### `githerd --update`

The shipped `githerd --update` command is the easy way to upgrade — it
calls the installer for you against your current install directory:

```bat
githerd --update           :: download + install the latest release
githerd --update -Check    :: just print whether an update is available
githerd --update -Force    :: re-install even if you're on the latest tag
githerd --update -Quiet    :: suppress informational output
githerd --version          :: print the installed version and exit
```

Before extracting the new release, the updater copies `config.json` into
`%LOCALAPPDATA%\GitHerd\config-backups\config-<yyyyMMdd-HHmmss>.json` as
a safety net. PATH is left alone (Portable-mode re-install).

### Daily update hint

Every time you run `githerd` (a real sync), it does a tiny background
check at most **once per day after 12:00 PM Malaysia time (UTC+8)** and
prints a one-line hint when a newer version is available:

```
[update] v0.3.0 is available. Run `githerd --update` to install.
```

- **Cache file:** `%LOCALAPPDATA%\GitHerd\update-check.json`
  (`{ last_checked_unix, last_checked_utc, latest_tag }`).
- **Throttle:** between midnight and 12:00 MYT, the network call is
  skipped entirely (cached hint still prints if relevant). After 12:00
  MYT, the call happens once and is cached for the rest of the day.
- **Disable:** set the environment variable `GITHERD_NO_UPDATE_CHECK=1`
  (user, not session — `setx GITHERD_NO_UPDATE_CHECK 1`).
- **Offline / GitHub down:** failures are swallowed silently. The check
  never blocks your sync.

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
