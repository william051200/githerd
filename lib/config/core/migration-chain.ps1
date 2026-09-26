#Requires -Version 5.0

function Assert-GitHerdMigrationHandler {
    param([Parameter(Mandatory = $true)] $Handler)

    foreach ($property in @('SourceVersion', 'TargetVersion', 'Next', 'Migrate')) {
        if (-not (Test-GitHerdProperty $Handler $property)) {
            throw "Config migration handler is missing '$property'."
        }
    }
    if ($Handler.SourceVersion -isnot [int] -or $Handler.TargetVersion -isnot [int]) {
        throw 'Config migration handler versions must be integers.'
    }
    if ($Handler.TargetVersion -ne ($Handler.SourceVersion + 1)) {
        throw ("Migration handler {0}-to-{1} must target the immediate next version." -f
            (Format-GitHerdConfigVersion $Handler.SourceVersion),
            (Format-GitHerdConfigVersion $Handler.TargetVersion))
    }
    if ($Handler.Migrate -isnot [scriptblock]) {
        throw 'Config migration handler Migrate must be a script block.'
    }
}

function Connect-GitHerdMigrationChain {
    param(
        [Parameter(Mandatory = $true)] [object[]]$Handlers,
        [Parameter(Mandatory = $true)] [int]$CurrentVersion
    )

    $ordered = @($Handlers | Sort-Object SourceVersion)
    if ($ordered.Count -ne $CurrentVersion) {
        throw "Migration chain has $($ordered.Count) handlers; expected $CurrentVersion."
    }

    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $handler = $ordered[$i]
        Assert-GitHerdMigrationHandler $handler
        if ($handler.SourceVersion -ne $i -or $handler.TargetVersion -ne ($i + 1)) {
            throw ("Migration chain expected {0}-to-{1}, found {2}-to-{3}." -f
                (Format-GitHerdConfigVersion $i),
                (Format-GitHerdConfigVersion ($i + 1)),
                (Format-GitHerdConfigVersion $handler.SourceVersion),
                (Format-GitHerdConfigVersion $handler.TargetVersion))
        }
        $handler.Next = if ($i -lt ($ordered.Count - 1)) { $ordered[$i + 1] } else { $null }
    }
    return $ordered[0]
}

function Invoke-GitHerdMigrationChain {
    param(
        [Parameter(Mandatory = $true)] $Handler,
        [Parameter(Mandatory = $true)] $Config,
        [Parameter(Mandatory = $true)] [int]$CurrentVersion
    )

    $version = Get-GitHerdConfigVersion $Config
    if ($version -eq $CurrentVersion) {
        return $Config
    }
    if ($version -gt $Handler.SourceVersion) {
        if ($null -eq $Handler.Next) {
            throw ("Migration chain ended at {0}, but current schema is {1}." -f
                (Format-GitHerdConfigVersion $version),
                (Format-GitHerdConfigVersion $CurrentVersion))
        }
        return Invoke-GitHerdMigrationChain -Handler $Handler.Next -Config $Config -CurrentVersion $CurrentVersion
    }
    if ($version -lt $Handler.SourceVersion) {
        throw ("Migration chain cannot handle schema {0}; next handler starts at {1}." -f
            (Format-GitHerdConfigVersion $version),
            (Format-GitHerdConfigVersion $Handler.SourceVersion))
    }

    try {
        $nextConfig = & $Handler.Migrate (Copy-GitHerdValue $Config)
    } catch {
        throw ("Failed config migration from {0} to {1}: {2}" -f
            (Format-GitHerdConfigVersion $Handler.SourceVersion),
            (Format-GitHerdConfigVersion $Handler.TargetVersion),
            $_.Exception.Message)
    }
    if ($null -eq $nextConfig) {
        throw ("Failed config migration from {0} to {1}: migration returned no config." -f
            (Format-GitHerdConfigVersion $Handler.SourceVersion),
            (Format-GitHerdConfigVersion $Handler.TargetVersion))
    }

    $newVersion = Get-GitHerdConfigVersion $nextConfig
    if ($newVersion -ne $Handler.TargetVersion) {
        throw ("Migration handler {0}-to-{1} returned schema {2}." -f
            (Format-GitHerdConfigVersion $Handler.SourceVersion),
            (Format-GitHerdConfigVersion $Handler.TargetVersion),
            (Format-GitHerdConfigVersion $newVersion))
    }
    if ($newVersion -eq $CurrentVersion) {
        return $nextConfig
    }
    if ($null -eq $Handler.Next) {
        throw ("Migration chain ended at {0}, but current schema is {1}." -f
            (Format-GitHerdConfigVersion $newVersion),
            (Format-GitHerdConfigVersion $CurrentVersion))
    }
    return Invoke-GitHerdMigrationChain -Handler $Handler.Next -Config $nextConfig -CurrentVersion $CurrentVersion
}
