#Requires -Version 5.0
<#
.SYNOPSIS
    Reads config.json and emits a .cmd file of `set` statements that sync.bat
    can `call` to populate its environment variables.

.PARAMETER ConfigPath
    Path to the JSON config file.

.PARAMETER OutPath
    Path of the .cmd file to generate.

.NOTES
    Variables emitted:
      repos[N].name
      repos[N].path
      repos[N].master
      repos[N].auto_merge   (true|false)
      repo_count
      repo_max_index
      FINAL_COMMAND
      MAX_WAIT
#>

param(
    [Parameter(Mandatory = $true)] [string]$ConfigPath,
    [Parameter(Mandatory = $true)] [string]$OutPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath"
    exit 1
}

try {
    $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse JSON: $($_.Exception.Message)"
    exit 1
}

$repos = @($cfg.repos)
if ($repos.Count -eq 0) {
    Write-Error 'config.json contains no repos.'
    exit 1
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('@echo off')

for ($i = 0; $i -lt $repos.Count; $i++) {
    $r = $repos[$i]
    $name   = [string]$r.name
    $path   = [string]$r.path
    $master = [string]$r.master
    $auto   = if ($r.auto_merge) { 'true' } else { 'false' }

    foreach ($v in @($name, $path, $master)) {
        if ($v -match '"') {
            Write-Error "repos[$i] field contains a double-quote, which is not supported."
            exit 1
        }
    }

    $lines.Add("set `"repos[$i].name=$name`"")
    $lines.Add("set `"repos[$i].path=$path`"")
    $lines.Add("set `"repos[$i].master=$master`"")
    $lines.Add("set `"repos[$i].auto_merge=$auto`"")
}

$count = $repos.Count
$lines.Add("set /a repo_count=$count")
$lines.Add("set /a repo_max_index=$($count - 1)")

$finalCmd = [string]$cfg.final_command
# Escape ^, &, |, <, > for safety inside a `set "VAR=..."` payload? Inside quoted set,
# only the closing quote is hazardous. We already rejected quotes above for repo fields;
# for FINAL_COMMAND we keep quotes by escaping them as "" is not a thing in cmd, so use
# delayed-expansion-friendly storage instead: write %FINAL_COMMAND% via a file load.
# Simpler: forbid double-quotes here too and tell the user to wrap paths with spaces using
# caret-escaping or no quotes.
if ($finalCmd -match '"') {
    Write-Error 'final_command must not contain double-quote characters.'
    exit 1
}
$lines.Add("set `"FINAL_COMMAND=$finalCmd`"")

$maxWait = 600
if ($cfg.PSObject.Properties.Match('max_wait_seconds').Count -gt 0 -and $cfg.max_wait_seconds) {
    $maxWait = [int]$cfg.max_wait_seconds
}
$lines.Add("set /a MAX_WAIT=$maxWait")

Set-Content -LiteralPath $OutPath -Value ($lines -join "`r`n") -Encoding ASCII
exit 0
