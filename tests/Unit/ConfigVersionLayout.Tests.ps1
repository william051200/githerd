#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Validator = Join-Path $script:RepoRoot 'tests\Validate-ConfigVersionLayout.ps1'

    function Invoke-LayoutValidator {
        param([Parameter(Mandatory = $true)] [string]$VersionsPath)

        $output = & $script:Validator -VersionsPath $VersionsPath 2>&1
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = ($output -join "`n")
        }
    }
}

Describe 'Config version package naming' {
    It 'accepts the repository version layout' {
        $versions = Join-Path $script:RepoRoot 'lib\config\versions'
        { & $script:Validator -VersionsPath $versions } | Should -Not -Throw
    }

    It 'rejects an unpadded version directory' {
        $versions = Join-Path $TestDrive 'unpadded\versions'
        New-Item -ItemType Directory -Path (Join-Path $versions 'v1') -Force | Out-Null

        { & $script:Validator -VersionsPath $versions } |
            Should -Throw '*exact vNNNN format*'
    }

    It 'rejects an uppercase version directory' {
        $versions = Join-Path $TestDrive 'uppercase\versions'
        New-Item -ItemType Directory -Path (Join-Path $versions 'V0001') -Force | Out-Null

        { & $script:Validator -VersionsPath $versions } |
            Should -Throw '*exact vNNNN format*'
    }

    It 'rejects an unpadded schema getter' {
        $versions = Join-Path $TestDrive 'getter\versions'
        $package = Join-Path $versions 'v0001'
        New-Item -ItemType Directory -Path $package -Force | Out-Null
        @"
@{
    Version = 1
    SchemaFile = 'schema.ps1'
    PreviousVersion = 0
    IncomingMigrationFile = 'migrate-from-v0000.ps1'
}
"@ | Set-Content -LiteralPath (Join-Path $package 'version.psd1') -Encoding ASCII
        'function Get-GitHerdConfigSchemaV1 { }' |
            Set-Content -LiteralPath (Join-Path $package 'schema.ps1') -Encoding ASCII
        'function Get-GitHerdConfigMigrationV0000ToV0001 { }' |
            Set-Content -LiteralPath (Join-Path $package 'migrate-from-v0000.ps1') -Encoding ASCII

        { & $script:Validator -VersionsPath $versions } |
            Should -Throw '*Get-GitHerdConfigSchemaV0001*'
    }
}
