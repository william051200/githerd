# Configuration

All settings live in `config.json` next to `sync.bat`. The file is gitignored — your real config is never committed. A template lives at `config.example.json`.

You can edit `config.json` by hand, or use the GUI (`sync.bat --config`). The UI auto-seeds from `config.example.json` on a fresh clone.

---

## Schema

```json
{
  "config_version": 1,
  "working_dir": "C:\\code",
  "repos": [
    {
      "name": "my-repo-a",
      "path": "my-repo-a",
      "master_remote": "upstream",
      "master": "main",
      "auto_merge": true
    }
  ],
  "final_command": "",
  "max_wait_seconds": 600
}
```

| Field | Type | Description |
|---|---|---|
| `config_version` | integer | Persisted configuration schema version. The current schema is `1`; it is independent from the GitHerd application version. |
| `working_dir` | string | Root folder for relative repo paths and the post-sync command. Leave `""` to fall back to the shell's current directory (preserves pre-1.x behavior). |
| `repos[].name` | string | Friendly name; also used as the log file name. Must be unique. |
| `repos[].path` | string | Path to the repo. Absolute or relative to `working_dir`. See [Filling in `path`](#filling-in-path) below. |
| `repos[].master` | string | The "master" branch for that repo (e.g. `main`, `master`, `dev`). |
| `repos[].master_remote` | string | Remote that owns the latest code. Used as the source in both modes. Legacy configs default to `upstream` for auto-merge and `origin` for pull-only. |
| `repos[].auto_merge` | bool | `true` = fetch/prune and ff-merge `master_remote/<master>`, then push to `origin`. `false` = pull/prune `master_remote/<master>`. |
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
- `repos[].master_remote` must not start with `-` or contain whitespace or CMD metacharacters (`"`, `&`, `|`, `<`, `>`, `^`, `%`, `!`, `(`, `)`). Names such as `work@github` and `team+mirror` are supported.

## Choosing a master repo and sync mode

The repository editor has two separate controls:

- **Master repo** selects the remote that owns the latest code.
- **Auto-merge latest code into the configured master branch** fetches and fast-forwards from the selected remote, then pushes the result to `origin`.
- With auto-merge off, GitHerd runs `git pull --prune <master_remote> <master>`.

Remote choices are discovered with `git -C <repo> remote`. If the repository is unavailable or discovery fails, the saved remote remains selectable and `origin` is included as a fallback. GitHerd does not infer which remote is authoritative.

For backward compatibility, configs without `master_remote` retain the old behavior: auto-merge uses `upstream`, while pull-only uses `origin`. Pull-only configs containing the earlier `pull_remote` field are migrated when saved.

## Schema versions and migration

GitHerd reads all configuration through `lib\config.ps1`. A missing
`config_version` identifies legacy schema v0. GitHerd migrates v0 to v1 in
memory, preserves an existing non-empty `master_remote`, otherwise uses
`pull_remote` for pull-only projects, `upstream` for auto-merge projects, and
`origin` for other projects. The obsolete `pull_remote` field is removed from
the current model.

Migrations are sequential: future releases apply every intermediate version
in order. Invalid, non-positive, non-integer, unsupported, and newer schema
versions fail explicitly. Reading or importing never rewrites the source;
Save, Save & Run, and Export persist the current schema.

## Canonical JSON and portable exports

Saved configs, `config.example.json`, and exports use the same canonical JSON:
UTF-8 without a BOM, two-space indentation, stable property order, no trailing
whitespace, and one final newline. Writes use a temporary file in the
destination directory and atomically replace the destination so a failed save
does not truncate the previous config.

Exports remain versioned v1 configs. They preserve project names, remotes,
branches, sync modes, the final command, and timeout, but blank `working_dir`
and every project `path`. Imported files use the normal parse, migration,
normalization, and validation pipeline before the UI state is replaced.

## Configuration errors

Malformed JSON, missing required project fields, duplicate project names,
unsafe values, failed migrations, and unsupported schema versions are errors.
GitHerd reports the schema version and affected field or project instead of
silently replacing invalid data with an empty config.
