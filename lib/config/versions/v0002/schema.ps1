#Requires -Version 5.0

function New-GitHerdConfigV0002 {
    [pscustomobject][ordered]@{
        config_version   = 2
        working_dir      = ''
        repos            = @()
        final_command    = ''
        max_wait_seconds = 600
    }
}

function New-GitHerdRepoV0002 {
    [pscustomobject][ordered]@{
        name          = ''
        path          = ''
        dev_remote    = 'origin'
        master_remote = 'upstream'
        master        = 'main'
        auto_merge    = $true
    }
}

function Assert-GitHerdConfigShapeV0002 {
    param([Parameter(Mandatory = $true)] $Config)

    if (-not (Test-GitHerdProperty $Config 'repos')) {
        throw "Config schema v0002 field 'repos' is required."
    }
    $repos = @($Config.repos)
    for ($i = 0; $i -lt $repos.Count; $i++) {
        $repo = $repos[$i]
        if ($null -eq $repo) {
            throw "Config schema v0002 project #$($i + 1) is null."
        }
        foreach ($field in @('name', 'path', 'dev_remote', 'master_remote', 'master', 'auto_merge')) {
            if (-not (Test-GitHerdProperty $repo $field) -or $null -eq $repo.$field) {
                throw "Config schema v0002 project #$($i + 1) field '$field' is required."
            }
        }
    }
}

function ConvertTo-NormalizedGitHerdConfigV0002 {
    param([Parameter(Mandatory = $true)] $Config)

    $repos = @()
    foreach ($repo in @($Config.repos)) {
        $repos += [pscustomobject][ordered]@{
            name          = ([string]$repo.name).Trim()
            path          = ([string]$repo.path).Trim()
            dev_remote    = ([string]$repo.dev_remote).Trim()
            master_remote = ([string]$repo.master_remote).Trim()
            master        = ([string]$repo.master).Trim()
            auto_merge    = $repo.auto_merge
        }
    }

    [pscustomobject][ordered]@{
        config_version   = 2
        working_dir      = if (Test-GitHerdProperty $Config 'working_dir') { ([string]$Config.working_dir).Trim() } else { '' }
        repos            = $repos
        final_command    = if (Test-GitHerdProperty $Config 'final_command') { [string]$Config.final_command } else { '' }
        max_wait_seconds = if (Test-GitHerdProperty $Config 'max_wait_seconds') { $Config.max_wait_seconds } else { 600 }
    }
}

function Test-GitHerdConfigV0002 {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [bool]$ForRuntime
    )

    if ((Get-GitHerdConfigVersion $Config) -ne 2) {
        throw 'Config schema v0002 validation received a different version.'
    }

    $repos = @($Config.repos)
    if ($ForRuntime -and $repos.Count -eq 0) {
        throw "Config schema v0002 field 'repos' must contain at least one project for runtime use."
    }

    $names = @{}
    for ($i = 0; $i -lt $repos.Count; $i++) {
        $repo = $repos[$i]
        $name = [string]$repo.name
        $path = [string]$repo.path
        $devRemote = [string]$repo.dev_remote
        $masterRemote = [string]$repo.master_remote
        $master = [string]$repo.master

        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Config schema v0002 project #$($i + 1) field 'name' is required."
        }
        if ($ForRuntime -and [string]::IsNullOrWhiteSpace($path)) {
            throw "Config schema v0002 project '$name' field 'path' is required for runtime use."
        }
        foreach ($remote in @(
            @{ Name = 'dev_remote'; Value = $devRemote },
            @{ Name = 'master_remote'; Value = $masterRemote }
        )) {
            if ([string]::IsNullOrWhiteSpace($remote.Value)) {
                throw "Config schema v0002 project '$name' field '$($remote.Name)' is required."
            }
            if ($remote.Value.StartsWith('-') -or $remote.Value -match '[\s"&|<>^%!()]') {
                throw "Config schema v0002 project '$name' field '$($remote.Name)' contains characters that are unsafe for CMD."
            }
        }
        if ([string]::IsNullOrWhiteSpace($master)) {
            throw "Config schema v0002 project '$name' field 'master' is required."
        }
        if ($repo.auto_merge -isnot [bool]) {
            throw "Config schema v0002 project '$name' field 'auto_merge' must be a boolean."
        }

        foreach ($fieldValue in @(
            @{ Name = 'name'; Value = $name },
            @{ Name = 'path'; Value = $path },
            @{ Name = 'master'; Value = $master }
        )) {
            if ($fieldValue.Value.Contains('"')) {
                throw "Config schema v0002 project '$name' field '$($fieldValue.Name)' must not contain double-quote characters."
            }
        }

        $nameKey = $name.ToLowerInvariant()
        if ($names.ContainsKey($nameKey)) {
            throw "Config schema v0002 project name '$name' is duplicated (names are case-insensitively unique)."
        }
        $names[$nameKey] = $true
    }

    foreach ($fieldValue in @(
        @{ Name = 'working_dir'; Value = [string]$Config.working_dir },
        @{ Name = 'final_command'; Value = [string]$Config.final_command }
    )) {
        if ($fieldValue.Value.Contains('"')) {
            throw "Config schema v0002 field '$($fieldValue.Name)' must not contain double-quote characters."
        }
    }

    $maxWait = $Config.max_wait_seconds
    if ($maxWait -isnot [int32] -and $maxWait -isnot [int64] -and
        $maxWait -isnot [int16] -and $maxWait -isnot [byte]) {
        throw "Config schema v0002 field 'max_wait_seconds' must be an integer."
    }
    if ([int64]$maxWait -lt 10 -or [int64]$maxWait -gt 86400) {
        throw "Config schema v0002 field 'max_wait_seconds' must be between 10 and 86400 seconds."
    }
}

function ConvertTo-CanonicalGitHerdConfigV0002 {
    param([Parameter(Mandatory = $true)] $Config)

    $repos = @()
    foreach ($repo in @($Config.repos)) {
        $repos += [pscustomobject][ordered]@{
            name          = $repo.name
            path          = $repo.path
            dev_remote    = $repo.dev_remote
            master_remote = $repo.master_remote
            master        = $repo.master
            auto_merge    = $repo.auto_merge
        }
    }
    [pscustomobject][ordered]@{
        config_version   = 2
        working_dir      = $Config.working_dir
        repos            = $repos
        final_command    = $Config.final_command
        max_wait_seconds = $Config.max_wait_seconds
    }
}

function New-GitHerdPortableExportV0002 {
    param([Parameter(Mandatory = $true)] $Config)

    $repos = @()
    foreach ($repo in @($Config.repos)) {
        $repos += [pscustomobject][ordered]@{
            name          = $repo.name
            path          = ''
            dev_remote    = $repo.dev_remote
            master_remote = $repo.master_remote
            master        = $repo.master
            auto_merge    = $repo.auto_merge
        }
    }
    [pscustomobject][ordered]@{
        config_version   = 2
        working_dir      = ''
        repos            = $repos
        final_command    = $Config.final_command
        max_wait_seconds = $Config.max_wait_seconds
    }
}

function script:Get-GitHerdConfigSchemaV0002 {
    if (-not (Get-Variable -Name GitHerdConfigSchemaV0002Instance -Scope Script -ErrorAction SilentlyContinue) -or
        $null -eq $script:GitHerdConfigSchemaV0002Instance) {
        $script:GitHerdConfigSchemaV0002Instance = [pscustomobject]@{
            PSTypeName        = 'GitHerd.Config.Schema'
            Version           = 2
            NewConfig         = ${function:New-GitHerdConfigV0002}
            NewRepo           = ${function:New-GitHerdRepoV0002}
            AssertShape       = ${function:Assert-GitHerdConfigShapeV0002}
            Normalize         = ${function:ConvertTo-NormalizedGitHerdConfigV0002}
            Validate          = ${function:Test-GitHerdConfigV0002}
            ToCanonicalObject = ${function:ConvertTo-CanonicalGitHerdConfigV0002}
            NewPortableExport = ${function:New-GitHerdPortableExportV0002}
        }
    }
    return $script:GitHerdConfigSchemaV0002Instance
}
