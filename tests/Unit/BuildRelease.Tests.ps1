#Requires -Version 5.1
<#
    Tests for scripts/build-release.ps1.

    Strategy:
        * Build a synthetic repo tree under TestDrive: containing every entry
          the packager whitelists, plus a few that must be excluded.
        * Invoke build-release.ps1 against that tree (we point $PSScriptRoot
          at the synthetic repo by copying the packager into the temp tree's
          scripts/ folder, since the script resolves the repo as
          $PSScriptRoot/..).
        * Inspect the produced zip with System.IO.Compression and assert:
            - it contains exactly the whitelist
            - it excludes .git/.github/config.json/DESIGN.md/dist/scripts
            - the inner VERSION file equals the -Version argument
        * Also assert the [ValidatePattern] rejects non-semver inputs.
#>

BeforeAll {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $script:RealRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:RealPackager = Join-Path $script:RealRepoRoot 'scripts\build-release.ps1'

    function New-SyntheticRepo {
        param([Parameter(Mandatory)] [string]$Root)

        New-Item -ItemType Directory -Path $Root -Force | Out-Null

        # Files/dirs that should end up in the zip
        Set-Content (Join-Path $Root 'sync.bat')           'REM fake sync' -Encoding ASCII
        Set-Content (Join-Path $Root 'githerd.cmd')        'REM fake cmd'  -Encoding ASCII
        Set-Content (Join-Path $Root 'README.md')          '# fake'        -Encoding ASCII
        Set-Content (Join-Path $Root 'LICENSE')            'MIT-ish'       -Encoding ASCII
        Set-Content (Join-Path $Root 'VERSION')            '9.9.9'         -Encoding ASCII -NoNewline
        Set-Content (Join-Path $Root 'config.example.json') '{}'           -Encoding ASCII

        New-Item -ItemType Directory -Path (Join-Path $Root 'lib')  -Force | Out-Null
        Set-Content (Join-Path $Root 'lib\dummy.ps1')  '# dummy' -Encoding ASCII

        New-Item -ItemType Directory -Path (Join-Path $Root 'ui')   -Force | Out-Null
        Set-Content (Join-Path $Root 'ui\dummy.ps1')   '# dummy' -Encoding ASCII

        New-Item -ItemType Directory -Path (Join-Path $Root 'docs') -Force | Out-Null
        Set-Content (Join-Path $Root 'docs\dummy.md')  '# dummy' -Encoding ASCII

        # Things that MUST be excluded
        New-Item -ItemType Directory -Path (Join-Path $Root '.git')          -Force | Out-Null
        Set-Content (Join-Path $Root '.git\config') 'should not ship' -Encoding ASCII

        New-Item -ItemType Directory -Path (Join-Path $Root '.github')       -Force | Out-Null
        Set-Content (Join-Path $Root '.github\stuff') 'no'             -Encoding ASCII

        Set-Content (Join-Path $Root 'config.json') '{"secret":true}'  -Encoding ASCII
        Set-Content (Join-Path $Root 'DESIGN.md')   '# design'         -Encoding ASCII

        New-Item -ItemType Directory -Path (Join-Path $Root 'dist')          -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Root 'scripts')       -Force | Out-Null

        # The packager itself needs to live inside the synthetic repo, since
        # $PSScriptRoot is what it uses to find the repo root.
        Copy-Item -LiteralPath $script:RealPackager -Destination (Join-Path $Root 'scripts\build-release.ps1') -Force
    }

    function Invoke-Packager {
        param(
            [Parameter(Mandatory)] [string]$Root,
            [Parameter(Mandatory)] [string]$Version,
            [string]$OutDir
        )
        $psExe  = (Get-Process -Id $PID).Path
        $script = Join-Path $Root 'scripts\build-release.ps1'
        $stdout = [System.IO.Path]::GetTempFileName()
        $stderr = [System.IO.Path]::GetTempFileName()
        try {
            $argList = @('-NoProfile','-File',$script,'-Version',$Version)
            if ($OutDir) { $argList += @('-OutDir', $OutDir) }
            $p = Start-Process -FilePath $psExe -ArgumentList $argList `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            return [pscustomobject]@{
                ExitCode = $p.ExitCode
                StdOut   = (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
                StdErr   = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
            }
        } finally {
            Remove-Item -LiteralPath $stdout,$stderr -ErrorAction SilentlyContinue
        }
    }

    function Get-ZipEntries {
        param([Parameter(Mandatory)] [string]$ZipPath)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            return @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
        } finally {
            $zip.Dispose()
        }
    }

    function Get-ZipEntryText {
        param(
            [Parameter(Mandatory)] [string]$ZipPath,
            [Parameter(Mandatory)] [string]$EntryName
        )
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $entry = $zip.Entries |
                Where-Object { $_.FullName.Replace('\','/') -eq $EntryName } |
                Select-Object -First 1
            if (-not $entry) { return $null }
            $stream = $entry.Open()
            try {
                $reader = New-Object System.IO.StreamReader($stream)
                return $reader.ReadToEnd()
            } finally {
                $stream.Dispose()
            }
        } finally {
            $zip.Dispose()
        }
    }
}

Describe 'scripts/build-release.ps1' {

    BeforeEach {
        $script:Repo   = Join-Path $TestDrive ("repo-" + [guid]::NewGuid().ToString('N'))
        $script:OutDir = Join-Path $TestDrive ("out-"  + [guid]::NewGuid().ToString('N'))
        New-SyntheticRepo -Root $script:Repo
        New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null
    }

    Context 'happy path' {
        It 'produces a zip named githerd-v<version>.zip in -OutDir' {
            $r = Invoke-Packager -Root $script:Repo -Version '1.2.3' -OutDir $script:OutDir
            $r.ExitCode | Should -Be 0
            $zip = Join-Path $script:OutDir 'githerd-v1.2.3.zip'
            Test-Path -LiteralPath $zip | Should -BeTrue
        }

        It 'includes every whitelisted entry' {
            (Invoke-Packager -Root $script:Repo -Version '1.2.3' -OutDir $script:OutDir).ExitCode | Should -Be 0
            $entries = Get-ZipEntries (Join-Path $script:OutDir 'githerd-v1.2.3.zip')

            $expected = @(
                'githerd-v1.2.3/sync.bat'
                'githerd-v1.2.3/githerd.cmd'
                'githerd-v1.2.3/README.md'
                'githerd-v1.2.3/LICENSE'
                'githerd-v1.2.3/VERSION'
                'githerd-v1.2.3/config.example.json'
                'githerd-v1.2.3/lib/dummy.ps1'
                'githerd-v1.2.3/ui/dummy.ps1'
                'githerd-v1.2.3/docs/dummy.md'
            )
            foreach ($e in $expected) {
                $entries | Should -Contain $e -Because "expected $e in the package"
            }
        }

        It 'excludes .git, .github, config.json, DESIGN.md, dist, and scripts' {
            (Invoke-Packager -Root $script:Repo -Version '1.2.3' -OutDir $script:OutDir).ExitCode | Should -Be 0
            $entries = Get-ZipEntries (Join-Path $script:OutDir 'githerd-v1.2.3.zip')

            ($entries | Where-Object { $_ -like '*.git/*'      }) | Should -BeNullOrEmpty
            ($entries | Where-Object { $_ -like '*/.github/*'  -or $_ -like '*.github/*' }) | Should -BeNullOrEmpty
            ($entries | Where-Object { $_ -like '*/config.json' -or $_ -like '*config.json' -and $_ -notlike '*example*' }) | Should -BeNullOrEmpty
            ($entries | Where-Object { $_ -like '*DESIGN.md'   }) | Should -BeNullOrEmpty
            ($entries | Where-Object { $_ -like '*/dist/*'     }) | Should -BeNullOrEmpty
            ($entries | Where-Object { $_ -like '*/scripts/*'  }) | Should -BeNullOrEmpty
        }

        It 'stamps the inner VERSION file with the -Version argument' {
            (Invoke-Packager -Root $script:Repo -Version '7.8.9' -OutDir $script:OutDir).ExitCode | Should -Be 0
            $zip = Join-Path $script:OutDir 'githerd-v7.8.9.zip'
            $v   = Get-ZipEntryText -ZipPath $zip -EntryName 'githerd-v7.8.9/VERSION'
            $v   | Should -Be '7.8.9' -Because 'the packager overrides VERSION with -Version (no trailing newline)'
        }

        It 'overwrites an existing zip at the same path' {
            $zip = Join-Path $script:OutDir 'githerd-v1.2.3.zip'
            Set-Content -LiteralPath $zip -Value 'placeholder' -Encoding ASCII
            (Invoke-Packager -Root $script:Repo -Version '1.2.3' -OutDir $script:OutDir).ExitCode | Should -Be 0
            (Get-Item -LiteralPath $zip).Length | Should -BeGreaterThan 'placeholder'.Length
        }
    }

    Context 'validation' {
        It 'rejects a non-semver -Version value' {
            $r = Invoke-Packager -Root $script:Repo -Version 'not-a-version' -OutDir $script:OutDir
            $r.ExitCode | Should -Not -Be 0
            ($r.StdErr + $r.StdOut) | Should -Match '(?i)Cannot validate argument|ValidatePattern|does not match'
        }

        It 'accepts a pre-release suffix like 1.2.3-rc1' {
            $r = Invoke-Packager -Root $script:Repo -Version '1.2.3-rc1' -OutDir $script:OutDir
            $r.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $script:OutDir 'githerd-v1.2.3-rc1.zip') | Should -BeTrue
        }
    }

    Context 'edge cases' {
        It 'warns and skips when a whitelisted entry is missing from the source tree' {
            Remove-Item -Recurse -Force (Join-Path $script:Repo 'docs')
            $r = Invoke-Packager -Root $script:Repo -Version '1.2.3' -OutDir $script:OutDir
            $r.ExitCode | Should -Be 0
            ($r.StdErr + $r.StdOut) | Should -Match 'Skipping missing entry: docs'

            $entries = Get-ZipEntries (Join-Path $script:OutDir 'githerd-v1.2.3.zip')
            ($entries | Where-Object { $_ -like 'githerd-v1.2.3/docs*' }) | Should -BeNullOrEmpty
            $entries | Should -Contain 'githerd-v1.2.3/sync.bat'
        }

        It 'defaults -OutDir to (repo)/dist when omitted' {
            $r = Invoke-Packager -Root $script:Repo -Version '1.2.3'   # no -OutDir
            $r.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $script:Repo 'dist\githerd-v1.2.3.zip') | Should -BeTrue
        }

        It 'creates -OutDir when it does not exist yet' {
            $newOut = Join-Path $TestDrive ("brand-new-" + [guid]::NewGuid().ToString('N'))
            Test-Path -LiteralPath $newOut | Should -BeFalse
            $r = Invoke-Packager -Root $script:Repo -Version '1.2.3' -OutDir $newOut
            $r.ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $newOut 'githerd-v1.2.3.zip') | Should -BeTrue
        }

        It 'cleans up its staging directory under $env:TEMP' {
            $tempBefore = @(Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter 'githerd-build-*' -Directory -ErrorAction SilentlyContinue).Count
            $r = Invoke-Packager -Root $script:Repo -Version '1.2.3' -OutDir $script:OutDir
            $r.ExitCode | Should -Be 0
            $tempAfter = @(Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter 'githerd-build-*' -Directory -ErrorAction SilentlyContinue).Count
            $tempAfter | Should -Be $tempBefore -Because 'staging directory must be removed in the finally block'
        }
    }
}
