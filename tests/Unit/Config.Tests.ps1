#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ConfigModule = Join-Path $script:RepoRoot 'lib\config.ps1'
    . $script:ConfigModule

    function New-TestConfig {
        param(
            [string]$Name = 'repo-a',
            [string]$Path = 'repo-a',
            [string]$Remote = 'upstream',
            [string]$Master = 'main',
            [bool]$AutoMerge = $true
        )

        [pscustomobject]@{
            config_version   = 1
            working_dir      = 'C:\code'
            repos            = @(
                [pscustomobject]@{
                    name          = $Name
                    path          = $Path
                    master_remote = $Remote
                    master        = $Master
                    auto_merge    = $AutoMerge
                }
            )
            final_command    = 'echo done'
            max_wait_seconds = 600
        }
    }

    function Write-TestJson {
        param([string]$Path, $Value)
        [IO.File]::WriteAllText(
            $Path,
            ($Value | ConvertTo-Json -Depth 10),
            [Text.UTF8Encoding]::new($false)
        )
    }
}

Describe 'GitHerd config versioning and migrations' {
    BeforeEach {
        . $script:ConfigModule
    }

    It 'treats an unversioned config as v0000 and migrates it to v0001' {
        $legacy = [pscustomobject]@{
            working_dir = 'C:\code'
            repos = @(
                [pscustomobject]@{ name='saved'; path='saved'; master_remote='company'; pull_remote='ignored'; master='main'; auto_merge=$false }
                [pscustomobject]@{ name='pull'; path='pull'; pull_remote='mirror'; master='main'; auto_merge=$false }
                [pscustomobject]@{ name='merge'; path='merge'; master='main'; auto_merge=$true }
                [pscustomobject]@{ name='origin'; path='origin'; master='main'; auto_merge=$false }
            )
        }

        $result = ConvertTo-CurrentGitHerdConfig -Config $legacy -ForRuntime

        $result.config_version | Should -Be 1
        @($result.repos.master_remote) | Should -Be @('company', 'mirror', 'upstream', 'origin')
        foreach ($repo in $result.repos) {
            $repo.PSObject.Properties.Name | Should -Not -Contain 'pull_remote'
        }
        $result.final_command | Should -Be ''
        $result.max_wait_seconds | Should -Be 600
    }

    It 'runs every intermediate migration exactly once and in order' {
        $script:MigrationLog = @()
        $handlers = @(
            [pscustomobject]@{
                SourceVersion = 0
                TargetVersion = 1
                Next = $null
                Migrate = {
                    param($Config)
                    $script:MigrationLog += '0-to-1'
                    $Config | Add-Member -NotePropertyName config_version -NotePropertyValue 1
                    return $Config
                }
            },
            [pscustomobject]@{
                SourceVersion = 1
                TargetVersion = 2
                Next = $null
                Migrate = {
                    param($Config)
                    $script:MigrationLog += '1-to-2'
                    $Config.config_version = 2
                    return $Config
                }
            },
            [pscustomobject]@{
                SourceVersion = 2
                TargetVersion = 3
                Next = $null
                Migrate = {
                    param($Config)
                    $script:MigrationLog += '2-to-3'
                    $Config.config_version = 3
                    return $Config
                }
            }
        )
        $chain = Connect-GitHerdMigrationChain -Handlers $handlers -CurrentVersion 3
        $result = Invoke-GitHerdMigrationChain -Handler $chain -Config ([pscustomobject]@{}) -CurrentVersion 3

        $result.config_version | Should -Be 3
        $script:MigrationLog | Should -Be @('0-to-1', '1-to-2', '2-to-3')
    }

    It 'does not migrate current-version input again' {
        $handler = [pscustomobject]@{
            SourceVersion = 0
            TargetVersion = 1
            Next = $null
            Migrate = { throw 'must not run' }
        }
        { Invoke-GitHerdMigrationChain -Handler $handler -Config (New-TestConfig) -CurrentVersion 1 } |
            Should -Not -Throw
    }

    It 'fails when an intermediate migration is missing' {
        $handlers = @(
            [pscustomobject]@{ SourceVersion=0; TargetVersion=1; Next=$null; Migrate={ param($c) $c } },
            [pscustomobject]@{ SourceVersion=2; TargetVersion=3; Next=$null; Migrate={ param($c) $c } }
        )
        { Connect-GitHerdMigrationChain -Handlers $handlers -CurrentVersion 3 } |
            Should -Throw '*expected 3*'
    }

    It 'rejects invalid and future versions' -ForEach @(
        @{ Version = '1'; Message = '*positive integer*' }
        @{ Version = 0; Message = '*positive integer*' }
        @{ Version = -1; Message = '*positive integer*' }
        @{ Version = 2; Message = '*newer GitHerd version is required*' }
    ) {
        $cfg = New-TestConfig
        $cfg.config_version = $Version
        { ConvertTo-CurrentGitHerdConfig -Config $cfg } | Should -Throw $Message
    }

    It 'does not mutate the caller object when a migration fails' {
        $handler = [pscustomobject]@{
            SourceVersion = 1
            TargetVersion = 2
            Next = $null
            Migrate = {
                param($Config)
                $Config.repos[0].name = 'mutated'
                throw 'planned failure'
            }
        }
        $source = New-TestConfig

        { Invoke-GitHerdMigrationChain -Handler $handler -Config $source -CurrentVersion 2 } |
            Should -Throw '*planned failure*'
        $source.repos[0].name | Should -Be 'repo-a'
        $source.config_version | Should -Be 1
    }

    It 'returns singleton schema and migration handler instances' {
        [object]::ReferenceEquals(
            (Get-GitHerdConfigSchemaV0001),
            (Get-GitHerdConfigSchemaV0001)
        ) | Should -BeTrue
        [object]::ReferenceEquals(
            (Get-GitHerdConfigMigrationV0000ToV0001),
            (Get-GitHerdConfigMigrationV0000ToV0001)
        ) | Should -BeTrue
    }

    It 'derives the current version from the highest discovered package' {
        $packages = @(Get-GitHerdVersionPackages -VersionsPath (Join-Path $script:RepoRoot 'lib\config\versions'))

        $packages.Name | Should -Be @('v0001')
        $script:CurrentConfigVersion | Should -Be $packages[-1].Version
        (Get-CurrentGitHerdConfigSchema).Version | Should -Be $packages[-1].Version
    }

    It 'keeps schema-specific field names out of the core engine' {
        $coreText = Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'lib\config\core') -Filter '*.ps1' |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        ($coreText -join "`n") | Should -Not -Match '\b(master_remote|auto_merge|max_wait_seconds)\b'
    }
}

Describe 'GitHerd config validation and reading' {
    BeforeEach {
        . $script:ConfigModule
    }

    It 'reads config.example.json as a valid current runtime config' {
        $config = Read-GitHerdConfig -Path (Join-Path $script:RepoRoot 'config.example.json') -ForRuntime
        $config.config_version | Should -Be 1
        $config.repos.Count | Should -Be 2
    }

    It 'reports malformed JSON explicitly instead of returning defaults' {
        $path = Join-Path $TestDrive 'bad.json'
        [IO.File]::WriteAllText($path, '{not json', [Text.UTF8Encoding]::new($false))

        { Read-GitHerdConfig -Path $path } | Should -Throw '*Failed to parse JSON config*'
    }

    It 'rejects duplicate names case-insensitively' {
        $cfg = New-TestConfig
        $cfg.repos += [pscustomobject]@{
            name='REPO-A'; path='other'; master_remote='origin'; master='main'; auto_merge=$false
        }

        { ConvertTo-CurrentGitHerdConfig -Config $cfg -ForRuntime } | Should -Throw '*case-insensitively unique*'
    }

    It 'allows portable blank paths but rejects them for runtime use' {
        $cfg = New-TestConfig
        $cfg.repos[0].path = ''

        { ConvertTo-CurrentGitHerdConfig -Config $cfg } | Should -Not -Throw
        { ConvertTo-CurrentGitHerdConfig -Config $cfg -ForRuntime } | Should -Throw '*required for runtime use*'
    }

    It 'rejects a current-schema project with a missing required field' {
        $cfg = New-TestConfig
        $cfg.repos[0].PSObject.Properties.Remove('path')

        { ConvertTo-CurrentGitHerdConfig -Config $cfg } | Should -Throw "*field 'path' is required*"
    }

    It 'rejects unsafe remotes, double quotes, and invalid timeouts' -ForEach @(
        @{ Mutate = { param($c) $c.repos[0].master_remote = 'bad&remote' }; Message = '*master_remote*unsafe for CMD*' }
        @{ Mutate = { param($c) $c.working_dir = 'C:\bad"dir' }; Message = '*working_dir*double-quote*' }
        @{ Mutate = { param($c) $c.max_wait_seconds = 9 }; Message = '*between 10 and 86400*' }
        @{ Mutate = { param($c) $c.max_wait_seconds = '600' }; Message = '*must be an integer*' }
    ) {
        $cfg = New-TestConfig
        & $Mutate $cfg
        { ConvertTo-CurrentGitHerdConfig -Config $cfg -ForRuntime } | Should -Throw $Message
    }
}

Describe 'GitHerd canonical JSON and file handling' {
    BeforeEach {
        . $script:ConfigModule
    }

    It 'matches canonical golden files' -ForEach @(
        @{
            Fixture = 'empty.json'
            Config = {
                New-GitHerdConfig
            }
        }
        @{
            Fixture = 'multi-project.json'
            Config = {
                $cfg = New-TestConfig
                $cfg.repos += [pscustomobject]@{
                    name='repo-b'; path='C:\code\repo-b'; master_remote='origin'; master='dev'; auto_merge=$false
                }
                $cfg
            }
        }
        @{
            Fixture = 'escaped-windows-path.json'
            Config = {
                New-TestConfig -Path 'C:\Users\example\source\repo-a'
            }
        }
        @{
            Fixture = 'portable-export.json'
            Config = {
                New-GitHerdExportConfig -Config (New-TestConfig)
            }
        }
    ) {
        $expectedPath = Join-Path $script:RepoRoot "tests\Fixtures\Config\$Fixture"
        (ConvertTo-GitHerdJson -Config (& $Config)) |
            Should -BeExactly ([IO.File]::ReadAllText($expectedPath))
    }

    It 'writes UTF-8 without BOM and exactly one final newline' {
        $path = Join-Path $TestDrive 'config.json'
        Write-GitHerdConfig -Path $path -Config (New-TestConfig)

        $bytes = [IO.File]::ReadAllBytes($path)
        ($bytes[0..2] -join ',') | Should -Not -Be '239,187,191'
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        $text | Should -Match "(?<!`n)`n$"
        $text | Should -Not -Match "`n`n$"
        $text | Should -Not -Match '(?m)[ \t]+$'
    }

    It 'creates a portable export without mutating its source' {
        $source = New-TestConfig -Path 'C:\code\repo-a'
        $export = New-GitHerdExportConfig -Config $source

        $export.config_version | Should -Be 1
        $export.working_dir | Should -Be ''
        $export.repos[0].path | Should -Be ''
        $export.repos[0].master_remote | Should -Be 'upstream'
        $export.final_command | Should -Be 'echo done'
        $source.working_dir | Should -Be 'C:\code'
        $source.repos[0].path | Should -Be 'C:\code\repo-a'
    }

    It 'leaves the previous destination intact when atomic replacement fails' {
        $path = Join-Path $TestDrive 'config.json'
        [IO.File]::WriteAllText($path, 'original', [Text.UTF8Encoding]::new($false))
        $lock = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            { Write-GitHerdConfig -Path $path -Config (New-TestConfig) } | Should -Throw
        } finally {
            $lock.Dispose()
        }
        [IO.File]::ReadAllText($path) | Should -BeExactly 'original'
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.githerd-config-*.tmp').Count | Should -Be 0
    }
}
