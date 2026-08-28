#Requires -Version 5.1

Describe 'Repository sanity' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    }

    It 'resolves the repo root from the tests folder' {
        $script:RepoRoot | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:RepoRoot | Should -BeTrue
    }

    It 'contains the expected top-level entry points' {
        foreach ($entry in @('sync.bat', 'githerd.cmd', 'VERSION', 'lib', 'ui')) {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot $entry) | Should -BeTrue -Because "expected $entry at repo root"
        }
    }

    It 'has a non-empty VERSION file' {
        $v = (Get-Content -LiteralPath (Join-Path $script:RepoRoot 'VERSION') -Raw).Trim()
        $v | Should -Not -BeNullOrEmpty
        $v | Should -Match '^\d+\.\d+\.\d+'
    }

    It 'wires separate master-remote and auto-merge controls' {
        $xaml = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'ui\MainWindow.xaml') -Raw
        $ui = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'ui\config-ui.ps1') -Raw
        $theme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'ui\Theme.xaml') -Raw

        $xaml | Should -Match 'x:Name="CmbMasterRemote"'
        $xaml | Should -Match 'x:Name="ChkAutoMerge"'
        $ui | Should -Match 'function Get-RepoRemotes'
        $ui | Should -Match '@\(Get-RepoRemotes'
        $ui | Should -Match 'master_remote'
        $theme | Should -Match 'x:Key="ComboBoxStyle"'
        $theme | Should -Match 'x:Key="ThinScrollViewer"'
    }
}
