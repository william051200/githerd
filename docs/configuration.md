# Configuration

All settings live in `config.json` next to `sync.bat`. The file is gitignored — your real config is never committed. A template lives at `config.example.json`.

You can edit `config.json` by hand, or use the GUI (`sync.bat --config`). The UI auto-seeds from `config.example.json` on a fresh clone.

---

## Schema

```json
{
    "working_dir": "C:\\code",
    "repos": [
        { "name": "my-repo-a", "path": "my-repo-a",                     "master": "main",   "auto_merge": true  },
        { "name": "my-repo-b", "path": "C:\\code\\my-repo-b",           "master": "master", "auto_merge": false },
        { "name": "my-repo-c", "path": "..\\other-projects\\my-repo-c", "master": "main",   "auto_merge": false }
    ],
    "final_command": "",
    "max_wait_seconds": 600
}
```

| Field | Type | Description |
|---|---|---|
| `working_dir` | string | Root folder for relative repo paths and the post-sync command. Leave `""` to fall back to the shell's current directory (preserves pre-1.x behavior). |
| `repos[].name` | string | Friendly name; also used as the log file name. Must be unique. |
| `repos[].path` | string | Path to the repo. Absolute or relative to `working_dir`. See [Filling in `path`](#filling-in-path) below. |
| `repos[].master` | string | The "master" branch for that repo (e.g. `main`, `master`, `dev`). |
| `repos[].auto_merge` | bool | `true` = fetch `upstream` + ff-merge `upstream/<master>` + push to `origin`. `false` = just `git pull origin <master>`. |
| `final_command` | string | Command run **after** all repos complete (sequentially, from `working_dir`). Set to `""` to skip. |
| `max_wait_seconds` | number | Hard timeout (seconds) for any worker. After this, still-running workers are marked `FAILED (timeout)`. Default: `600`. |

---

## Filling in `path`

`path` accepts either form:

### 1. Absolute path

Always works regardless of `working_dir`. Recommended for repos that live outside the working directory.

```json
"path": "C:\\Users\\you\\code\\my-repo-a"
```

> JSON requires backslashes to be escaped, so write `C:\\code\\repo`, not `C:\code\repo`. The **Browse…** button in the UI fills this in correctly for you — and auto-shortens the result to a name under `working_dir` when applicable.

### 2. Relative path

Resolved against `working_dir` if it is set. If `working_dir` is empty, the path is resolved against the **current working directory** at the time you launch `sync.bat`.

With `"working_dir": "C:\\code"` and the folder layout below:

```
C:\code\
├── my-repo-a\
├── my-repo-b\
└── my-repo-c\
```

…you can write the short form:

```json
"path": "my-repo-a"
```

If you're unsure, use **Browse…** in the UI — it opens at the working directory and stores the chosen folder as a short relative name whenever possible.

---

## Restrictions

- `working_dir`, `repos[].name`, `repos[].path`, `repos[].master`, and `final_command` **must not contain double-quote characters** — `cmd.exe`'s `set "VAR=..."` syntax can't safely round-trip them. Use unquoted paths instead; spaces in paths are fine.
