@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM githerd  ::  sync.bat
REM
REM   Syncs each configured git repo concurrently. Each repo
REM   runs in its own background cmd process; full output goes
REM   to a per-repo log file. The parent prints one line per
REM   phase change ([repo] phase) and waits for all workers to
REM   finish before running the configured final command and
REM   printing the summary.
REM
REM   Per repo:
REM     * If working tree is dirty -> auto-stash, sync, pop stash
REM     * Switch to master branch
REM     * Fetch upstream + origin
REM     * If auto_merge=true: ff-merge upstream/master, push to origin
REM       Else: pull from origin
REM     * Switch back to the original working branch
REM     * Pop stash (only if branch was successfully restored)
REM
REM   Usage:
REM     sync.bat                 Run the sync (default).
REM     sync.bat --config        Open the configuration UI.
REM     sync.bat -c              Same as --config.
REM     sync.bat /c              Same as --config.
REM     sync.bat --update        Update GitHerd to the latest release.
REM     sync.bat -u              Same as --update.
REM     sync.bat --version       Print the installed version and exit.
REM     sync.bat -v              Same as --version.
REM
REM   Configuration is stored in config.json (next to this script).
REM ============================================================

REM --- Resolve script directory and config paths ---
set "SCRIPT_DIR=%~dp0"
set "CONFIG_PATH=%SCRIPT_DIR%config.json"
set "UI_SCRIPT=%SCRIPT_DIR%ui\config-ui.ps1"
set "LOADER_PS=%SCRIPT_DIR%lib\load-config.ps1"
set "UPDATE_PS=%SCRIPT_DIR%lib\update.ps1"
set "UPDATE_CHECK_PS=%SCRIPT_DIR%lib\update-check.ps1"
set "VERSION_FILE=%SCRIPT_DIR%VERSION"

REM ===== Help dispatch =====================================================
if /I "%~1"=="--help" goto :print_help
if /I "%~1"=="-h"     goto :print_help
if /I "%~1"=="/?"     goto :print_help
goto :after_help_dispatch

:print_help
set "GH_VER=unknown"
if exist "%VERSION_FILE%" set /p GH_VER=<"%VERSION_FILE%"
echo githerd v!GH_VER! - parallel multi-repo git sync
echo.
echo Usage:
echo   githerd                          Sync all configured repos in parallel.
echo   githerd --config, -c, /c         Open the configuration UI.
echo   githerd --update, -u             Install the latest GitHerd release.
echo   githerd --version, -v            Print the installed version.
echo   githerd --help, -h, /?           Show this help.
echo.
echo Run "githerd [command] -h" for command-specific help.
echo.
echo More: https://github.com/william051200/githerd
endlocal & exit /b 0

:help_config
echo githerd --config  ^(aliases: -c, /c^)
echo.
echo Open the configuration UI to add/remove repos, set the post-sync
echo command, and adjust the per-repo timeout. Saved settings are written
echo to config.json next to githerd. If you click "Save & Run", the sync
echo starts immediately after closing the UI.
endlocal & exit /b 0

:help_update
echo githerd --update  ^(alias: -u^)
echo.
echo Download and install the latest GitHerd release from GitHub. Your
echo config.json is preserved; a timestamped backup is written to
echo %%LOCALAPPDATA%%\GitHerd\config-backups\.
echo.
echo Flags:
echo   -Check, -c    Print whether an update is available; do not install.
echo   -Force, -f    Re-install even if already on the latest version.
echo   -Quiet, -q    Suppress informational output.
echo.
echo Examples:
echo   githerd --update
echo   githerd --update -Check
echo   githerd --update -c
echo   githerd --update -Force
endlocal & exit /b 0

:help_version
echo githerd --version  ^(alias: -v^)
echo.
echo Print the installed GitHerd version ^(read from the VERSION file next
echo to githerd^) and exit.
endlocal & exit /b 0

:after_help_dispatch

REM ===== Version dispatch ===================================================
if /I "%~1"=="--version" (
    if /I "%~2"=="-h"     goto :help_version
    if /I "%~2"=="--help" goto :help_version
    if /I "%~2"=="/?"     goto :help_version
    goto :print_version
)
if /I "%~1"=="-v" (
    if /I "%~2"=="-h"     goto :help_version
    if /I "%~2"=="--help" goto :help_version
    if /I "%~2"=="/?"     goto :help_version
    goto :print_version
)
goto :after_version_dispatch

:print_version
if exist "%VERSION_FILE%" (
    set /p GH_VER=<"%VERSION_FILE%"
    echo githerd v!GH_VER!
) else (
    echo githerd ^(version unknown^)
)
endlocal & exit /b 0

:after_version_dispatch

REM ===== Update dispatch ====================================================
if /I "%~1"=="--update" (
    if /I "%~2"=="-h"     goto :help_update
    if /I "%~2"=="--help" goto :help_update
    if /I "%~2"=="/?"     goto :help_update
    goto :launch_update
)
if /I "%~1"=="-u" (
    if /I "%~2"=="-h"     goto :help_update
    if /I "%~2"=="--help" goto :help_update
    if /I "%~2"=="/?"     goto :help_update
    goto :launch_update
)
goto :after_update_dispatch

:launch_update
where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell is required to run the updater.
    endlocal & exit /b 1
)
shift
powershell -NoProfile -ExecutionPolicy Bypass -File "%UPDATE_PS%" %1 %2 %3 %4 %5 %6 %7 %8 %9
endlocal & exit /b %ERRORLEVEL%

:after_update_dispatch

REM ===== UI dispatch (must run BEFORE config load so we can use UI to fix a bad config) ===
if /I "%~1"=="--config" (
    if /I "%~2"=="-h"     goto :help_config
    if /I "%~2"=="--help" goto :help_config
    if /I "%~2"=="/?"     goto :help_config
    goto :launch_ui
)
if /I "%~1"=="-c" (
    if /I "%~2"=="-h"     goto :help_config
    if /I "%~2"=="--help" goto :help_config
    if /I "%~2"=="/?"     goto :help_config
    goto :launch_ui
)
if /I "%~1"=="/c" (
    if /I "%~2"=="-h"     goto :help_config
    if /I "%~2"=="--help" goto :help_config
    if /I "%~2"=="/?"     goto :help_config
    goto :launch_ui
)
goto :after_ui_dispatch

:launch_ui
where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell is required to run the configuration UI.
    endlocal & exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%UI_SCRIPT%" "%CONFIG_PATH%"
set "UI_RC=%ERRORLEVEL%"
if "%UI_RC%"=="10" (
    echo [INFO] Configuration saved. Starting sync...
    goto :after_ui_dispatch
)
endlocal & exit /b %UI_RC%

:after_ui_dispatch

REM ===== Daily update check (silent, throttled) =============================
where powershell >nul 2>&1
if not errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%UPDATE_CHECK_PS%"
)

REM ===== Load config from JSON =====================================
where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell is required to load config.json.
    endlocal & exit /b 1
)

if not exist "%CONFIG_PATH%" (
    echo [ERROR] Config file not found: %CONFIG_PATH%
    if exist "%SCRIPT_DIR%config.example.json" (
        echo [INFO]  A template exists at: %SCRIPT_DIR%config.example.json
        echo [INFO]  Either copy it to config.json, or run "%~nx0 --config" to create one via the UI.
    ) else (
        echo [INFO]  Run "%~nx0 --config" to create one.
    )
    endlocal & exit /b 1
)

REM Workers can race on %RANDOM% (same cmd start time -> same seed); make the
REM loader path unique by including a per-role tag so two workers never collide.
if /I "%~1"=="--worker" (
    set "LOADER_CMD=%TEMP%\githerd_loader_w%~2_%RANDOM%_%RANDOM%.cmd"
) else (
    set "LOADER_CMD=%TEMP%\githerd_loader_p_%RANDOM%_%RANDOM%_%RANDOM%.cmd"
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOADER_PS%" "%CONFIG_PATH%" "%LOADER_CMD%"
if errorlevel 1 (
    echo [ERROR] Failed to load config from %CONFIG_PATH%
    if exist "%LOADER_CMD%" del /q "%LOADER_CMD%" >nul 2>&1
    endlocal & exit /b 1
)
call "%LOADER_CMD%" >nul 2>&1
if exist "%LOADER_CMD%" del /q "%LOADER_CMD%" >nul 2>&1

REM ===== Worker dispatch (re-entry point) ==========================
REM When this script is launched as: cmd /c "<this> --worker IDX TMPD"
REM run the worker for that repo and exit.
if /I "%~1"=="--worker" (
    call :worker %2 %3
    endlocal & exit /b !ERRORLEVEL!
)

REM ===== Parent flow ==========================================

echo ============================================================
echo [INFO] githerd  ^|  %DATE% %TIME%
echo ============================================================

REM --- Create temp dir for IPC files ---
set "TMPD=%TEMP%\githerd_%RANDOM%_%RANDOM%"
mkdir "%TMPD%" 2>nul
if not exist "%TMPD%" (
    echo [ERROR] Failed to create temp dir "%TMPD%"
    endlocal & exit /b 2
)
echo [INFO] Temp dir: %TMPD%
echo ------------------------------------------------------------

REM --- Capture ESC byte for ANSI cursor moves ---
for /f "delims=" %%a in ('powershell -NoProfile -Command "[char]27"') do set "ESC=%%a"

REM --- Initialize per-repo bar state ---
for /L %%i in (0,1,!repo_max_index!) do (
    set /a "cur_pct[%%i]=0"
    set "cur_phase[%%i]="
    set "cur_status[%%i]=waiting"
)

REM --- Launch workers (silently; bars will show progress) ---
for /L %%i in (0,1,!repo_max_index!) do (
    start "" /b cmd /c ""%~f0" --worker %%i "%TMPD%""
)

REM --- Reserve N lines for the live progress block ---
for /L %%i in (0,1,!repo_max_index!) do echo.

REM --- Poll loop ---
set /a elapsed=0

:poll
set /a all_done=1
for /L %%i in (0,1,!repo_max_index!) do (
    call :update_repo %%i
    if not exist "%TMPD%\!repos[%%i].name!.done" set /a all_done=0
)
call :render_block

if !all_done! EQU 1 goto poll_finished

if !elapsed! GEQ !MAX_WAIT! (
    for /L %%i in (0,1,!repo_max_index!) do (
        if not exist "%TMPD%\!repos[%%i].name!.done" (
            ^> "%TMPD%\!repos[%%i].name!.done" echo FAILED ^(timeout^)
        )
    )
    goto poll_finished
)

REM Sleep ~1s silently
ping 127.0.0.1 -n 2 >nul
set /a elapsed+=1
goto poll

:poll_finished
REM Final render so bars reflect terminal state, then a newline to freeze the block
for /L %%i in (0,1,!repo_max_index!) do (
    call :update_repo %%i
)
call :render_block
echo.
echo ------------------------------------------------------------

REM --- Read done files, count results, build summary ---
set /a ok_count=0
set /a fail_count=0
set /a skip_count=0
set "ANY_FAILED="

for /L %%i in (0,1,!repo_max_index!) do (
    call :read_done %%i
)

REM --- Per-repo summary ---
echo [INFO] Per-repo results:
for /L %%i in (0,1,!repo_max_index!) do (
    call echo    %%repos[%%i].name%%  ::  %%done_status[%%i]%%
)
echo ------------------------------------------------------------
echo [INFO] Totals: ok=!ok_count!  failed=!fail_count!  skipped=!skip_count!
echo ============================================================

REM --- Show log paths for failed repos ---
if defined ANY_FAILED (
    echo [INFO] Log files for FAILED repos:
    for /L %%i in (0,1,!repo_max_index!) do (
        call :show_failed_log %%i
    )
    echo ------------------------------------------------------------
)

REM --- Run final command (sequential, after all workers done) ---
if defined FINAL_COMMAND if not "!FINAL_COMMAND!"=="" (
    REM Resolve the directory to run the final command from: WORKING_DIR if set,
    REM otherwise the current shell directory (backward compatible).
    set "FINAL_ROOT=!WORKING_DIR!"
    if "!FINAL_ROOT!"=="" set "FINAL_ROOT=%CD%"
    set "_FINAL_PUSHED="
    if exist "!FINAL_ROOT!\." (
        pushd "!FINAL_ROOT!" >nul 2>&1
        if not errorlevel 1 set "_FINAL_PUSHED=1"
    ) else (
        echo [WARN] working_dir not found: !FINAL_ROOT! - running final command from current directory.
    )
    echo [INFO] Running final command in: !CD!
    echo        !FINAL_COMMAND!
    call !FINAL_COMMAND!
    set "FINAL_RC=!ERRORLEVEL!"
    if defined _FINAL_PUSHED popd
    if "!FINAL_RC!"=="0" (
        echo [INFO] Final command completed successfully
    ) else (
        echo [ERROR] Final command exited with code !FINAL_RC!
        set "ANY_FAILED=1"
    )
)

echo ============================================================
echo [INFO] All done
echo ============================================================

REM --- Cleanup tempdir on success; keep it on failure ---
if defined ANY_FAILED (
    echo [INFO] Temp dir kept for inspection: %TMPD%
    endlocal & exit /b 1
) else (
    rmdir /s /q "%TMPD%" 2>nul
    endlocal & exit /b 0
)

REM ============================================================
REM :update_repo IDX
REM   Read repos[IDX]'s .status / .done files; update
REM   cur_phase / cur_pct / cur_status accordingly.
REM ============================================================
:update_repo
set "_i=%~1"
set "_name=!repos[%_i%].name!"
set "_df=%TMPD%\!_name!.done"
set "_sf=%TMPD%\!_name!.status"

if exist "!_df!" (
    set "_phase="
    for /f "usebackq delims=" %%D in ("!_df!") do set "_phase=%%D"
    set "cur_status[%_i%]=!_phase!"
    set "cur_phase[%_i%]=!_phase!"
    for /f "tokens=1" %%T in ("!_phase!") do set "_first=%%T"
    if /I "!_first!"=="OK"      set /a "cur_pct[%_i%]=100"
    if /I "!_first!"=="SKIPPED" set /a "cur_pct[%_i%]=100"
    REM FAILED keeps existing pct (frozen)
    goto :eof
)

set "_phase="
if exist "!_sf!" (
    for /f "usebackq delims=" %%S in ("!_sf!") do set "_phase=%%S"
)
if "!_phase!"=="" (
    set "cur_status[%_i%]=waiting"
    goto :eof
)
set "cur_status[%_i%]=!_phase!"
call :update_pct %_i% "!_phase!"
goto :eof

REM ============================================================
REM :update_pct IDX PHASE
REM   Maps PHASE to a [min,max] range. On phase change, jump
REM   to min. Otherwise tick up by STEP toward max.
REM ============================================================
:update_pct
set "_i=%~1"
set "_phase=%~2"
set "_old=!cur_phase[%_i%]!"
call :phase_range "%_phase%"
if "%_old%" NEQ "%_phase%" (
    set "cur_phase[%_i%]=%_phase%"
    if !RANGE_MIN! GEQ 0 set /a "cur_pct[%_i%]=!RANGE_MIN!"
    goto :eof
)
if !RANGE_MIN! LSS 0 goto :eof
set /a "_np=cur_pct[%_i%]+2"
if !_np! GTR !RANGE_MAX! set /a "_np=!RANGE_MAX!"
set /a "cur_pct[%_i%]=!_np!"
goto :eof

REM ============================================================
REM :phase_range PHASE
REM   Sets RANGE_MIN / RANGE_MAX. RANGE_MIN=-1 means "freeze".
REM ============================================================
:phase_range
set "P=%~1"
set "RANGE_MIN=0"
set "RANGE_MAX=0"
if /I "%P%"=="starting"          ( set "RANGE_MIN=0"   & set "RANGE_MAX=5"   & goto :eof )
if /I "%P%"=="stashing"          ( set "RANGE_MIN=5"   & set "RANGE_MAX=15"  & goto :eof )
if /I "%P%"=="checkout master"   ( set "RANGE_MIN=15"  & set "RANGE_MAX=20"  & goto :eof )
if /I "%P%"=="fetching upstream" ( set "RANGE_MIN=20"  & set "RANGE_MAX=40"  & goto :eof )
if /I "%P%"=="fetching origin"   ( set "RANGE_MIN=40"  & set "RANGE_MAX=55"  & goto :eof )
if /I "%P%"=="merging"           ( set "RANGE_MIN=55"  & set "RANGE_MAX=70"  & goto :eof )
if /I "%P%"=="pulling"           ( set "RANGE_MIN=55"  & set "RANGE_MAX=85"  & goto :eof )
if /I "%P%"=="pushing"           ( set "RANGE_MIN=70"  & set "RANGE_MAX=90"  & goto :eof )
if /I "%P%"=="checkout original" ( set "RANGE_MIN=90"  & set "RANGE_MAX=95"  & goto :eof )
if /I "%P%"=="popping stash"     ( set "RANGE_MIN=95"  & set "RANGE_MAX=99"  & goto :eof )
for /f "tokens=1" %%T in ("%P%") do set "FIRST=%%T"
if /I "%FIRST%"=="OK"      ( set "RANGE_MIN=100" & set "RANGE_MAX=100" & goto :eof )
if /I "%FIRST%"=="SKIPPED" ( set "RANGE_MIN=100" & set "RANGE_MAX=100" & goto :eof )
if /I "%FIRST%"=="FAILED"  ( set "RANGE_MIN=-1"  & set "RANGE_MAX=-1"  & goto :eof )
goto :eof

REM ============================================================
REM :render_block
REM   Move cursor up (repo_count+1) lines and redraw all bars.
REM ============================================================
:render_block
set /a _up=repo_count+1
echo %ESC%[!_up!A
for /L %%i in (0,1,!repo_max_index!) do (
    call :render_line %%i
)
goto :eof

REM ============================================================
REM :render_line IDX
REM   Emit "<padded_name> [<bar>] <pct>% <status>" prefixed
REM   with ESC[2K to clear the existing line.
REM ============================================================
:render_line
set "_i=%~1"
set "_n=!repos[%_i%].name!                      "
set "_n=!_n:~0,22!"
set /a "_p=cur_pct[%_i%]"
set /a _fill=_p/5
set "_bar="
for /L %%j in (1,1,%_fill%) do set "_bar=!_bar!#"
set /a _empty=20-_fill
for /L %%j in (1,1,%_empty%) do set "_bar=!_bar!-"
set "_pp=  %_p%"
set "_pp=!_pp:~-3!"
echo %ESC%[2K!_n![!_bar!] !_pp!%% !cur_status[%_i%]!
goto :eof

REM ============================================================
REM :read_done IDX
REM ============================================================
:read_done
set "_i=%~1"
set "_name=!repos[%_i%].name!"
set "_df=%TMPD%\!_name!.done"
set "_status=MISSING"
if exist "!_df!" (
    for /f "usebackq delims=" %%D in ("!_df!") do set "_status=%%D"
)
set "done_status[%_i%]=!_status!"
for /f "tokens=1" %%T in ("!_status!") do set "_first=%%T"
if /I "!_first!"=="OK"      set /a ok_count+=1
if /I "!_first!"=="SKIPPED" set /a skip_count+=1
if /I "!_first!"=="FAILED"  ( set /a fail_count+=1 & set "ANY_FAILED=1" )
if /I "!_first!"=="MISSING" ( set /a fail_count+=1 & set "ANY_FAILED=1" )
goto :eof

REM ============================================================
REM :show_failed_log IDX
REM ============================================================
:show_failed_log
set "_i=%~1"
set "_name=!repos[%_i%].name!"
for /f "tokens=1" %%T in ("!done_status[%_i%]!") do set "_first=%%T"
if /I "!_first!"=="FAILED"  echo    !_name!  ::  %TMPD%\!_name!.log
if /I "!_first!"=="MISSING" echo    !_name!  ::  %TMPD%\!_name!.log
goto :eof

REM ============================================================
REM :worker IDX TMPD
REM ============================================================
:worker
set "IDX=%~1"
set "TMPD=%~2"

set "NAME=!repos[%IDX%].name!"
set "PATHDIR=!repos[%IDX%].path!"
set "MASTER_BRANCH=!repos[%IDX%].master!"
set "AUTO_MERGE=!repos[%IDX%].auto_merge!"

REM Resolve effective directory by combining WORKING_DIR with the configured path.
REM Absolute paths (X:..., \..., /...) are used as-is.
call :resolve_path "!PATHDIR!" EFFECTIVE_DIR

set "LOG=%TMPD%\%NAME%.log"
set "STATUS_FILE=%TMPD%\%NAME%.status"
set "DONE_FILE=%TMPD%\%NAME%.done"

> "%LOG%"  echo === Worker for %NAME% (%DATE% %TIME%) ===
>> "%LOG%" echo path=%PATHDIR%  resolved=!EFFECTIVE_DIR!  master=%MASTER_BRANCH%  auto_merge=%AUTO_MERGE%

call :set_phase starting

if not exist "!EFFECTIVE_DIR!" (
    call :write_done "SKIPPED (path not found)"
    exit /b 0
)

pushd "!EFFECTIVE_DIR!" >> "%LOG%" 2>&1
if errorlevel 1 (
    call :write_done "SKIPPED (pushd failed)"
    exit /b 0
)

if not exist ".git" (
    call :write_done "SKIPPED (not a git repo)"
    popd
    exit /b 0
)

REM --- Detect dirty tree ---
set "DIRTY="
for /f "delims=" %%L in ('git status --porcelain') do set "DIRTY=1"

REM --- Capture original branch ---
set "ORIGINAL_BRANCH="
for /f "delims=" %%b in ('git branch --show-current 2^>nul') do set "ORIGINAL_BRANCH=%%b"

set "STASHED="
set "REPO_FAILED="
set "FAIL_REASON="

if defined DIRTY (
    call :set_phase "stashing"
    git stash push -u -m "githerd auto-stash" >> "%LOG%" 2>&1
    if errorlevel 1 (
        call :write_done "FAILED (git stash push)"
        popd
        exit /b 0
    )
    set "STASHED=1"
)

if /I "!ORIGINAL_BRANCH!" NEQ "%MASTER_BRANCH%" (
    call :set_phase "checkout master"
    git checkout %MASTER_BRANCH% >> "%LOG%" 2>&1
    if errorlevel 1 (
        set "REPO_FAILED=1"
        set "FAIL_REASON=git checkout %MASTER_BRANCH%"
    )
)

if not defined REPO_FAILED (
    if /I "%AUTO_MERGE%"=="true" (
        call :set_phase "fetching upstream"
        git fetch upstream %MASTER_BRANCH% >> "%LOG%" 2>&1
        if errorlevel 1 (
            set "REPO_FAILED=1"
            set "FAIL_REASON=git fetch upstream"
        )
    )
)

if not defined REPO_FAILED (
    if /I "%AUTO_MERGE%"=="true" (
        call :set_phase "fetching origin"
        git fetch origin %MASTER_BRANCH% >> "%LOG%" 2>&1
        if errorlevel 1 (
            set "REPO_FAILED=1"
            set "FAIL_REASON=git fetch origin"
        )
    )
)

if not defined REPO_FAILED (
    if /I "%AUTO_MERGE%"=="true" (
        call :set_phase "merging"
        git merge --ff-only upstream/%MASTER_BRANCH% >> "%LOG%" 2>&1
        if errorlevel 1 (
            set "REPO_FAILED=1"
            set "FAIL_REASON=git merge --ff-only"
        ) else (
            call :set_phase "pushing"
            git push origin %MASTER_BRANCH% --no-verify >> "%LOG%" 2>&1
            if errorlevel 1 (
                set "REPO_FAILED=1"
                set "FAIL_REASON=git push origin"
            )
        )
    ) else (
        call :set_phase "pulling"
        git pull origin %MASTER_BRANCH% >> "%LOG%" 2>&1
        if errorlevel 1 (
            set "REPO_FAILED=1"
            set "FAIL_REASON=git pull origin %MASTER_BRANCH%"
        )
    )
)

REM --- Switch back to original branch ---
set "BRANCH_RESTORED=1"
if /I "!ORIGINAL_BRANCH!" NEQ "%MASTER_BRANCH%" (
    if defined ORIGINAL_BRANCH (
        call :set_phase "checkout original"
        git checkout !ORIGINAL_BRANCH! >> "%LOG%" 2>&1
        if errorlevel 1 (
            set "REPO_FAILED=1"
            set "FAIL_REASON=git checkout !ORIGINAL_BRANCH!"
            set "BRANCH_RESTORED="
        )
    )
)

REM --- Pop stash (only if branch was restored) ---
if defined STASHED (
    if defined BRANCH_RESTORED (
        call :set_phase "popping stash"
        git stash pop >> "%LOG%" 2>&1
        if errorlevel 1 (
            set "REPO_FAILED=1"
            set "FAIL_REASON=git stash pop"
        )
    ) else (
        echo [WARN] Skipping git stash pop - not on original branch>> "%LOG%"
        set "REPO_FAILED=1"
        if not defined FAIL_REASON set "FAIL_REASON=stash kept (branch not restored)"
    )
)

popd

if defined REPO_FAILED (
    call :write_done "FAILED (!FAIL_REASON!)"
) else (
    set "RESULT=OK"
    if defined STASHED set "RESULT=!RESULT! (stashed)"
    if /I "!ORIGINAL_BRANCH!" NEQ "%MASTER_BRANCH%" (
        if defined ORIGINAL_BRANCH set "RESULT=!RESULT! - !ORIGINAL_BRANCH!"
    )
    call :write_done "!RESULT!"
)
exit /b 0

REM ============================================================
REM :set_phase  PHASE_STRING
REM ============================================================
:set_phase
> "%STATUS_FILE%.tmp" echo %~1
move /y "%STATUS_FILE%.tmp" "%STATUS_FILE%" >nul 2>&1
goto :eof

REM ============================================================
REM :write_done  RESULT_STRING
REM ============================================================
:write_done
> "%STATUS_FILE%.tmp" echo %~1
move /y "%STATUS_FILE%.tmp" "%STATUS_FILE%" >nul 2>&1
> "%DONE_FILE%" echo %~1
>> "%LOG%" echo === Result: %~1 ===
goto :eof

REM ============================================================
REM :resolve_path  RAW_PATH  OUT_VAR_NAME
REM   Joins WORKING_DIR with RAW_PATH unless RAW_PATH is already
REM   absolute (starts with drive letter, backslash, or forward
REM   slash). Falls back to %CD% when WORKING_DIR is empty.
REM ============================================================
:resolve_path
set "_in=%~1"
set "_outv=%~2"
set "_root=!WORKING_DIR!"
if "!_root!"=="" set "_root=%CD%"

set "_abs=0"
if not "!_in!"=="" if "!_in:~1,1!"==":" set "_abs=1"
if not "!_in!"=="" if "!_in:~0,1!"=="\" set "_abs=1"
if not "!_in!"=="" if "!_in:~0,1!"=="/" set "_abs=1"

if "!_abs!"=="1" (
    set "!_outv!=!_in!"
) else if "!_in!"=="" (
    set "!_outv!=!_root!"
) else (
    set "!_outv!=!_root!\!_in!"
)
goto :eof
