#Requires -Version 5.0

if (-not (Get-Variable -Name GitHerdConfigArchitecture -Scope Script -ErrorAction SilentlyContinue)) {
    $script:GitHerdConfigArchitecture = $null
}

function Assert-GitHerdSchemaDescriptor {
    param(
        [Parameter(Mandatory = $true)] $Schema,
        [Parameter(Mandatory = $true)] [int]$ExpectedVersion
    )

    if (-not (Test-GitHerdProperty $Schema 'Version') -or $Schema.Version -ne $ExpectedVersion) {
        throw "Config schema descriptor does not declare version $ExpectedVersion."
    }
    foreach ($operation in @(
        'NewConfig', 'NewRepo', 'AssertShape', 'Normalize',
        'Validate', 'ToCanonicalObject', 'NewPortableExport'
    )) {
        if (-not (Test-GitHerdScriptBlockProperty $Schema $operation)) {
            throw ("Config schema {0} operation '$operation' is missing or invalid." -f
                (Format-GitHerdConfigVersion $ExpectedVersion))
        }
    }
}

function Get-GitHerdVersionPackages {
    param([Parameter(Mandatory = $true)] [string]$VersionsPath)

    if (-not (Test-Path -LiteralPath $VersionsPath -PathType Container)) {
        throw "Config versions directory not found: $VersionsPath"
    }

    $packages = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $VersionsPath -Directory)) {
        if ($directory.Name -cnotmatch '^v[0-9]{4}$') { continue }
        $version = [int]$directory.Name.Substring(1)
        if ($version -eq 0) {
            throw 'Config version package v0000 is reserved for unversioned legacy input.'
        }

        $manifestPath = Join-Path $directory.FullName 'version.psd1'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Config version package $($directory.Name) is missing version.psd1."
        }
        $manifest = $null
        Import-LocalizedData `
            -BindingVariable manifest `
            -BaseDirectory $directory.FullName `
            -FileName 'version.psd1'
        if ($manifest.Version -isnot [int] -or $manifest.Version -ne $version) {
            throw "Config version package $($directory.Name) declares Version $($manifest.Version)."
        }
        if ($manifest.PreviousVersion -isnot [int] -or
            $manifest.PreviousVersion -ne ($version - 1)) {
            throw ("Config version package {0} declares PreviousVersion {1}; expected {2}." -f
                $directory.Name, $manifest.PreviousVersion, ($version - 1))
        }
        if ([string]$manifest.SchemaFile -ne 'schema.ps1') {
            throw "Config version package $($directory.Name) must use SchemaFile 'schema.ps1'."
        }
        $expectedMigration = 'migrate-from-{0}.ps1' -f (Format-GitHerdConfigVersion ($version - 1))
        if ([string]$manifest.IncomingMigrationFile -ne $expectedMigration) {
            throw "Config version package $($directory.Name) must use IncomingMigrationFile '$expectedMigration'."
        }

        $schemaPath = Join-Path $directory.FullName $manifest.SchemaFile
        $migrationPath = Join-Path $directory.FullName $manifest.IncomingMigrationFile
        foreach ($requiredPath in @($schemaPath, $migrationPath)) {
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                throw "Config version package $($directory.Name) is missing $(Split-Path -Leaf $requiredPath)."
            }
        }

        $packages += [pscustomobject]@{
            Version       = $version
            PreviousVersion = $version - 1
            Name          = $directory.Name
            SchemaPath    = $schemaPath
            MigrationPath = $migrationPath
        }
    }
    return @($packages | Sort-Object Version)
}

function Initialize-GitHerdConfigArchitecture {
    param([Parameter(Mandatory = $true)] [string]$VersionsPath)

    if ($script:GitHerdConfigArchitecture) { return }

    $packages = @(Get-GitHerdVersionPackages -VersionsPath $VersionsPath)
    if ($packages.Count -eq 0) {
        throw "No config version packages were found in $VersionsPath."
    }
    for ($i = 0; $i -lt $packages.Count; $i++) {
        $expected = $i + 1
        if ($packages[$i].Version -ne $expected) {
            throw ("Config versions must be contiguous from v0001; expected {0}, found {1}." -f
                (Format-GitHerdConfigVersion $expected), $packages[$i].Name)
        }
    }

    $schemas = @{}
    $handlers = @()
    foreach ($package in $packages) {
        . $package.SchemaPath
        . $package.MigrationPath

        $versionLabel = '{0:D4}' -f $package.Version
        $previousLabel = '{0:D4}' -f $package.PreviousVersion
        $schemaGetter = "Get-GitHerdConfigSchemaV$versionLabel"
        $migrationGetter = "Get-GitHerdConfigMigrationV${previousLabel}ToV$versionLabel"

        $schemaCommand = Get-Command -Name $schemaGetter -CommandType Function -ErrorAction SilentlyContinue
        if (-not $schemaCommand) {
            throw "Config version package $($package.Name) does not define $schemaGetter."
        }
        $migrationCommand = Get-Command -Name $migrationGetter -CommandType Function -ErrorAction SilentlyContinue
        if (-not $migrationCommand) {
            throw "Config version package $($package.Name) does not define $migrationGetter."
        }

        $schema = & $schemaCommand
        Assert-GitHerdSchemaDescriptor -Schema $schema -ExpectedVersion $package.Version
        if ($schemas.ContainsKey($package.Version)) {
            throw "Duplicate config schema version $($package.Version) was registered."
        }
        $schemas[$package.Version] = $schema

        $handler = & $migrationCommand
        Assert-GitHerdMigrationHandler $handler
        if ($handler.SourceVersion -ne $package.PreviousVersion -or
            $handler.TargetVersion -ne $package.Version) {
            throw "Config version package $($package.Name) registered the wrong incoming migration."
        }
        $handlers += $handler
    }

    $currentVersion = $packages[-1].Version
    $chainHead = Connect-GitHerdMigrationChain -Handlers $handlers -CurrentVersion $currentVersion
    $script:GitHerdConfigArchitecture = [pscustomobject]@{
        VersionsPath   = [System.IO.Path]::GetFullPath($VersionsPath)
        CurrentVersion = $currentVersion
        Schemas        = $schemas
        ChainHead      = $chainHead
    }
    $script:CurrentConfigVersion = $currentVersion
}

function Get-CurrentGitHerdConfigSchema {
    if (-not $script:GitHerdConfigArchitecture) {
        throw 'GitHerd config architecture has not been initialized.'
    }
    return $script:GitHerdConfigArchitecture.Schemas[$script:GitHerdConfigArchitecture.CurrentVersion]
}
