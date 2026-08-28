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

Each repo runs in its own background `cmd` worker, in parallel. Before step 1 each worker resolves its effective directory: if `repos[].path` is absolute it is used as-is, otherwise it is joined onto `working_dir` (or the shell's current directory when `working_dir` is empty). The worker then does:

1. **starting** — sanity-check the path exists and is a Git repo.
2. **stashing** — if the working tree is dirty, `git stash push -u`.
3. **checkout master** — switch to the configured master branch (only if not already there).
4. If `auto_merge: true`:
   - **fetching &lt;master-remote&gt;** — `git fetch --prune <master_remote> <master>`
   - **fetching origin** — `git fetch --prune origin <master>` when the master remote is not `origin`
   - **merging** — `git merge --ff-only <master_remote>/<master>`
   - **pushing** — `git push origin <master> --no-verify`
5. If `auto_merge: false`:
   - **pulling &lt;master-remote&gt;** — `git pull --prune <master_remote> <master>`
6. **checkout original** — switch back to the branch you were on.
7. **popping stash** — if step 2 stashed, `git stash pop` (skipped if step 6 failed).

If any step fails, the repo's status becomes `FAILED (<reason>)` and its full log path is printed at the end. The temp folder containing logs is **kept on failure** so you can inspect it.

Fetch and pull operations prune remote-tracking refs for branches that no longer exist on the corresponding remote. Pruning does not delete local branches. Repositories that take the already-up-to-date fast path skip pruning along with the rest of the sync.

Before stashing or switching branches, the fast path compares the local master SHA with the required remote tips. Pull-only checks `master_remote`; auto-merge also checks `origin` when it is a different remote.

The `final_command` is run **sequentially after all workers finish**, from `working_dir` (or the shell's current directory if `working_dir` is empty).

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
