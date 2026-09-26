#Requires -Version 5.0

$configCore = Join-Path $PSScriptRoot 'config\core'

. (Join-Path $configCore 'common.ps1')
. (Join-Path $configCore 'json.ps1')
. (Join-Path $configCore 'file-store.ps1')
. (Join-Path $configCore 'migration-chain.ps1')
. (Join-Path $configCore 'version-loader.ps1')
. (Join-Path $configCore 'engine.ps1')

Initialize-GitHerdConfigArchitecture -VersionsPath (Join-Path $PSScriptRoot 'config\versions')
