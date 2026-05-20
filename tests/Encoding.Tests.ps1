#Requires -Version 5.1
<#
    Locks in the lesson from a past production bug: Windows PowerShell 5.1
    reads .ps1 files as CP-1252 by default. Any source file containing
    non-ASCII bytes (emoji, em-dash, smart quotes, accented letters) must
    start with a UTF-8 BOM (EF BB BF), otherwise PS 5.1 will mojibake the
    file and fail to parse it.

    Only tracked .ps1 files are inspected so untracked scratch files do not
    fail the suite.
#>

# Discovery-time: build the file list now so -ForEach gets populated data.
# Pester 5 BeforeAll runs at *run* time, which is too late for data-driven
# It -ForEach.
$script:RepoRootDiscovery = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $script:RepoRootDiscovery
try {
    $script:TrackedPs1 = @(git ls-files '*.ps1' 2>$null |
        Where-Object { $_ } |
        ForEach-Object { (Join-Path $script:RepoRootDiscovery $_).Replace('/', '\') })
} finally {
    Pop-Location
}

if ($script:TrackedPs1.Count -eq 0) {
    throw "Encoding.Tests.ps1: git ls-files '*.ps1' returned no files. Run from inside a git checkout."
}

Describe 'Encoding: non-ASCII .ps1 files must start with a UTF-8 BOM' {

    It '<_> is ASCII-only or starts with UTF-8 BOM' -ForEach $script:TrackedPs1 {
        $path  = $_
        $bytes = [System.IO.File]::ReadAllBytes($path)

        $hasNonAscii = $false
        foreach ($b in $bytes) {
            if ($b -gt 127) { $hasNonAscii = $true; break }
        }

        if (-not $hasNonAscii) { return }

        $bytes.Length | Should -BeGreaterOrEqual 3 -Because "$path has non-ASCII bytes but is shorter than a BOM"
        $bom = '{0:X2}{1:X2}{2:X2}' -f $bytes[0], $bytes[1], $bytes[2]
        $bom | Should -Be 'EFBBBF' -Because "$path contains non-ASCII bytes but is missing the UTF-8 BOM (PS 5.1 will mojibake it)"
    }
}
