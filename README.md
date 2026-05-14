# githerd

Sync a herd of Git repositories **in parallel** from one Windows command, with live progress bars and an optional GUI for editing the config.

```
my-repo-a             [####################] 100% OK
my-repo-b             [###############-----]  78% pulling
my-repo-c             [#########-----------]  45% fetching origin
my-repo-d             [###############-----]  78% pushing
```

---

## Requirements

- Windows 10 / 11 (PowerShell 5+ ships in-box).
- `git` on `PATH`.
- A console that supports ANSI escapes (Windows Terminal or modern `cmd.exe`) for the live bars.

---

## Quick start

Drop the `githerd\` folder next to the repos you want to sync, then from that parent folder:

```bat
REM Open the GUI to set up your repos (and optional final command)
githerd\sync.bat --config

REM Sync everything
githerd\sync.bat
```

That's it. The GUI's **Save && Run** button does both in one click.

---

## Minimal config

`config.json` (created by the GUI, or copy `config.example.json`):

```json
{
    "repos": [
        { "name": "my-repo-a", "path": ".\\my-repo-a",         "master": "main", "auto_merge": true  },
        { "name": "my-repo-b", "path": "C:\\code\\my-repo-b",  "master": "main", "auto_merge": false }
    ],
    "final_command": "",
    "max_wait_seconds": 600
}
```

| Field | Quick meaning |
|---|---|
| `name` | Friendly label / log file name. |
| `path` | Absolute (`C:\code\repo`) or relative to where you launch `sync.bat`. |
| `master` | The branch to sync (e.g. `main`, `master`, `dev`). |
| `auto_merge` | `true` = fetch upstream + ff-merge + push origin. `false` = just `git pull origin <master>`. |
| `final_command` | Optional command to run once after all repos finish (`""` to skip). |

> Tip: in the GUI, select a repo and use **Browse…** to insert a correctly-escaped absolute path.

Full schema, restrictions, and the relative-path rules: see [`docs/configuration.md`](docs/configuration.md).

---

## More docs

- [Configuration reference](docs/configuration.md) — every field, path rules, JSON escaping, restrictions.
- [How it works](docs/how-it-works.md) — folder layout, per-repo phase workflow, UI ↔ sync handshake.
- [UI design](docs/ui-design.md) — how the WPF config window maps to [`DESIGN.md`](DESIGN.md).
- [Troubleshooting](docs/troubleshooting.md) — common failures and fixes.
- [Reference](docs/reference.md) — exit codes and per-repo status strings.

---

## License

MIT — see [LICENSE](LICENSE).
