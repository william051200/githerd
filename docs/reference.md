# Reference

## Exit codes

| Code | Meaning |
|---|---|
| `0`  | All repos OK and the final command (if any) succeeded. |
| `1`  | One or more repos failed, or the final command failed, or config could not be loaded. |
| `2`  | Failed to create the IPC temp directory. |
| `10` | (`ui\config-ui.ps1` only) User clicked **Save && Run**. `sync.bat` handles this internally and falls through to running the sync. |

## Per-repo status strings

| Status | Meaning |
|---|---|
| `OK` | Repo synced successfully. |
| `OK (stashed)` | Synced; the worker auto-stashed and restored a dirty working tree. |
| `OK ... - <branch>` | The worker switched back from the master branch to `<branch>` (where you were). |
| `SKIPPED (path not found)` | Configured `path` didn't exist. |
| `SKIPPED (not a git repo)` | Path exists but contains no `.git` folder. |
| `SKIPPED (pushd failed)` | Could not enter the path (permissions, etc.). |
| `FAILED (<reason>)` | A git command failed; see the per-repo log file. |
| `FAILED (timeout)` | Worker did not finish before `max_wait_seconds`. |
| `MISSING` | Worker process exited without writing a result file (very unusual). |
