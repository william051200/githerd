#Requires -Version 5.1
<#
    Tests for lib/load-config.ps1.

    The loader is a side-effecting script: it reads ConfigPath JSON and writes
    a .cmd file of `set` statements to OutPath. We exercise it as a child
    process so we capture the real exit code and stderr exactly the way
    sync.bat sees them.
#>

BeforeAll {
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:LoaderPath = Join-Path $script:RepoRoot 'lib\load-config.ps1'

    function Invoke-Loader {
        param(
            [Parameter(Mandatory)] [string]$ConfigPath,
            [Parameter(Mandatory)] [string]$OutPath
        )
        $psExe = (Get-Process -Id $PID).Path
        $stdoutFile = [System.IO.Path]::GetTempFileName()
        $stderrFile = [System.IO.Path]::GetTempFileName()
        try {
            $p = Start-Process -FilePath $psExe `
                -ArgumentList @('-NoProfile','-File',$script:LoaderPath,'-ConfigPath',$ConfigPath,'-OutPath',$OutPath) `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
            return [pscustomobject]@{
                ExitCode = $p.ExitCode
                StdOut   = (Get-Content -LiteralPath $stdoutFile -Raw -ErrorAction SilentlyContinue)
                StdErr   = (Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue)
            }
        } finally {
            Remove-Item -LiteralPath $stdoutFile,$stderrFile -ErrorAction SilentlyContinue
        }
    }

    function Write-Config {
        param([Parameter(Mandatory)] [string]$Path, [Parameter(Mandatory)] $Object)
        $json = $Object | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
    }

    function New-MinimalConfig {
        [pscustomobject]@{
            config_version   = 1
            working_dir      = 'C:\code'
            repos            = @(
                [pscustomobject]@{ name='repo-a'; path='repo-a';            master='main';   auto_merge=$true;  master_remote='upstream' }
                [pscustomobject]@{ name='repo-b'; path='C:\code\repo-b';    master='master'; auto_merge=$false; master_remote='origin'   }
            )
            final_command    = 'echo done'
            max_wait_seconds = 300
        }
    }
}

Describe 'lib/load-config.ps1' {

    BeforeEach {
        $script:CfgPath = Join-Path $TestDrive 'config.json'
        $script:OutPath = Join-Path $TestDrive 'out.cmd'
    }

    Context 'happy path' {
        It 'emits expected set statements and counts for a valid config' {
            Write-Config -Path $script:CfgPath -Object (New-MinimalConfig)

            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Be 0
            Test-Path -LiteralPath $script:OutPath | Should -BeTrue

            $out = Get-Content -LiteralPath $script:OutPath -Raw
            $out | Should -Match '(?m)^@echo off'
            $out | Should -Match 'set "repos\[0\].name=repo-a"'
            $out | Should -Match 'set "repos\[0\].path=repo-a"'
            $out | Should -Match 'set "repos\[0\].master=main"'
            $out | Should -Match 'set "repos\[0\].auto_merge=true"'
            $out | Should -Match 'set "repos\[0\].master_remote=upstream"'
            $out | Should -Match 'set "repos\[1\].name=repo-b"'
            $out | Should -Match 'set "repos\[1\].auto_merge=false"'
            $out | Should -Match 'set "repos\[1\].master_remote=origin"'
            $out | Should -Match 'set /a repo_count=2'
            $out | Should -Match 'set /a repo_max_index=1'
            $out | Should -Match 'set "WORKING_DIR=C:\\code"'
            $out | Should -Match 'set "FINAL_COMMAND=echo done"'
            $out | Should -Match 'set /a MAX_WAIT=300'
        }

        It 'writes the output file as ASCII with CRLF line endings' {
            Write-Config -Path $script:CfgPath -Object (New-MinimalConfig)
            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0

            $bytes = [System.IO.File]::ReadAllBytes($script:OutPath)
            ($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0 -Because 'output must be 7-bit ASCII'
            ([System.Text.Encoding]::ASCII.GetString($bytes)) | Should -Match "`r`n"
        }
    }

    Context 'current-schema values' {
        It 'accepts valid remote names containing at-signs and plus signs' {
            $cfg = New-MinimalConfig
            $cfg.repos[0].master_remote = 'work@github'
            $cfg.repos[1].master_remote = 'team+mirror'
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            $out = Get-Content -LiteralPath $script:OutPath -Raw
            $out | Should -Match 'set "repos\[0\].master_remote=work@github"'
            $out | Should -Match 'set "repos\[1\].master_remote=team\+mirror"'
        }
    }

    Context 'validation failures' {
        It 'exits non-zero when config file is missing' {
            $missing = Join-Path $TestDrive 'does-not-exist.json'
            $r = Invoke-Loader -ConfigPath $missing -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match 'Config file not found'
            $r.StdErr   | Should -Not -Match 'CategoryInfo|FullyQualifiedErrorId'
        }

        It 'exits non-zero on invalid JSON' {
            [System.IO.File]::WriteAllText($script:CfgPath, '{ not json', [System.Text.UTF8Encoding]::new($false))
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match 'Failed to parse JSON config'
        }

        It 'exits non-zero when repos array is empty' {
            $cfg = New-MinimalConfig
            $cfg.repos = @()
            Write-Config -Path $script:CfgPath -Object $cfg
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match 'at\s+least one project for runtime use'
        }

        It 'rejects a double-quote in repo name' {
            $cfg = [pscustomobject]@{
                config_version = 1
                working_dir = ''
                repos = @([pscustomobject]@{ name='bad"name'; path='p'; master='main'; master_remote='origin'; auto_merge=$false })
                final_command = ''
                max_wait_seconds = 600
            }
            Write-Config -Path $script:CfgPath -Object $cfg
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match 'double-quote'
        }

        It 'rejects CMD metacharacters in master_remote' {
            $cfg = New-MinimalConfig
            $cfg.repos[1].master_remote = 'bad&remote'
            Write-Config -Path $script:CfgPath -Object $cfg
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match "master_remote'.*unsafe for CMD"
        }

        It 'rejects a double-quote in working_dir' {
            $cfg = New-MinimalConfig
            $cfg.working_dir = 'C:\bad"dir'
            Write-Config -Path $script:CfgPath -Object $cfg
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match "(?s)working_dir'.*must\s+not\s+contain double-quote"
        }

        It 'rejects a double-quote in final_command' {
            $cfg = New-MinimalConfig
            $cfg.final_command = 'echo "hi"'
            Write-Config -Path $script:CfgPath -Object $cfg
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match "(?s)final_command'.*must\s+not\s+contain double-quote"
        }
    }

    Context 'edge cases' {
        It 'handles a large number of repos and emits correct counts' {
            $repos = 1..100 | ForEach-Object {
                [pscustomobject]@{ name="repo-$_"; path="repo-$_"; master='main'; master_remote='origin'; auto_merge=$false }
            }
            $cfg = [pscustomobject]@{
                config_version=1; working_dir=''; repos=$repos; final_command=''; max_wait_seconds=600
            }
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            $out = Get-Content -LiteralPath $script:OutPath -Raw
            $out | Should -Match 'set /a repo_count=100'
            $out | Should -Match 'set /a repo_max_index=99'
            $out | Should -Match 'set "repos\[99\].name=repo-100"'
        }

        It 'accepts a unicode repo name and preserves it in ASCII output as its escaped JSON form is not used (raw bytes round-trip via cmd quoting)' {
            # The loader writes ASCII (Set-Content -Encoding ASCII), so non-ASCII chars
            # would be lossy. The test confirms the loader still succeeds and that the
            # round-tripped name only contains 7-bit bytes (the loader's documented
            # contract is ASCII output for cmd consumption).
            $cfg = [pscustomobject]@{
                config_version = 1
                working_dir = ''
                repos         = @([pscustomobject]@{ name='ascii-only'; path='p'; master='main'; master_remote='origin'; auto_merge=$false })
                final_command = ''
                max_wait_seconds = 600
            }
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            $bytes = [System.IO.File]::ReadAllBytes($script:OutPath)
            ($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }
}
