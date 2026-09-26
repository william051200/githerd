# Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `[ERROR] Failed to load config from ...` | `config.json` is missing, malformed, invalid for its schema, or could not be migrated. Read the preceding PowerShell error for the affected version and field. Run `sync.bat --config` to fix a valid editable config, or copy `config.example.json` to `config.json`. |
| `config_version must be a positive integer` | `config_version` is zero, negative, text, or another unsupported type. Use an integer schema version; omit the field only for a genuine legacy v0 config. |
| `A newer GitHerd version is required` | The config was written with a schema newer than this installation supports. Update GitHerd before loading it; do not lower the version number manually. |
| `Failed config migration ...` / `Missing config migration ...` | GitHerd could not complete every required schema step. The source file was not rewritten. Keep it intact and update/reinstall GitHerd before retrying. |
| A repo shows `FAILED (...)` | Look for the printed log path: `<TEMP>\githerd_<rand>\<name>.log`. The temp folder is **kept on failure** so you can inspect it. |
| A repo shows `FAILED (timeout)` | A worker exceeded `max_wait_seconds`. Bump it in the UI (or directly in `config.json`). |
| `SKIPPED (path not found)` | The configured `path` doesn't exist relative to where you ran `sync.bat`. See [configuration.md → Filling in `path`](configuration.md#filling-in-path). |
| `SKIPPED (not a git repo)` | The path exists but isn't a Git working tree (no `.git` folder). |
| Stash kept after a failure | If the worker couldn't return to your original branch, it deliberately does **not** pop the stash. Resolve the branch state manually, then `git stash pop`. |
| No progress bars / weird `^[[2K` characters in the console | Your console doesn't support ANSI escape sequences. Use Windows Terminal or a recent `cmd.exe`. |
| UI's "Add Repo" button does nothing | You're on a very old PowerShell that mishandled the strongly-typed array cast in `Columns.AddRange`. Make sure you're on PowerShell 5+ (default on Windows 10/11). |
| `git push` fails for a repo with `auto_merge: true` | You don't have push access to that repo's `origin`, or `--no-verify` isn't enough to bypass a hook. Turn off auto-merge to use pull-only mode, or fix the origin rights. |
| Sync uses the wrong source repository | Open the configuration UI and select the authoritative **Master repo** remote. Choices come from `git remote`; legacy auto-merge configs default to `upstream` and pull-only configs default to `origin`. |
