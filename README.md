# githerd

A small Windows tool that syncs multiple Git repositories **in parallel**, with a live per-repo progress bar in the console and a Windows GUI (PowerShell + WinForms) for editing the configuration.

Herd a whole flock of repos with one command.

---

## Features

- Sync any number of repos **concurrently** (each repo runs in its own background `cmd` worker).
- Live progress bars per repo with phase tracking (stashing, fetching, merging, pushing, ...).
- Auto-stash dirty working trees, sync `master`/`main`/`dev`, then restore the original branch and pop the stash.
- Two sync modes per repo:
  - **`auto_merge: true`** &mdash; fetch `upstream`, fast-forward merge into local master, push to `origin`.
  - **`auto_merge: false`** &mdash; just `git pull origin <master>`.
- Optional **final command** that runs after all repos finish (e.g. a build / setup / refresh step).
- All settings live in **`config.json`**, editable from a Windows GUI.

---

## Folder layout

```
githerd\
├── sync.bat              # entry point (run sync, or open the UI)
├── config.example.json   # template config (committed)
├── config.json           # your editable configuration (gitignored; created on first save)
├── config-ui.ps1         # WinForms editor for config.json
├── load-config.ps1       # internal helper (JSON -> set statements)
├── .gitignore
└── README.md             # this file
```

The whole folder is self-contained &mdash; copy or move it anywhere.

---

## First-time setup

`config.json` is **not committed** (it's user-specific and listed in `.gitignore`). On a fresh clone, do one of:

```bat
REM Option A: copy the template and edit it by hand
copy githerd\config.example.json githerd\config.json

REM Option B: launch the UI; it auto-seeds from config.example.json on first run
githerd\sync.bat --config
```

---

## Requirements

- Windows 10 / 11 (or any Windows with PowerShell 5+ &mdash; ships with the OS).
- `git` on `PATH`.
- A console that supports ANSI escape sequences (Windows Terminal or modern `cmd.exe`) for the live progress bars to render correctly.

---

## Quick start

From the directory **above** the project folder (i.e. the directory that contains your repos):

```bat
REM Run the sync using the saved config
githerd\sync.bat

REM Open the configuration UI
githerd\sync.bat --config
githerd\sync.bat -c
githerd\sync.bat /c
```

> Repo paths in `config.json` are interpreted relative to the **current working directory** when `sync.bat` is invoked, not relative to `sync.bat`'s own folder. Run it from the parent folder of your repos.

In the UI you can click **Save** (just persist) or **Save && Run** (persist and immediately start the sync).

---

## `config.json` reference

Example:

```json
{
    "repos": [
        { "name": "my-repo-a", "path": ".\\my-repo-a",                "master": "main",   "auto_merge": true  },
        { "name": "my-repo-b", "path": "C:\\code\\my-repo-b",         "master": "master", "auto_merge": false },
        { "name": "my-repo-c", "path": "..\\other-projects\\my-repo-c","master": "main",  "auto_merge": false }
    ],
    "final_command": "",
    "max_wait_seconds": 600
}
```

| Field | Type | Description |
|---|---|---|
| `repos[].name` | string | Friendly name; also used as the log file name. Must be unique. |
| `repos[].path` | string | Path to the repo. May be **relative** (resolved against the directory you launch `sync.bat` from) or **absolute** (e.g. `C:\code\my-repo`). See [Filling in the `path` field](#filling-in-the-path-field) below. |
| `repos[].master` | string | The "master" branch for that repo (e.g. `main`, `master`, `dev`). |
| `repos[].auto_merge` | bool | `true` = fetch `upstream` + ff-merge + push to `origin`. `false` = just `git pull origin <master>`. |
| `final_command` | string | Command run **after** all repos complete. Set to `""` to skip. **Note:** this actually executes when non-empty. |
| `max_wait_seconds` | number | Hard timeout (seconds) for any repo. Workers still running after this are marked `FAILED (timeout)`. Default: `600`. |

### Filling in the `path` field

`path` accepts either form:

**1. Absolute path** &mdash; always works regardless of where you run `sync.bat` from. Recommended if you sometimes invoke the script from different directories.

```json
"path": "C:\\Users\\you\\code\\my-repo-a"
```

> JSON requires backslashes to be escaped, so write `C:\\code\\repo`, not `C:\code\repo`. The Browse Path... button in the UI fills this in for you.

**2. Relative path** &mdash; resolved against the **current working directory** when you launch `sync.bat`, **not** against `sync.bat`'s folder. So if your repos sit next to the project folder like this:

```
C:\code\
├── githerd\
│   └── sync.bat
├── my-repo-a\
├── my-repo-b\
└── my-repo-c\
```

then from `C:\code\` you would run:

```bat
githerd\sync.bat
```

and the relative paths would be:

```json
"path": ".\\my-repo-a"
```

If you're unsure, pick **Browse Path...** in the UI and select the folder &mdash; it'll insert the absolute path for you.

### Restrictions

- `repos[].name`, `repos[].path`, `repos[].master`, and `final_command` **must not contain double-quote characters** &mdash; `cmd.exe`'s `set "VAR=..."` syntax can't safely round-trip them. Use unquoted paths instead; spaces in paths are fine.

---

## Sync workflow (per repo)

For each repo, the worker does:

1. **starting** &mdash; sanity-check the path exists and is a Git repo.
2. **stashing** &mdash; if the working tree is dirty, `git stash push -u`.
3. **checkout master** &mdash; switch to the configured master branch (only if not already there).
4. If `auto_merge: true`:
   - **fetching upstream** &mdash; `git fetch upstream <master>`
   - **fetching origin** &mdash; `git fetch origin <master>`
   - **merging** &mdash; `git merge --ff-only upstream/<master>`
   - **pushing** &mdash; `git push origin <master> --no-verify`
5. If `auto_merge: false`:
   - **pulling** &mdash; `git pull origin <master>`
6. **checkout original** &mdash; switch back to the branch you were on.
7. **popping stash** &mdash; if step 2 stashed, `git stash pop` (skipped if step 6 failed).

If any step fails the repo's status becomes `FAILED (<reason>)` and its full log path is printed at the end.

---

## Output

The console shows one progress bar per repo:

```
my-repo-a             [####################] 100% OK
my-repo-b             [###############-----]  78% pulling
my-repo-c             [#########-----------]  45% fetching origin
my-repo-d             [###############-----]  78% pushing
```

After all workers finish you'll get a per-repo summary, totals, and (if any failed) the path to each failure's log.

---

## Troubleshooting

- **"Failed to load config from ..."** &mdash; `config.json` is missing or malformed. Run `sync.bat --config` to fix it via the UI.
- **A repo says `FAILED (...)`** &mdash; look for the printed log path: `<TEMP>\githerd_<rand>\<name>.log`. The temp folder is **kept on failure** so you can inspect it.
- **A repo says `FAILED (timeout)`** &mdash; bump `max_wait_seconds` in the UI (or the JSON).
- **`SKIPPED (path not found)` / `SKIPPED (not a git repo)`** &mdash; the configured `path` doesn't exist (relative to where you ran `sync.bat`) or isn't a Git working tree.
- **Stash kept** &mdash; if the worker couldn't return to your original branch, it deliberately does not pop the stash. Resolve the branch state manually, then `git stash pop`.
- **No progress bars / weird `^[[2K` characters** &mdash; your console doesn't support ANSI escapes. Use Windows Terminal or a recent `cmd.exe`.

---

## Exit codes

| Code | Meaning |
|---|---|
| `0`  | All repos OK and final command (if any) succeeded. |
| `1`  | One or more repos failed, or the final command failed, or config could not be loaded. |
| `2`  | Failed to create the IPC temp directory. |
| `10` | (`config-ui.ps1` only) User clicked **Save && Run**. `sync.bat` handles this internally and falls through to running the sync. |

---

## How the UI talks to the sync

`sync.bat --config` launches `config-ui.ps1`. The UI exits with code `10` to signal "Save & Run", and `sync.bat` then proceeds with the normal sync flow using the just-saved config. Any other exit code (`0` plain save, `2` cancel) terminates `sync.bat` without running the sync.
