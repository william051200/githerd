#Requires -Version 5.0

function New-GitHerdRepoConfig {
    $schema = Get-CurrentGitHerdConfigSchema
    return & $schema.NewRepo
}

function New-GitHerdConfig {
    $schema = Get-CurrentGitHerdConfigSchema
    return & $schema.NewConfig
}

function Test-GitHerdConfig {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [switch]$ForRuntime
    )

    $schema = Get-CurrentGitHerdConfigSchema
    $version = Get-GitHerdConfigVersion $Config
    if ($version -ne $schema.Version) {
        throw ("Config schema {0} is not the current schema {1}." -f
            (Format-GitHerdConfigVersion $version),
            (Format-GitHerdConfigVersion $schema.Version))
    }
    & $schema.AssertShape $Config
    & $schema.Validate $Config ([bool]$ForRuntime)
    return $true
}

function ConvertTo-CurrentGitHerdConfig {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [switch]$ForRuntime
    )

    $architecture = $script:GitHerdConfigArchitecture
    $working = Copy-GitHerdValue $Config
    $version = Get-GitHerdConfigVersion $working
    if ($version -gt $architecture.CurrentVersion) {
        throw ("Config schema {0} is newer than supported schema {1}. A newer GitHerd version is required." -f
            (Format-GitHerdConfigVersion $version),
            (Format-GitHerdConfigVersion $architecture.CurrentVersion))
    }
    if ($version -lt $architecture.CurrentVersion) {
        $working = Invoke-GitHerdMigrationChain `
            -Handler $architecture.ChainHead `
            -Config $working `
            -CurrentVersion $architecture.CurrentVersion
    }

    $schema = Get-CurrentGitHerdConfigSchema
    & $schema.AssertShape $working
    $normalized = & $schema.Normalize $working
    & $schema.Validate $normalized ([bool]$ForRuntime)
    return $normalized
}

function Read-GitHerdConfig {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [switch]$ForRuntime
    )

    $source = $Path
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $example = Join-Path (Split-Path -Parent $source) 'config.example.json'
        if (([System.IO.Path]::GetFullPath($example) -ne [System.IO.Path]::GetFullPath($source)) -and
            (Test-Path -LiteralPath $example -PathType Leaf)) {
            $source = $example
        } else {
            return New-GitHerdConfig
        }
    }

    $raw = Read-GitHerdConfigText -Path $source
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Failed to parse config '$source': the file is empty."
    }
    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse JSON config '$source': $($_.Exception.Message)"
    }
    if ($null -eq $parsed -or $parsed -is [System.Array]) {
        throw "Failed to parse config '$source': the root value must be an object."
    }
    return ConvertTo-CurrentGitHerdConfig -Config $parsed -ForRuntime:$ForRuntime
}

function ConvertTo-GitHerdJson {
    param([Parameter(Mandatory = $true)] $Config)

    $current = ConvertTo-CurrentGitHerdConfig -Config $Config
    $schema = Get-CurrentGitHerdConfigSchema
    $ordered = & $schema.ToCanonicalObject $current
    return ConvertTo-CanonicalGitHerdJson $ordered
}

function Write-GitHerdConfig {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] $Config
    )

    Write-GitHerdConfigText -Path $Path -Text (ConvertTo-GitHerdJson $Config)
}

function New-GitHerdExportConfig {
    param([Parameter(Mandatory = $true)] $Config)

    $current = ConvertTo-CurrentGitHerdConfig -Config $Config -ForRuntime
    $schema = Get-CurrentGitHerdConfigSchema
    $export = & $schema.NewPortableExport $current
    [void](Test-GitHerdConfig $export)
    return $export
}
