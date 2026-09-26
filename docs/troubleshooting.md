# Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `[ERROR] Failed to load config from ...` | `config.json` is missing, malformed, invalid for its schema, or could not be migrated. Read the preceding PowerShell error for the affected version and field. Run `sync.bat --config` to fix a valid editable config, or copy `config.example.json` to `config.json`. |
| `config_version must be a positive integer` | `config_version` is zero, negative, text, or another unsupported type. Use an integer schema version; omit the field only for a genuine legacy v0 config. |
| `A newer GitHerd version is required` | The config was written with a schema newer than this installation supports. Update GitHerd before loading it; do not lower the version number manually. |
| `Failed config migration ...` / `Missing config migration ...` | GitHerd could not complete every required schema step. The source file was not rewritten. Keep it intact and update/reinstall GitHerd before retrying. |
| A project shows `FAILED (...)` | Look for the printed log path: `<TEMP>\githerd_<rand>\<name>.log`. The temp folder is **kept on failure** so you can inspect it. |
| A project shows `FAILED (timeout)` | A worker exceeded `max_wait_seconds`. Bump it in the UI (or directly in `config.json`). |
| `SKIPPED (path not found)` | The configured `path` doesn't exist relative to where you ran `sync.bat`. See [configuration.md → Filling in `path`](configuration.md#filling-in-path). |
| `SKIPPED (not a git repo)` | The path exists but isn't a Git working tree (no `.git` folder). |
| Stash kept after a failure | If the worker couldn't return to your original branch, it deliberately does **not** pop the stash. Resolve the branch state manually, then `git stash pop`. |
| No progress bars / weird `^[[2K` characters in the console | Your console doesn't support ANSI escape sequences. Use Windows Terminal or a recent `cmd.exe`. |
| Remote dropdowns only show fallback values | Confirm the project path exists and `git -C <path> remote -v` succeeds. Saved custom selections remain available while discovery is unavailable. |
| Master branch dropdown only shows the saved value | Confirm `git -C <path> branch --format=%(refname:short)` succeeds and the branch exists locally. Remote-tracking branches are intentionally excluded. |
| `git push` fails for a project with `auto_merge: true` | You don't have push access to the selected Development repo, or `--no-verify` isn't enough to bypass a hook. Turn off merge mode or fix that remote's rights. |
| Sync uses the wrong source or destination repository | Open the configuration UI and select the authoritative **Master repo** and destination **Development repo**. |
