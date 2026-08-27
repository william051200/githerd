# githerd

Sync a herd of Git repositories **in parallel** from one Windows command, with live progress bars and an optional GUI for editing the config.

```
my-repo-a             [####################] 100% OK
my-repo-b             [###############-----]  78% pulling
my-repo-c             [#########-----------]  45% fetching origin
my-repo-d             [###############-----]  78% pushing
```

---

## Install

Open **PowerShell** (any version 5.1+) and run:

```powershell
irm https://raw.githubusercontent.com/william051200/githerd/main/install.ps1 | iex
```

This installs GitHerd into `%LOCALAPPDATA%\Programs\GitHerd` and adds it to your user `PATH`. Open a new terminal, then:

```bat
githerd --config       :: open the GUI to set up your repos
githerd                :: sync everything in parallel
```

The GUI's **Save & Run** button does both in one click.

> Other install modes (portable, custom location, specific version) and uninstall steps are in [`docs/install.md`](docs/install.md).

### Updating

```bat
githerd --update          :: install the latest release in place
githerd --update -Check   :: just check, don't install
githerd --version         :: print the installed version
```

GitHerd also pings GitHub at most **once per day after 12:00 PM Malaysia time** and prints a one-line hint at the top of `githerd` when a newer version is out. Set `GITHERD_NO_UPDATE_CHECK=1` to disable the daily ping. Your `config.json` is preserved across updates (and a timestamped backup is written under `%LOCALAPPDATA%\GitHerd\config-backups\` just in case).

---

## Requirements

- Windows 10 / 11 (PowerShell 5.1+ ships in-box).
- `git` on `PATH`.
- A console that supports ANSI escapes (Windows Terminal or modern `cmd.exe`) for the live bars.

---

## Minimal config

`config.json` lives next to `githerd.cmd` and is created by the GUI (or copy `config.example.json`):

```json
{
    "working_dir": "C:\\code",
    "repos": [
        { "name": "my-repo-a", "path": "my-repo-a",            "master": "main", "auto_merge": true  },
        { "name": "my-repo-b", "path": "C:\\code\\my-repo-b",  "master": "main", "auto_merge": false }
    ],
    "final_command": "",
    "max_wait_seconds": 600
}
```

| Field | Quick meaning |
|---|---|
| `working_dir` | Optional root folder. Relative repo `path`s are resolved against it, and `final_command` runs from it. Leave `""` to use the shell's current directory. |
| `name` | Friendly label / log file name. |
| `path` | Absolute (`C:\code\repo`) or relative to `working_dir` (e.g. `my-repo-a`). |
| `master` | The branch to sync (e.g. `main`, `master`, `dev`). |
| `auto_merge` | `true` = fetch/prune upstream and origin + ff-merge + push origin. `false` = pull/prune origin. |
| `final_command` | Optional command to run once after all repos finish (`""` to skip). |

> Tip: in the GUI, select a repo and use **Browse…** to insert a correctly-escaped absolute path.

Full schema, restrictions, and the relative-path rules: see [`docs/configuration.md`](docs/configuration.md).

### Sharing your config

In the config window, use **↑ Import** / **↓ Export** in the top-right
of the page header to swap a `githerd-config.json` file with teammates.
Export writes the full config (repos + post-sync command + timeout); Import
replaces the current state in memory — click **Save** to commit. Repo
paths are machine-specific, so after importing GitHerd flags any paths
that don't exist locally so you can update them before saving.

---

## More docs

- [Install](docs/install.md) — portable mode, custom location, uninstall, troubleshooting the installer.
- [Configuration reference](docs/configuration.md) — every field, path rules, JSON escaping, restrictions.
- [How it works](docs/how-it-works.md) — folder layout, per-repo phase workflow, UI ↔ sync handshake.
- [UI design](docs/ui-design.md) — how the WPF config window maps to [`DESIGN.md`](DESIGN.md).
- [Troubleshooting](docs/troubleshooting.md) — common failures and fixes.
- [Reference](docs/reference.md) — exit codes and per-repo status strings.
- [Release notes format](docs/release-notes.md) — template for GitHub Release bodies (read this before cutting a new tag).

---

## From source

If you'd rather run from a clone:

```bat
git clone https://github.com/william051200/githerd.git
cd githerd
sync.bat --config
```

`sync.bat` and `githerd.cmd` are interchangeable — the latter is just a shim for the brand on `PATH`.

---

## License

MIT — see [LICENSE](LICENSE).
