#Requires -Version 5.0

function Test-GitHerdProperty {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string]$Name
    )

    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return $Object.PSObject.Properties.Match($Name).Count -gt 0
}

function Copy-GitHerdValue {
    param($Value)

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) {
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $copy[[string]$key] = Copy-GitHerdValue $Value[$key]
        }
        return [pscustomobject]$copy
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        return @($Value | ForEach-Object { Copy-GitHerdValue $_ })
    }

    $copy = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.MemberType -in @('NoteProperty', 'Property')) {
            $copy[$property.Name] = Copy-GitHerdValue $property.Value
        }
    }
    return [pscustomobject]$copy
}

function Format-GitHerdConfigVersion {
    param([Parameter(Mandatory = $true)] [int]$Version)

    if ($Version -lt 0 -or $Version -gt 9999) {
        throw "Config version $Version cannot be represented as vNNNN."
    }
    return 'v{0:D4}' -f $Version
}

function Get-GitHerdConfigVersion {
    param([Parameter(Mandatory = $true)] $Config)

    if (-not (Test-GitHerdProperty -Object $Config -Name 'config_version')) {
        return 0
    }

    $value = $Config.config_version
    $integerTypes = @(
        [sbyte], [byte], [int16], [uint16],
        [int32], [uint32], [int64], [uint64]
    )
    $isInteger = $false
    foreach ($type in $integerTypes) {
        if ($value -is $type) {
            $isInteger = $true
            break
        }
    }
    if (-not $isInteger -or [int64]$value -le 0) {
        throw "Invalid config_version '$value'. config_version must be a positive integer."
    }
    if ([uint64]$value -gt 9999) {
        throw "Invalid config_version '$value'. The maximum supported version identifier is 9999."
    }
    return [int]$value
}

function Test-GitHerdScriptBlockProperty {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string]$Name
    )

    return (Test-GitHerdProperty $Object $Name) -and $Object.$Name -is [scriptblock]
}
