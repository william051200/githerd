#Requires -Version 5.0

function Test-GitHerdJsonScalar {
    param($Value)

    return $null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]
}

function ConvertTo-GitHerdJsonScalar {
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [string]) {
        return ($Value | ConvertTo-Json -Compress)
    }
    return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
}

function Get-GitHerdObjectProperties {
    param([Parameter(Mandatory = $true)] $Value)

    if ($Value -is [System.Collections.IDictionary]) {
        return @($Value.Keys | ForEach-Object {
            [pscustomobject]@{ Name = [string]$_; Value = $Value[$_] }
        })
    }
    return @($Value.PSObject.Properties | Where-Object {
        $_.MemberType -in @('NoteProperty', 'Property')
    })
}

function ConvertTo-GitHerdJsonLines {
    param(
        [AllowNull()] $Value,
        [int]$Indent = 0
    )

    $padding = ' ' * $Indent
    if (Test-GitHerdJsonScalar $Value) {
        return @($padding + (ConvertTo-GitHerdJsonScalar $Value))
    }

    if ($Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [System.Collections.IDictionary]) {
        $items = @($Value)
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add($padding + '[')
        for ($i = 0; $i -lt $items.Count; $i++) {
            $itemLines = @(ConvertTo-GitHerdJsonLines -Value $items[$i] -Indent ($Indent + 2))
            if ($i -lt ($items.Count - 1)) {
                $itemLines[$itemLines.Count - 1] += ','
            }
            foreach ($line in $itemLines) { $lines.Add($line) }
        }
        $lines.Add($padding + ']')
        return @($lines)
    }

    $properties = @(Get-GitHerdObjectProperties $Value)
    $objectLines = New-Object System.Collections.Generic.List[string]
    $objectLines.Add($padding + '{')
    for ($i = 0; $i -lt $properties.Count; $i++) {
        $property = $properties[$i]
        $name = ConvertTo-GitHerdJsonScalar ([string]$property.Name)
        if (Test-GitHerdJsonScalar $property.Value) {
            $propertyLines = @(
                (' ' * ($Indent + 2)) + $name + ': ' +
                (ConvertTo-GitHerdJsonScalar $property.Value)
            )
        } else {
            $childLines = @(ConvertTo-GitHerdJsonLines -Value $property.Value -Indent ($Indent + 2))
            $propertyLines = @(
                (' ' * ($Indent + 2)) + $name + ': ' +
                $childLines[0].Substring($Indent + 2)
            )
            if ($childLines.Count -gt 1) {
                $propertyLines += $childLines[1..($childLines.Count - 1)]
            }
        }
        if ($i -lt ($properties.Count - 1)) {
            $propertyLines[$propertyLines.Count - 1] += ','
        }
        foreach ($line in $propertyLines) { $objectLines.Add($line) }
    }
    $objectLines.Add($padding + '}')
    return @($objectLines)
}

function ConvertTo-CanonicalGitHerdJson {
    param([Parameter(Mandatory = $true)] $OrderedConfig)

    return (@(ConvertTo-GitHerdJsonLines -Value $OrderedConfig) -join "`n") + "`n"
}
