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
      repos[N].master_remote
      repo_count
      repo_max_index
      WORKING_DIR
      FINAL_COMMAND
      MAX_WAIT
#>

param(
    [Parameter(Mandatory = $true)] [string]$ConfigPath,
    [Parameter(Mandatory = $true)] [string]$OutPath
)

$ErrorActionPreference = 'Stop'

try {
    . (Join-Path $PSScriptRoot 'config.ps1')
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: $ConfigPath"
    }
    $cfg = Read-GitHerdConfig -Path $ConfigPath -ForRuntime
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$repos = @($cfg.repos)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('@echo off')

for ($i = 0; $i -lt $repos.Count; $i++) {
    $r = $repos[$i]
    $name   = [string]$r.name
    $path   = [string]$r.path
    $master = [string]$r.master
    $auto   = if ($r.auto_merge) { 'true' } else { 'false' }
    $masterRemote = [string]$r.master_remote

    $lines.Add("set `"repos[$i].name=$name`"")
    $lines.Add("set `"repos[$i].path=$path`"")
    $lines.Add("set `"repos[$i].master=$master`"")
    $lines.Add("set `"repos[$i].auto_merge=$auto`"")
    $lines.Add("set `"repos[$i].master_remote=$masterRemote`"")
}

$count = $repos.Count
$lines.Add("set /a repo_count=$count")
$lines.Add("set /a repo_max_index=$($count - 1)")

$workingDir = [string]$cfg.working_dir
$lines.Add("set `"WORKING_DIR=$workingDir`"")

$finalCmd = [string]$cfg.final_command
$lines.Add("set `"FINAL_COMMAND=$finalCmd`"")

$maxWait = [int]$cfg.max_wait_seconds
$lines.Add("set /a MAX_WAIT=$maxWait")

Set-Content -LiteralPath $OutPath -Value ($lines -join "`r`n") -Encoding ASCII
exit 0
