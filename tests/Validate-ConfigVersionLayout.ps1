#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$VersionsPath = (Join-Path $PSScriptRoot '..\lib\config\versions')
)

$ErrorActionPreference = 'Stop'

function Get-FunctionNames {
    param([Parameter(Mandatory = $true)] [string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -gt 0) {
        throw "Cannot parse '$Path': $($errors.Message -join '; ')"
    }
    return @(
        $ast.FindAll({
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true) | ForEach-Object {
            $_.Name -replace '^script:', ''
        }
    )
}

if (-not (Test-Path -LiteralPath $VersionsPath -PathType Container)) {
    throw "Config versions directory not found: $VersionsPath"
}

$packages = @()
foreach ($directory in @(Get-ChildItem -LiteralPath $VersionsPath -Directory)) {
    if ($directory.Name -match '^[vV][0-9]+$' -and $directory.Name -cnotmatch '^v[0-9]{4}$') {
        throw "Config version directory '$($directory.Name)' must use the exact vNNNN format."
    }
    if ($directory.Name -cnotmatch '^v[0-9]{4}$') { continue }
    if ($directory.Name -eq 'v0000') {
        throw 'Config version directory v0000 is reserved for legacy unversioned input.'
    }

    $version = [int]$directory.Name.Substring(1)
    if ($version -lt 1 -or $version -gt 9999) {
        throw "Config version directory '$($directory.Name)' is outside the supported range."
    }
    $expectedDirectoryName = 'v{0:D4}' -f $version
    if ($directory.Name -cne $expectedDirectoryName) {
        throw "Config version directory '$($directory.Name)' must be '$expectedDirectoryName'."
    }

    $manifestPath = Join-Path $directory.FullName 'version.psd1'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Config version package '$($directory.Name)' is missing version.psd1."
    }
    $manifest = $null
    Import-LocalizedData `
        -BindingVariable manifest `
        -BaseDirectory $directory.FullName `
        -FileName 'version.psd1'
    if ($manifest.Version -isnot [int] -or $manifest.Version -ne $version) {
        throw "Config version package '$($directory.Name)' has an invalid integer Version."
    }
    if ($manifest.PreviousVersion -isnot [int] -or
        $manifest.PreviousVersion -ne ($version - 1)) {
        throw "Config version package '$($directory.Name)' must declare PreviousVersion $($version - 1)."
    }
    if ([string]$manifest.SchemaFile -cne 'schema.ps1') {
        throw "Config version package '$($directory.Name)' must use schema.ps1."
    }

    $previousName = 'v{0:D4}' -f $manifest.PreviousVersion
    $expectedMigrationFile = "migrate-from-$previousName.ps1"
    if ([string]$manifest.IncomingMigrationFile -cne $expectedMigrationFile) {
        throw "Config version package '$($directory.Name)' must use $expectedMigrationFile."
    }

    $schemaPath = Join-Path $directory.FullName 'schema.ps1'
    $migrationPath = Join-Path $directory.FullName $expectedMigrationFile
    foreach ($requiredPath in @($schemaPath, $migrationPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Config version package '$($directory.Name)' is missing $(Split-Path -Leaf $requiredPath)."
        }
    }

    $versionDigits = '{0:D4}' -f $version
    $previousDigits = '{0:D4}' -f $manifest.PreviousVersion
    $expectedSchemaGetter = "Get-GitHerdConfigSchemaV$versionDigits"
    $expectedMigrationGetter = "Get-GitHerdConfigMigrationV${previousDigits}ToV$versionDigits"
    if ((Get-FunctionNames $schemaPath) -cnotcontains $expectedSchemaGetter) {
        throw "Config version package '$($directory.Name)' must define $expectedSchemaGetter."
    }
    if ((Get-FunctionNames $migrationPath) -cnotcontains $expectedMigrationGetter) {
        throw "Config version package '$($directory.Name)' must define $expectedMigrationGetter."
    }

    $packages += $version
}

if ($packages.Count -eq 0) {
    throw 'No config version packages were found.'
}
$packages = @($packages | Sort-Object)
for ($i = 0; $i -lt $packages.Count; $i++) {
    if ($packages[$i] -ne ($i + 1)) {
        throw ("Config version packages must be contiguous; expected v{0:D4}." -f ($i + 1))
    }
}

Write-Host "Config version layout: valid ($($packages.Count) package(s))."
