# How it works

## Folder layout

```
githerd\
├── sync.bat              # entry point (run sync, or open the UI with --config)
├── config.example.json   # template config (committed)
├── config.json           # your editable configuration (gitignored; created on first save)
├── ui\
│   ├── config-ui.ps1     # WPF editor (host script)
│   ├── MainWindow.xaml   # window layout
│   └── Theme.xaml        # design tokens & control styles
├── lib\
│   └── load-config.ps1   # internal helper (JSON -> set statements)
├── docs\                 # this folder
├── DESIGN.md             # visual design reference for the UI
├── .gitignore
├── LICENSE
└── README.md
```

The whole folder is self-contained — copy or move it anywhere.

---

## Per-repo workflow

Each repo runs in its own background `cmd` worker, in parallel. The worker does:

1. **starting** — sanity-check the path exists and is a Git repo.
2. **stashing** — if the working tree is dirty, `git stash push -u`.
3. **checkout master** — switch to the configured master branch (only if not already there).
4. If `auto_merge: true`:
   - **fetching upstream** — `git fetch upstream <master>`
   - **fetching origin** — `git fetch origin <master>`
   - **merging** — `git merge --ff-only upstream/<master>`
   - **pushing** — `git push origin <master> --no-verify`
5. If `auto_merge: false`:
   - **pulling** — `git pull origin <master>`
6. **checkout original** — switch back to the branch you were on.
7. **popping stash** — if step 2 stashed, `git stash pop` (skipped if step 6 failed).

If any step fails, the repo's status becomes `FAILED (<reason>)` and its full log path is printed at the end. The temp folder containing logs is **kept on failure** so you can inspect it.

---

## How the UI talks to the sync

`sync.bat --config` launches `ui\config-ui.ps1` (a WPF window). The UI signals its choice via exit code:

| Exit | Meaning |
|---|---|
| `0`  | Saved (just persist) |
| `2`  | Cancelled |
| `10` | **Save && Run** — `sync.bat` falls through and immediately runs the sync |

Any code other than `10` causes `sync.bat` to terminate without running the sync.

---

## First-time setup (alternatives)

`config.json` is gitignored. On a fresh clone, you can either:

```bat
REM A. copy the template and edit it by hand
copy githerd\config.example.json githerd\config.json

REM B. launch the UI; it auto-seeds from config.example.json on first run,
REM    and writes config.json when you save.
githerd\sync.bat --config
```
