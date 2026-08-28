# Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `[ERROR] Failed to load config from ...` | `config.json` is missing or malformed. Run `sync.bat --config` to fix it via the UI, or copy `config.example.json` to `config.json` and edit. |
| A repo shows `FAILED (...)` | Look for the printed log path: `<TEMP>\githerd_<rand>\<name>.log`. The temp folder is **kept on failure** so you can inspect it. |
| A repo shows `FAILED (timeout)` | A worker exceeded `max_wait_seconds`. Bump it in the UI (or directly in `config.json`). |
| `SKIPPED (path not found)` | The configured `path` doesn't exist relative to where you ran `sync.bat`. See [configuration.md → Filling in `path`](configuration.md#filling-in-path). |
| `SKIPPED (not a git repo)` | The path exists but isn't a Git working tree (no `.git` folder). |
| Stash kept after a failure | If the worker couldn't return to your original branch, it deliberately does **not** pop the stash. Resolve the branch state manually, then `git stash pop`. |
| No progress bars / weird `^[[2K` characters in the console | Your console doesn't support ANSI escape sequences. Use Windows Terminal or a recent `cmd.exe`. |
| UI's "Add Repo" button does nothing | You're on a very old PowerShell that mishandled the strongly-typed array cast in `Columns.AddRange`. Make sure you're on PowerShell 5+ (default on Windows 10/11). |
| `git push` fails for a repo with `auto_merge: true` | You don't have push access to that repo's `origin`, or `--no-verify` isn't enough to bypass a hook. Turn off auto-merge to use pull-only mode, or fix the origin rights. |
| Sync uses the wrong source repository | Open the configuration UI and select the authoritative **Master repo** remote. Choices come from `git remote`; legacy auto-merge configs default to `upstream` and pull-only configs default to `origin`. |
