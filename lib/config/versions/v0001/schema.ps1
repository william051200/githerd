#Requires -Version 5.0

function New-GitHerdConfigV0001 {
    [pscustomobject][ordered]@{
        config_version   = 1
        working_dir      = ''
        repos            = @()
        final_command    = ''
        max_wait_seconds = 600
    }
}

function New-GitHerdRepoV0001 {
    [pscustomobject][ordered]@{
        name          = ''
        path          = ''
        master_remote = 'upstream'
        master        = 'main'
        auto_merge    = $true
    }
}

function Assert-GitHerdConfigShapeV0001 {
    param([Parameter(Mandatory = $true)] $Config)

    if (-not (Test-GitHerdProperty $Config 'repos')) {
        throw "Config schema v0001 field 'repos' is required."
    }
    $repos = @($Config.repos)
    for ($i = 0; $i -lt $repos.Count; $i++) {
        $repo = $repos[$i]
        if ($null -eq $repo) {
            throw "Config schema v0001 project #$($i + 1) is null."
        }
        foreach ($field in @('name', 'path', 'master_remote', 'master', 'auto_merge')) {
            if (-not (Test-GitHerdProperty $repo $field) -or $null -eq $repo.$field) {
                throw "Config schema v0001 project #$($i + 1) field '$field' is required."
            }
        }
    }
}

function ConvertTo-NormalizedGitHerdConfigV0001 {
    param([Parameter(Mandatory = $true)] $Config)

    $repos = @()
    foreach ($repo in @($Config.repos)) {
        $repos += [pscustomobject][ordered]@{
            name          = ([string]$repo.name).Trim()
            path          = ([string]$repo.path).Trim()
            master_remote = ([string]$repo.master_remote).Trim()
            master        = ([string]$repo.master).Trim()
            auto_merge    = $repo.auto_merge
        }
    }

    [pscustomobject][ordered]@{
        config_version   = 1
        working_dir      = if (Test-GitHerdProperty $Config 'working_dir') { ([string]$Config.working_dir).Trim() } else { '' }
        repos            = $repos
        final_command    = if (Test-GitHerdProperty $Config 'final_command') { [string]$Config.final_command } else { '' }
        max_wait_seconds = if (Test-GitHerdProperty $Config 'max_wait_seconds') { $Config.max_wait_seconds } else { 600 }
    }
}

function Test-GitHerdConfigV0001 {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [bool]$ForRuntime
    )

    if ((Get-GitHerdConfigVersion $Config) -ne 1) {
        throw 'Config schema v0001 validation received a different version.'
    }

    $repos = @($Config.repos)
    if ($ForRuntime -and $repos.Count -eq 0) {
        throw "Config schema v0001 field 'repos' must contain at least one project for runtime use."
    }

    $names = @{}
    for ($i = 0; $i -lt $repos.Count; $i++) {
        $repo = $repos[$i]
        $name = [string]$repo.name
        $path = [string]$repo.path
        $masterRemote = [string]$repo.master_remote
        $master = [string]$repo.master

        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Config schema v0001 project #$($i + 1) field 'name' is required."
        }
        if ($ForRuntime -and [string]::IsNullOrWhiteSpace($path)) {
            throw "Config schema v0001 project '$name' field 'path' is required for runtime use."
        }
        if ([string]::IsNullOrWhiteSpace($masterRemote)) {
            throw "Config schema v0001 project '$name' field 'master_remote' is required."
        }
        if ([string]::IsNullOrWhiteSpace($master)) {
            throw "Config schema v0001 project '$name' field 'master' is required."
        }
        if ($repo.auto_merge -isnot [bool]) {
            throw "Config schema v0001 project '$name' field 'auto_merge' must be a boolean."
        }

        foreach ($fieldValue in @(
            @{ Name = 'name'; Value = $name },
            @{ Name = 'path'; Value = $path },
            @{ Name = 'master'; Value = $master }
        )) {
            if ($fieldValue.Value.Contains('"')) {
                throw "Config schema v0001 project '$name' field '$($fieldValue.Name)' must not contain double-quote characters."
            }
        }
        if ($masterRemote.StartsWith('-') -or $masterRemote -match '[\s"&|<>^%!()]') {
            throw "Config schema v0001 project '$name' field 'master_remote' contains characters that are unsafe for CMD."
        }

        $nameKey = $name.ToLowerInvariant()
        if ($names.ContainsKey($nameKey)) {
            throw "Config schema v0001 project name '$name' is duplicated (names are case-insensitively unique)."
        }
        $names[$nameKey] = $true
    }

    foreach ($fieldValue in @(
        @{ Name = 'working_dir'; Value = [string]$Config.working_dir },
        @{ Name = 'final_command'; Value = [string]$Config.final_command }
    )) {
        if ($fieldValue.Value.Contains('"')) {
            throw "Config schema v0001 field '$($fieldValue.Name)' must not contain double-quote characters."
        }
    }

    $maxWait = $Config.max_wait_seconds
    if ($maxWait -isnot [int32] -and $maxWait -isnot [int64] -and
        $maxWait -isnot [int16] -and $maxWait -isnot [byte]) {
        throw "Config schema v0001 field 'max_wait_seconds' must be an integer."
    }
    if ([int64]$maxWait -lt 10 -or [int64]$maxWait -gt 86400) {
        throw "Config schema v0001 field 'max_wait_seconds' must be between 10 and 86400 seconds."
    }
}

function ConvertTo-CanonicalGitHerdConfigV0001 {
    param([Parameter(Mandatory = $true)] $Config)

    $repos = @()
    foreach ($repo in @($Config.repos)) {
        $repos += [pscustomobject][ordered]@{
            name          = $repo.name
            path          = $repo.path
            master_remote = $repo.master_remote
            master        = $repo.master
            auto_merge    = $repo.auto_merge
        }
    }
    [pscustomobject][ordered]@{
        config_version   = 1
        working_dir      = $Config.working_dir
        repos            = $repos
        final_command    = $Config.final_command
        max_wait_seconds = $Config.max_wait_seconds
    }
}

function New-GitHerdPortableExportV0001 {
    param([Parameter(Mandatory = $true)] $Config)

    $repos = @()
    foreach ($repo in @($Config.repos)) {
        $repos += [pscustomobject][ordered]@{
            name          = $repo.name
            path          = ''
            master_remote = $repo.master_remote
            master        = $repo.master
            auto_merge    = $repo.auto_merge
        }
    }
    [pscustomobject][ordered]@{
        config_version   = 1
        working_dir      = ''
        repos            = $repos
        final_command    = $Config.final_command
        max_wait_seconds = $Config.max_wait_seconds
    }
}

function script:Get-GitHerdConfigSchemaV0001 {
    if (-not (Get-Variable -Name GitHerdConfigSchemaV0001Instance -Scope Script -ErrorAction SilentlyContinue) -or
        $null -eq $script:GitHerdConfigSchemaV0001Instance) {
        $script:GitHerdConfigSchemaV0001Instance = [pscustomobject]@{
            PSTypeName        = 'GitHerd.Config.Schema'
            Version           = 1
            NewConfig         = ${function:New-GitHerdConfigV0001}
            NewRepo           = ${function:New-GitHerdRepoV0001}
            AssertShape       = ${function:Assert-GitHerdConfigShapeV0001}
            Normalize         = ${function:ConvertTo-NormalizedGitHerdConfigV0001}
            Validate          = ${function:Test-GitHerdConfigV0001}
            ToCanonicalObject = ${function:ConvertTo-CanonicalGitHerdConfigV0001}
            NewPortableExport = ${function:New-GitHerdPortableExportV0001}
        }
    }
    return $script:GitHerdConfigSchemaV0001Instance
}
