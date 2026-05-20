#Requires -Version 5.1
<#
    Behavioural tests for lib/update-check.ps1.

    update-check.ps1 is a script (not a module) so its helpers aren't
    importable for in-process mocking. We exercise it as a child process
    and only assert observable behaviour:

        * GITHERD_NO_UPDATE_CHECK=1 short-circuits silently.
        * With a fresh cache (last_checked_unix = now) the script never
          hits the network: it either skips outright (before noon MYT)
          or honours the cache (after noon MYT). Either way, the cached
          hint is printed when the cached tag is newer than VERSION,
          and not printed when it isn't.

    We isolate the cache by pointing $env:LOCALAPPDATA at a fresh
    TestDrive directory before each test.
#>

BeforeAll {
    $script:RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ScriptPath  = Join-Path $script:RepoRoot 'lib\update-check.ps1'
    $script:LocalVerRaw = (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'VERSION') -Raw).Trim()

    function Invoke-UpdateCheck {
        param(
            [string]$LocalAppData,
            [hashtable]$ExtraEnv = @{}
        )
        $psExe   = (Get-Process -Id $PID).Path
        $stdout  = [System.IO.Path]::GetTempFileName()
        $stderr  = [System.IO.Path]::GetTempFileName()

        $originalLAD = $env:LOCALAPPDATA
        $originalNoCheck = $env:GITHERD_NO_UPDATE_CHECK
        try {
            if ($LocalAppData) { $env:LOCALAPPDATA = $LocalAppData }
            foreach ($k in $ExtraEnv.Keys) { Set-Item -Path "Env:\$k" -Value $ExtraEnv[$k] }
            $p = Start-Process -FilePath $psExe `
                -ArgumentList @('-NoProfile','-File',$script:ScriptPath) `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            return [pscustomobject]@{
                ExitCode = $p.ExitCode
                StdOut   = (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
                StdErr   = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
            }
        } finally {
            foreach ($k in $ExtraEnv.Keys) { Remove-Item -Path "Env:\$k" -ErrorAction SilentlyContinue }
            $env:LOCALAPPDATA = $originalLAD
            if ($null -ne $originalNoCheck) { $env:GITHERD_NO_UPDATE_CHECK = $originalNoCheck }
            Remove-Item -LiteralPath $stdout,$stderr -ErrorAction SilentlyContinue
        }
    }

    function Write-Cache {
        param(
            [Parameter(Mandatory)] [string]$LocalAppData,
            [Parameter(Mandatory)] [string]$Tag,
            [datetime]$LastCheckedUtc = ([DateTime]::UtcNow)
        )
        $dir = Join-Path $LocalAppData 'GitHerd'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $obj = [pscustomobject]@{
            last_checked_unix = [int64]([DateTimeOffset]::new($LastCheckedUtc, [TimeSpan]::Zero).ToUnixTimeSeconds())
            last_checked_utc  = $LastCheckedUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
            latest_tag        = $Tag
        }
        $path = Join-Path $dir 'update-check.json'
        $obj | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
        return $path
    }
}

Describe 'lib/update-check.ps1' {

    BeforeEach {
        $script:Lad = Join-Path $TestDrive ("lad-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Lad -Force | Out-Null
    }

    Context 'opt-out env var' {
        It 'exits 0 silently when GITHERD_NO_UPDATE_CHECK=1' {
            $r = Invoke-UpdateCheck -LocalAppData $script:Lad -ExtraEnv @{ GITHERD_NO_UPDATE_CHECK = '1' }
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -BeNullOrEmpty
        }
    }

    Context 'cached hint' {
        It 'prints the cached hint when cached tag is newer than local VERSION' {
            $newer = "v999.999.999"
            Write-Cache -LocalAppData $script:Lad -Tag $newer | Out-Null

            $r = Invoke-UpdateCheck -LocalAppData $script:Lad
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Match '\[update\] v999\.999\.999 is available'
        }

        It 'prints nothing when cached tag equals local VERSION' {
            Write-Cache -LocalAppData $script:Lad -Tag ("v" + $script:LocalVerRaw) | Out-Null

            $r = Invoke-UpdateCheck -LocalAppData $script:Lad
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Not -Match '\[update\]'
        }

        It 'prints nothing when cached tag is older than local VERSION' {
            Write-Cache -LocalAppData $script:Lad -Tag 'v0.0.1' | Out-Null

            $r = Invoke-UpdateCheck -LocalAppData $script:Lad
            $r.ExitCode | Should -Be 0
            $r.StdOut   | Should -Not -Match '\[update\]'
        }
    }
}
