#Requires -Version 5.1
<#
.SYNOPSIS
    Integration tests for sync.bat. A "fake git" is placed at the front of
    PATH so we can verify the call sequences, exit codes, and timeout
    behaviour without touching real repositories or the network.

    These tests are tagged 'Integration' and excluded from the default
    Invoke-Tests.ps1 run; pass -IncludeIntegration or -Tag Integration to
    include them.
#>

BeforeDiscovery {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:FakeGitDir = (Resolve-Path (Join-Path $PSScriptRoot 'FakeGit')).Path
}

Describe 'sync.bat integration' -Tag 'Integration' {

    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:FakeGitDir = (Resolve-Path (Join-Path $PSScriptRoot 'FakeGit')).Path

        # Build the fake git.exe from FakeGit.cs if it's missing or stale.
        # We need a .exe (not .cmd) because sync.bat workers invoke `git ...`
        # without `call`, which would terminate the worker if git were a .cmd.
        $exe = Join-Path $script:FakeGitDir 'git.exe'
        $src = Join-Path $script:FakeGitDir 'FakeGit.cs'
        $needBuild = $true
        if ((Test-Path $exe) -and (Test-Path $src)) {
            $needBuild = (Get-Item $src).LastWriteTimeUtc -gt (Get-Item $exe).LastWriteTimeUtc
        }
        if ($needBuild) {
            if (Test-Path $exe) { Remove-Item $exe -Force }

            # Add-Type -OutputType ConsoleApplication only works on Windows
            # PowerShell 5.1 (.NET Framework). On PowerShell 7+ it throws
            # "PSNotSupportedException: Both the assembly types
            # 'ConsoleApplication' and 'WindowsApplication' are not currently
            # supported." Fall back to calling csc.exe from the .NET
            # Framework directly - it ships with Windows so it is always
            # present on windows-latest runners.
            $built = $false
            if ($PSVersionTable.PSEdition -eq 'Desktop') {
                try {
                    $code = Get-Content -LiteralPath $src -Raw
                    Add-Type -TypeDefinition $code -OutputAssembly $exe -OutputType ConsoleApplication
                    $built = Test-Path $exe
                } catch {
                    $built = $false
                }
            }

            if (-not $built) {
                $cscCandidates = @(
                    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
                    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
                )
                $csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
                if (-not $csc) {
                    throw "Could not locate csc.exe to build fake git.exe. Tried: $($cscCandidates -join ', ')"
                }
                & $csc /nologo /target:exe /out:$exe $src | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "csc.exe failed (exit $LASTEXITCODE) while building fake git.exe."
                }
            }

            if (-not (Test-Path $exe)) {
                throw "Failed to build fake git.exe at $exe"
            }
        }

        function script:New-FakeRepo {
            param(
                [Parameter(Mandatory)] [string]$Name,
                [string]$Root,
                [switch]$NotARepo,
                [switch]$Missing
            )
            if (-not $Root) { $Root = $script:Workspace }
            $dir = Join-Path $Root $Name
            if ($Missing) { return $dir }
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            if (-not $NotARepo) {
                New-Item -ItemType Directory -Path (Join-Path $dir '.git') -Force | Out-Null
            }
            return $dir
        }

        function script:Write-Config {
            param(
                [Parameter(Mandatory)] [object[]]$Repos,
                [string]$WorkingDir,
                [string]$FinalCommand = '',
                [int]$MaxWaitSeconds = 60
            )
            if (-not $PSBoundParameters.ContainsKey('WorkingDir')) {
                $WorkingDir = $script:Workspace
            }
            $cfg = [ordered]@{
                working_dir      = $WorkingDir
                repos            = $Repos
                final_command    = $FinalCommand
                max_wait_seconds = $MaxWaitSeconds
            }
            $json = $cfg | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $script:Install 'config.json') -Value $json -Encoding ASCII
        }

        function script:Invoke-Sync {
            param([hashtable]$EnvVars = @{})

            $defaults = @{
                FAKEGIT_LOG             = $script:GitLog
                GITHERD_NO_UPDATE_CHECK = '1'
            }
            foreach ($k in $EnvVars.Keys) { $defaults[$k] = $EnvVars[$k] }

            $lines = @('@echo off')
            $lines += "set `"PATH=$($script:FakeGitDir);%PATH%`""
            foreach ($k in $defaults.Keys) {
                $v = $defaults[$k]
                $lines += "set `"$k=$v`""
            }
            $lines += "cd /d `"$($script:Workspace)`""
            $lines += "call `"$($script:Install)\sync.bat`""
            $lines += "exit /b %ERRORLEVEL%"

            $runner = Join-Path $script:TestRoot 'run.cmd'
            Set-Content -Path $runner -Value ($lines -join "`r`n") -Encoding ASCII

            $output = & cmd.exe /c $runner 2>&1
            $exit = $LASTEXITCODE

            $calls = @()
            if (Test-Path $script:GitLog) {
                $calls = Get-Content $script:GitLog
            }

            [pscustomobject]@{
                ExitCode = $exit
                Stdout   = ($output -join "`n")
                GitCalls = $calls
            }
        }
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $install = Join-Path $root 'install'
        New-Item -ItemType Directory -Path $install -Force | Out-Null
        Copy-Item (Join-Path $RepoRoot 'sync.bat') $install
        Copy-Item (Join-Path $RepoRoot 'lib') $install -Recurse
        if (Test-Path (Join-Path $RepoRoot 'VERSION')) {
            Copy-Item (Join-Path $RepoRoot 'VERSION') $install
        }

        $workspace = Join-Path $root 'workspace'
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null

        $script:TestRoot = $root
        $script:Install = $install
        $script:Workspace = $workspace
        $script:GitLog = Join-Path $root 'git-log.txt'
    }

    It 'happy path: single on-master repo with auto_merge=true exits 0 and runs expected git calls' {
        New-FakeRepo -Name 'repoA' | Out-Null
        Write-Config -Repos @(
            @{ name = 'repoA'; path = 'repoA'; master = 'main'; auto_merge = $true }
        )

        $r = Invoke-Sync

        $r.ExitCode | Should -Be 0
        $r.Stdout | Should -Match 'repoA\s+::\s+OK'
        $r.Stdout | Should -Match 'Totals: ok=1\s+failed=0\s+skipped=0'

        $firsts = $r.GitCalls | ForEach-Object { ($_ -split '\|', 2)[1].Split(' ')[0] }
        $firsts | Should -Contain 'status'
        $firsts | Should -Contain 'branch'
        $firsts | Should -Contain 'fetch'
        $firsts | Should -Contain 'merge'
        $firsts | Should -Contain 'push'
        # No pull when auto_merge=true
        $firsts | Should -Not -Contain 'pull'
        # No stash on a clean tree
        $firsts | Should -Not -Contain 'stash'
    }

    It 'pull mode: auto_merge=false runs git pull and skips fetch/merge/push' {
        New-FakeRepo -Name 'repoB' | Out-Null
        Write-Config -Repos @(
            @{ name = 'repoB'; path = 'repoB'; master = 'main'; auto_merge = $false }
        )

        $r = Invoke-Sync

        $r.ExitCode | Should -Be 0
        $r.Stdout | Should -Match 'repoB\s+::\s+OK'

        $firsts = $r.GitCalls | ForEach-Object { ($_ -split '\|', 2)[1].Split(' ')[0] }
        $firsts | Should -Contain 'pull'
        $firsts | Should -Not -Contain 'fetch'
        $firsts | Should -Not -Contain 'merge'
        $firsts | Should -Not -Contain 'push'
    }

    It 'multiple repos all succeed' {
        New-FakeRepo -Name 'r1' | Out-Null
        New-FakeRepo -Name 'r2' | Out-Null
        Write-Config -Repos @(
            @{ name = 'r1'; path = 'r1'; master = 'main'; auto_merge = $true }
            @{ name = 'r2'; path = 'r2'; master = 'main'; auto_merge = $false }
        )

        $r = Invoke-Sync

        $r.ExitCode | Should -Be 0
        $r.Stdout | Should -Match 'r1\s+::\s+OK'
        $r.Stdout | Should -Match 'r2\s+::\s+OK'
        $r.Stdout | Should -Match 'Totals: ok=2\s+failed=0\s+skipped=0'
    }

    It 'one failing repo: push failure surfaces FAILED, exit 1, log path printed' {
        New-FakeRepo -Name 'good' | Out-Null
        New-FakeRepo -Name 'bad'  | Out-Null
        Write-Config -Repos @(
            @{ name = 'good'; path = 'good'; master = 'main'; auto_merge = $true }
            @{ name = 'bad';  path = 'bad';  master = 'main'; auto_merge = $true }
        )

        # NOTE: fail flag is global, so BOTH repos' push will fail.
        $r = Invoke-Sync -EnvVars @{ FAKEGIT_FAIL_FIRST = 'push' }

        $r.ExitCode | Should -Be 1
        $r.Stdout | Should -Match 'FAILED \(git push origin\)'
        $r.Stdout | Should -Match 'Log files for FAILED repos:'
        $r.Stdout | Should -Match 'bad\.log'
    }

    It 'SKIPPED (path not found) when repo dir does not exist' {
        Write-Config -Repos @(
            @{ name = 'ghost'; path = 'does-not-exist'; master = 'main'; auto_merge = $true }
        )

        $r = Invoke-Sync

        $r.ExitCode | Should -Be 0
        $r.Stdout | Should -Match 'ghost\s+::\s+SKIPPED \(path not found\)'
        $r.Stdout | Should -Match 'Totals: ok=0\s+failed=0\s+skipped=1'
    }

    It 'SKIPPED (not a git repo) when directory exists without .git' {
        New-FakeRepo -Name 'plain' -NotARepo | Out-Null
        Write-Config -Repos @(
            @{ name = 'plain'; path = 'plain'; master = 'main'; auto_merge = $true }
        )

        $r = Invoke-Sync

        $r.ExitCode | Should -Be 0
        $r.Stdout | Should -Match 'plain\s+::\s+SKIPPED \(not a git repo\)'
    }

    It 'dirty tree triggers stash push and pop' {
        New-FakeRepo -Name 'dirty' | Out-Null
        Write-Config -Repos @(
            @{ name = 'dirty'; path = 'dirty'; master = 'main'; auto_merge = $false }
        )

        $r = Invoke-Sync -EnvVars @{ FAKEGIT_DIRTY = '1' }

        $r.ExitCode | Should -Be 0
        $r.Stdout | Should -Match 'dirty\s+::\s+OK \(stashed\)'

        $stashCalls = $r.GitCalls | Where-Object { (($_ -split '\|', 2)[1]) -like 'stash *' }
        $stashCalls.Count | Should -BeGreaterOrEqual 2  # push + pop
        ($stashCalls | Where-Object { $_ -match 'stash push' }).Count | Should -BeGreaterOrEqual 1
        ($stashCalls | Where-Object { $_ -match 'stash pop'  }).Count | Should -BeGreaterOrEqual 1
    }

    It 'final_command runs once after all repos when all succeed' {
        New-FakeRepo -Name 'r1' | Out-Null
        $marker = Join-Path $script:TestRoot 'final-ran.txt'
        $finalScript = Join-Path $script:TestRoot 'final.cmd'
        Set-Content -Path $finalScript -Value @"
@echo off
echo HELLO_FINAL>"$marker"
exit /b 0
"@ -Encoding ASCII
        Write-Config -Repos @(
            @{ name = 'r1'; path = 'r1'; master = 'main'; auto_merge = $true }
        ) -FinalCommand $finalScript

        $r = Invoke-Sync

        $r.ExitCode | Should -Be 0
        $r.Stdout | Should -Match 'Running final command'
        $r.Stdout | Should -Match 'Final command completed successfully'
        Test-Path $marker | Should -BeTrue
        (Get-Content $marker -Raw) | Should -Match 'HELLO_FINAL'
    }

    It 'absolute repo path resolves outside working_dir' {
        $absRoot = Join-Path $script:TestRoot 'elsewhere'
        New-Item -ItemType Directory -Path $absRoot -Force | Out-Null
        $absRepo = New-FakeRepo -Name 'abs' -Root $absRoot
        Write-Config -Repos @(
            @{ name = 'abs'; path = $absRepo; master = 'main'; auto_merge = $true }
        )

        $r = Invoke-Sync

        $r.ExitCode | Should -Be 0
        $r.Stdout | Should -Match 'abs\s+::\s+OK'
        # All recorded git invocations should have been made from the absolute path.
        $cwds = $r.GitCalls | ForEach-Object { ($_ -split '\|', 2)[0] }
        ($cwds | Where-Object { $_ -ieq $absRepo }).Count | Should -BeGreaterThan 0
    }

    It 'per-repo log file is created at the printed path on failure' {
        New-FakeRepo -Name 'bad' | Out-Null
        Write-Config -Repos @(
            @{ name = 'bad'; path = 'bad'; master = 'main'; auto_merge = $true }
        )

        $r = Invoke-Sync -EnvVars @{ FAKEGIT_FAIL_FIRST = 'push' }

        $r.ExitCode | Should -Be 1
        # Extract the printed log path: "    bad  ::  <path>\bad.log"
        $line = ($r.Stdout -split "`n") | Where-Object { $_ -match 'bad\.log\s*$' } | Select-Object -First 1
        $line | Should -Not -BeNullOrEmpty
        $logPath = ($line -split '::', 2)[1].Trim()
        Test-Path $logPath | Should -BeTrue
    }
}
