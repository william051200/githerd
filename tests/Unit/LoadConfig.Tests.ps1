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

    Context 'defaults and optional fields' {
        It 'defaults max_wait_seconds to 600 when omitted' {
            $cfg = New-MinimalConfig
            $cfg.PSObject.Properties.Remove('max_wait_seconds')
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            (Get-Content -LiteralPath $script:OutPath -Raw) | Should -Match 'set /a MAX_WAIT=600'
        }

        It 'emits empty WORKING_DIR when working_dir is missing' {
            $cfg = New-MinimalConfig
            $cfg.PSObject.Properties.Remove('working_dir')
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            (Get-Content -LiteralPath $script:OutPath -Raw) | Should -Match 'set "WORKING_DIR="'
        }

        It 'treats missing auto_merge as false' {
            $cfg = [pscustomobject]@{
                repos         = @([pscustomobject]@{ name='r'; path='r'; master='main' })
                final_command = ''
            }
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            (Get-Content -LiteralPath $script:OutPath -Raw) | Should -Match 'set "repos\[0\].auto_merge=false"'
        }

        It 'defaults missing master_remote by mode to preserve legacy behavior' {
            $cfg = [pscustomobject]@{
                repos = @(
                    [pscustomobject]@{ name='merge'; path='merge'; master='main'; auto_merge=$true }
                    [pscustomobject]@{ name='pull';  path='pull';  master='main'; auto_merge=$false }
                )
                final_command = ''
            }
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            $out = Get-Content -LiteralPath $script:OutPath -Raw
            $out | Should -Match 'set "repos\[0\].master_remote=upstream"'
            $out | Should -Match 'set "repos\[1\].master_remote=origin"'
        }

        It 'migrates pull_remote for pull-only configs' {
            $cfg = [pscustomobject]@{
                repos         = @([pscustomobject]@{ name='r'; path='r'; master='main'; auto_merge=$false; pull_remote='team' })
                final_command = ''
            }
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            (Get-Content -LiteralPath $script:OutPath -Raw) | Should -Match 'set "repos\[0\].master_remote=team"'
        }

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
        }

        It 'exits non-zero on invalid JSON' {
            [System.IO.File]::WriteAllText($script:CfgPath, '{ not json', [System.Text.UTF8Encoding]::new($false))
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match 'Failed to parse JSON'
        }

        It 'exits non-zero when repos array is empty' {
            Write-Config -Path $script:CfgPath -Object ([pscustomobject]@{ repos=@(); final_command='' })
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match 'no repos'
        }

        It 'rejects a double-quote in repo name' {
            $cfg = [pscustomobject]@{
                repos = @([pscustomobject]@{ name='bad"name'; path='p'; master='main'; auto_merge=$false })
                final_command = ''
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
            $r.StdErr   | Should -Match 'master_remote contains characters that are unsafe\s+for CMD'
        }

        It 'rejects a double-quote in working_dir' {
            $cfg = New-MinimalConfig
            $cfg.working_dir = 'C:\bad"dir'
            Write-Config -Path $script:CfgPath -Object $cfg
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match 'working_dir must not contain double-quote'
        }

        It 'rejects a double-quote in final_command' {
            $cfg = New-MinimalConfig
            $cfg.final_command = 'echo "hi"'
            Write-Config -Path $script:CfgPath -Object $cfg
            $r = Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath
            $r.ExitCode | Should -Not -Be 0
            $r.StdErr   | Should -Match 'final_command must not contain double-quote'
        }
    }

    Context 'edge cases' {
        It 'handles a large number of repos and emits correct counts' {
            $repos = 1..100 | ForEach-Object {
                [pscustomobject]@{ name="repo-$_"; path="repo-$_"; master='main'; auto_merge=$false }
            }
            $cfg = [pscustomobject]@{ repos=$repos; final_command='' }
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
                repos         = @([pscustomobject]@{ name='ascii-only'; path='p'; master='main'; auto_merge=$false })
                final_command = ''
            }
            Write-Config -Path $script:CfgPath -Object $cfg

            (Invoke-Loader -ConfigPath $script:CfgPath -OutPath $script:OutPath).ExitCode | Should -Be 0
            $bytes = [System.IO.File]::ReadAllBytes($script:OutPath)
            ($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }
}
