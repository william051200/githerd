<#
.SYNOPSIS
    Runs the GitHerd Pester test suite. Installs Pester 5.5+ for the current
    user if a compatible version is not already loadable.

.PARAMETER Tag
    Optional Pester tag filter. Pass 'Integration' to run only the slow
    integration suite, or omit to run everything except integration tests.

.PARAMETER IncludeIntegration
    Include integration tests in the default run. Equivalent to omitting the
    -ExcludeTag filter.

.EXAMPLE
    pwsh -File tests/Invoke-Tests.ps1
    powershell -File tests\Invoke-Tests.ps1 -IncludeIntegration
#>
[CmdletBinding()]
param(
    [string[]]$Tag,
    [switch]$IncludeIntegration
)

$ErrorActionPreference = 'Stop'

$MinPester = [version]'5.5.0'

function Ensure-Pester {
    $loaded = Get-Module -Name Pester | Where-Object { $_.Version -ge $MinPester } | Select-Object -First 1
    if ($loaded) { return $loaded }

    $available = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -ge $MinPester } |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $available) {
        Write-Host "Installing Pester >= $MinPester for current user..."
        Install-Module -Name Pester -MinimumVersion $MinPester -Scope CurrentUser -Force -SkipPublisherCheck
        $available = Get-Module -ListAvailable -Name Pester |
            Where-Object { $_.Version -ge $MinPester } |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }
    Import-Module $available.Path -Force
    return (Get-Module -Name Pester)
}

$pester = Ensure-Pester
Write-Host ("Using Pester {0} from {1}" -f $pester.Version, $pester.Path)

$testsRoot = $PSScriptRoot

$config = New-PesterConfiguration
$config.Run.Path = $testsRoot
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

if ($Tag) {
    $config.Filter.Tag = $Tag
} elseif (-not $IncludeIntegration) {
    $config.Filter.ExcludeTag = 'Integration'
}

Invoke-Pester -Configuration $config
