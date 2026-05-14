# Configuration

All settings live in `config.json` next to `sync.bat`. The file is gitignored — your real config is never committed. A template lives at `config.example.json`.

You can edit `config.json` by hand, or use the GUI (`sync.bat --config`). The UI auto-seeds from `config.example.json` on a fresh clone.

---

## Schema

```json
{
    "repos": [
        { "name": "my-repo-a", "path": ".\\my-repo-a",                 "master": "main",   "auto_merge": true  },
        { "name": "my-repo-b", "path": "C:\\code\\my-repo-b",          "master": "master", "auto_merge": false },
        { "name": "my-repo-c", "path": "..\\other-projects\\my-repo-c", "master": "main",  "auto_merge": false }
    ],
    "final_command": "",
    "max_wait_seconds": 600
}
```

| Field | Type | Description |
|---|---|---|
| `repos[].name` | string | Friendly name; also used as the log file name. Must be unique. |
| `repos[].path` | string | Path to the repo. Absolute or relative. See [Filling in `path`](#filling-in-path) below. |
| `repos[].master` | string | The "master" branch for that repo (e.g. `main`, `master`, `dev`). |
| `repos[].auto_merge` | bool | `true` = fetch `upstream` + ff-merge `upstream/<master>` + push to `origin`. `false` = just `git pull origin <master>`. |
| `final_command` | string | Command run **after** all repos complete. Set to `""` to skip. |
| `max_wait_seconds` | number | Hard timeout (seconds) for any worker. After this, still-running workers are marked `FAILED (timeout)`. Default: `600`. |

---

## Filling in `path`

`path` accepts either form:

### 1. Absolute path

Always works regardless of where you launch `sync.bat` from. Recommended if you sometimes invoke from different directories.

```json
"path": "C:\\Users\\you\\code\\my-repo-a"
```

> JSON requires backslashes to be escaped, so write `C:\\code\\repo`, not `C:\code\repo`. The **Browse Path...** button in the UI fills this in correctly for you.

### 2. Relative path

Resolved against the **current working directory** when you launch `sync.bat` — **not** against `sync.bat`'s folder.

If your repos sit next to the project folder like this:

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

…and the relative paths would be:

```json
"path": ".\\my-repo-a"
```

If you're unsure, use **Browse Path...** in the UI — it always inserts an absolute path.

---

## Restrictions

- `repos[].name`, `repos[].path`, `repos[].master`, and `final_command` **must not contain double-quote characters** — `cmd.exe`'s `set "VAR=..."` syntax can't safely round-trip them. Use unquoted paths instead; spaces in paths are fine.
