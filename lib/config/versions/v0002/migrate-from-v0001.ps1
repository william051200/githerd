#Requires -Version 5.0

function Convert-GitHerdConfigV0001ToV0002 {
    param([Parameter(Mandatory = $true)] $Config)

    if ((Get-GitHerdConfigVersion $Config) -ne 1) {
        throw 'Migration v0001 to v0002 requires a schema v0001 config.'
    }

    $repos = @()
    foreach ($repo in @($Config.repos)) {
        $devRemote = 'origin'
        if ((Test-GitHerdProperty -Object $repo -Name 'dev_remote') -and
            -not [string]::IsNullOrWhiteSpace([string]$repo.dev_remote)) {
            $devRemote = [string]$repo.dev_remote
        }

        $repos += [pscustomobject][ordered]@{
            name          = $repo.name
            path          = $repo.path
            dev_remote    = $devRemote
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

function script:Get-GitHerdConfigMigrationV0001ToV0002 {
    if (-not (Get-Variable -Name GitHerdConfigMigrationV0001ToV0002Instance -Scope Script -ErrorAction SilentlyContinue) -or
        $null -eq $script:GitHerdConfigMigrationV0001ToV0002Instance) {
        $script:GitHerdConfigMigrationV0001ToV0002Instance = [pscustomobject]@{
            PSTypeName    = 'GitHerd.Config.MigrationHandler'
            SourceVersion = 1
            TargetVersion = 2
            Next          = $null
            Migrate       = ${function:Convert-GitHerdConfigV0001ToV0002}
        }
    }
    return $script:GitHerdConfigMigrationV0001ToV0002Instance
}
