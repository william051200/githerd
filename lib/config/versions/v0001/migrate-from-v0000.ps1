#Requires -Version 5.0

function Convert-GitHerdConfigV0000ToV0001 {
    param([Parameter(Mandatory = $true)] $Config)

    if (Test-GitHerdProperty -Object $Config -Name 'config_version') {
        throw 'Migration v0000 to v0001 requires an unversioned config.'
    }

    $repos = @()
    if (Test-GitHerdProperty -Object $Config -Name 'repos') {
        foreach ($repo in @($Config.repos)) {
            if ($null -eq $repo) { continue }

            $autoMerge = $false
            if (Test-GitHerdProperty -Object $repo -Name 'auto_merge') {
                $autoMerge = $repo.auto_merge
            }

            $masterRemote = ''
            if ((Test-GitHerdProperty -Object $repo -Name 'master_remote') -and
                -not [string]::IsNullOrWhiteSpace([string]$repo.master_remote)) {
                $masterRemote = [string]$repo.master_remote
            } elseif (-not [bool]$autoMerge -and
                      (Test-GitHerdProperty -Object $repo -Name 'pull_remote') -and
                      -not [string]::IsNullOrWhiteSpace([string]$repo.pull_remote)) {
                $masterRemote = [string]$repo.pull_remote
            } elseif ([bool]$autoMerge) {
                $masterRemote = 'upstream'
            } else {
                $masterRemote = 'origin'
            }

            $repos += [pscustomobject][ordered]@{
                name          = if (Test-GitHerdProperty $repo 'name') { $repo.name } else { $null }
                path          = if (Test-GitHerdProperty $repo 'path') { $repo.path } else { $null }
                master_remote = $masterRemote
                master        = if (Test-GitHerdProperty $repo 'master') { $repo.master } else { $null }
                auto_merge    = $autoMerge
            }
        }
    }

    [pscustomobject][ordered]@{
        config_version   = 1
        working_dir      = if (Test-GitHerdProperty $Config 'working_dir') { $Config.working_dir } else { '' }
        repos            = $repos
        final_command    = if (Test-GitHerdProperty $Config 'final_command') { $Config.final_command } else { '' }
        max_wait_seconds = if (Test-GitHerdProperty $Config 'max_wait_seconds') { $Config.max_wait_seconds } else { 600 }
    }
}

function script:Get-GitHerdConfigMigrationV0000ToV0001 {
    if (-not (Get-Variable -Name GitHerdConfigMigrationV0000ToV0001Instance -Scope Script -ErrorAction SilentlyContinue) -or
        $null -eq $script:GitHerdConfigMigrationV0000ToV0001Instance) {
        $script:GitHerdConfigMigrationV0000ToV0001Instance = [pscustomobject]@{
            PSTypeName    = 'GitHerd.Config.MigrationHandler'
            SourceVersion = 0
            TargetVersion = 1
            Next          = $null
            Migrate       = ${function:Convert-GitHerdConfigV0000ToV0001}
        }
    }
    return $script:GitHerdConfigMigrationV0000ToV0001Instance
}
