#Requires -Version 5.0
<#
.SYNOPSIS
    WPF editor for githerd's config.json.

.DESCRIPTION
    List+detail editor for the repo collection, post-sync command, and
    worker timeout. Layout in MainWindow.xaml; styling in Theme.xaml.

    Exit codes (preserved contract used by sync.bat):
      0  - Saved and closed
      10 - Saved with "Save & Run" (caller should launch the sync)
      2  - User cancelled
      1  - Error
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms   # FolderBrowserDialog only

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- Config IO --------------------------------------------------------------

function New-DefaultConfig {
    [pscustomobject]@{
        repos            = @()
        final_command    = ''
        max_wait_seconds = 600
    }
}

function Load-Config {
    param([string]$Path)
    $source = $Path
    if (-not (Test-Path -LiteralPath $source)) {
        $example = Join-Path (Split-Path -Parent $source) 'config.example.json'
        if (Test-Path -LiteralPath $example) { $source = $example }
        else { return New-DefaultConfig }
    }
    try {
        $raw = Get-Content -LiteralPath $source -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return New-DefaultConfig }
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        [System.Windows.MessageBox]::Show(
            "Failed to read $Path`n$($_.Exception.Message)`n`nStarting with empty config.",
            'Config load error', 'OK', 'Warning') | Out-Null
        return New-DefaultConfig
    }
}

function Save-Config {
    param([string]$Path, $Config)
    $json = $Config | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

# ---- Repo VM (so list bindings update on edit) ------------------------------
# Use a DependencyObject so the ListBox DataTemplate refreshes when the
# user edits the name/path in the right-hand pane.

if (-not ('GitherdRepoVM' -as [type])) {
    Add-Type -ReferencedAssemblies PresentationFramework, PresentationCore, WindowsBase -TypeDefinition @'
using System.Windows;
public class GitherdRepoVM : DependencyObject {
    public static readonly DependencyProperty NameProperty =
        DependencyProperty.Register("name", typeof(string), typeof(GitherdRepoVM));
    public static readonly DependencyProperty PathProperty =
        DependencyProperty.Register("path", typeof(string), typeof(GitherdRepoVM));
    public static readonly DependencyProperty MasterProperty =
        DependencyProperty.Register("master", typeof(string), typeof(GitherdRepoVM));
    public static readonly DependencyProperty AutoMergeProperty =
        DependencyProperty.Register("auto_merge", typeof(bool), typeof(GitherdRepoVM));

    public string name       { get { return (string)GetValue(NameProperty); }   set { SetValue(NameProperty, value); } }
    public string path       { get { return (string)GetValue(PathProperty); }   set { SetValue(PathProperty, value); } }
    public string master     { get { return (string)GetValue(MasterProperty); } set { SetValue(MasterProperty, value); } }
    public bool   auto_merge { get { return (bool)GetValue(AutoMergeProperty); } set { SetValue(AutoMergeProperty, value); } }
}
'@
}

function New-RepoVM {
    param($Source)
    $vm = New-Object GitherdRepoVM
    $vm.name       = if ($Source -and $Source.name)   { [string]$Source.name }   else { '' }
    $vm.path       = if ($Source -and $Source.path)   { [string]$Source.path }   else { '' }
    $vm.master     = if ($Source -and $Source.master) { [string]$Source.master } else { 'main' }
    $auto = $true
    if ($Source -and $Source.PSObject.Properties.Match('auto_merge').Count -gt 0) {
        $auto = [bool]$Source.auto_merge
    }
    $vm.auto_merge = $auto
    return $vm
}

# ---- Load XAML --------------------------------------------------------------

function Load-Xaml {
    param([string]$Path)
    $xml = [xml](Get-Content -LiteralPath $Path -Raw)
    $reader = New-Object System.Xml.XmlNodeReader $xml
    return [Windows.Markup.XamlReader]::Load($reader)
}

$theme  = Load-Xaml (Join-Path $ScriptDir 'Theme.xaml')
$window = Load-Xaml (Join-Path $ScriptDir 'MainWindow.xaml')
$window.Resources.MergedDictionaries.Add($theme)

# ---- Resolve named controls -------------------------------------------------
$ctl = @{}
foreach ($n in 'ErrorBox','ErrorText','RepoList','RepoCount','BtnAdd','BtnRemove',
                'BtnImport','BtnExport',
                'DetailPanel','EmptyState','TxtName','TxtPath','BtnBrowse','TxtMaster',
                'ChkAutoMerge','TxtFinal','TxtTimeout','BtnCancel','BtnSave','BtnSaveRun') {
    $ctl[$n] = $window.FindName($n)
}

# ---- Bindings & state -------------------------------------------------------
$reposVm = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$ctl.RepoList.ItemsSource = $reposVm

$script:current = $null   # currently bound repo VM
$script:suppressDetailWrite = $false

function Set-StateFromConfig {
    param($Config)
    $script:suppressDetailWrite = $true
    $reposVm.Clear()
    foreach ($r in @($Config.repos)) {
        if ($null -eq $r) { continue }
        $reposVm.Add((New-RepoVM -Source $r))
    }
    $ctl.TxtFinal.Text = [string]$Config.final_command
    $timeoutInit = 600
    try { if ($null -ne $Config.max_wait_seconds) { $timeoutInit = [int]$Config.max_wait_seconds } } catch {}
    if ($timeoutInit -lt 10)    { $timeoutInit = 10 }
    if ($timeoutInit -gt 86400) { $timeoutInit = 86400 }
    $ctl.TxtTimeout.Text = [string]$timeoutInit
    $script:suppressDetailWrite = $false
}

$config = Load-Config -Path $ConfigPath
Set-StateFromConfig -Config $config

function Update-Count {
    $ctl.RepoCount.Text = "$($reposVm.Count) configured"
}

function Show-Error {
    param([string]$Message)
    if ([string]::IsNullOrEmpty($Message)) {
        $ctl.ErrorBox.Visibility = 'Collapsed'
        $ctl.ErrorText.Text = ''
    } else {
        $ctl.ErrorBox.Style  = $window.FindResource('ErrorBanner')
        $ctl.ErrorText.Style = $window.FindResource('ErrorBannerText')
        $ctl.ErrorText.Text = $Message
        $ctl.ErrorBox.Visibility = 'Visible'
    }
}

function Show-Info {
    param([string]$Message)
    if ([string]::IsNullOrEmpty($Message)) {
        $ctl.ErrorBox.Visibility = 'Collapsed'
        $ctl.ErrorText.Text = ''
        return
    }
    $ctl.ErrorBox.Style  = $window.FindResource('SuccessBanner')
    $ctl.ErrorText.Style = $window.FindResource('SuccessBannerText')
    $ctl.ErrorText.Text = $Message
    $ctl.ErrorBox.Visibility = 'Visible'
}

function Bind-Detail {
    param($Vm)
    $script:suppressDetailWrite = $true
    if ($null -eq $Vm) {
        $ctl.DetailPanel.Visibility = 'Collapsed'
        $ctl.EmptyState.Visibility  = 'Visible'
        $ctl.TxtName.Text = ''; $ctl.TxtPath.Text = ''; $ctl.TxtMaster.Text = ''
        $ctl.ChkAutoMerge.IsChecked = $false
    } else {
        $ctl.DetailPanel.Visibility = 'Visible'
        $ctl.EmptyState.Visibility  = 'Collapsed'
        $ctl.TxtName.Text   = [string]$Vm.name
        $ctl.TxtPath.Text   = [string]$Vm.path
        $ctl.TxtMaster.Text = [string]$Vm.master
        $ctl.ChkAutoMerge.IsChecked = [bool]$Vm.auto_merge
    }
    $script:current = $Vm
    $script:suppressDetailWrite = $false
}

function Push-Detail-To-Vm {
    if ($script:suppressDetailWrite -or $null -eq $script:current) { return }
    $script:current.name       = $ctl.TxtName.Text
    $script:current.path       = $ctl.TxtPath.Text
    $script:current.master     = $ctl.TxtMaster.Text
    $script:current.auto_merge = [bool]$ctl.ChkAutoMerge.IsChecked
}

# ---- Wire events ------------------------------------------------------------
$ctl.RepoList.Add_SelectionChanged({
    Bind-Detail -Vm $ctl.RepoList.SelectedItem
})

$ctl.TxtName.Add_TextChanged({   Push-Detail-To-Vm })
$ctl.TxtPath.Add_TextChanged({   Push-Detail-To-Vm })
$ctl.TxtMaster.Add_TextChanged({ Push-Detail-To-Vm })
$ctl.ChkAutoMerge.Add_Click({    Push-Detail-To-Vm })

$ctl.BtnAdd.Add_Click({
    $vm = New-RepoVM -Source $null
    $reposVm.Add($vm)
    Update-Count
    $ctl.RepoList.SelectedItem = $vm
    $ctl.RepoList.ScrollIntoView($vm)
    $ctl.TxtName.Focus() | Out-Null
    $ctl.TxtName.SelectAll()
})

$ctl.BtnRemove.Add_Click({
    $sel = $ctl.RepoList.SelectedItem
    if ($null -eq $sel) { return }
    $idx = $reposVm.IndexOf($sel)
    [void]$reposVm.Remove($sel)
    Update-Count
    if ($reposVm.Count -gt 0) {
        if ($idx -ge $reposVm.Count) { $idx = $reposVm.Count - 1 }
        $ctl.RepoList.SelectedIndex = $idx
    } else {
        Bind-Detail -Vm $null
    }
})

$ctl.BtnBrowse.Add_Click({
    if ($null -eq $script:current) { return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select repository folder'
    if ($script:current.path -and (Test-Path -LiteralPath $script:current.path)) {
        $dlg.SelectedPath = (Resolve-Path -LiteralPath $script:current.path).Path
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $ctl.TxtPath.Text = $dlg.SelectedPath
    }
})

# ---- Import / Export -------------------------------------------------------

function Get-DefaultShareDir {
    try {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        if ($docs -and (Test-Path -LiteralPath $docs)) { return $docs }
    } catch {}
    return [Environment]::GetFolderPath('UserProfile')
}

$ctl.BtnExport.Add_Click({
    try {
        Push-Detail-To-Vm
        $cfg = Validate-And-Build
    } catch {
        Show-Error $_.Exception.Message
        return
    }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title       = 'Export GitHerd config'
    $dlg.Filter      = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $dlg.FileName    = 'githerd-config.json'
    $dlg.DefaultExt  = '.json'
    $dlg.InitialDirectory = (Get-DefaultShareDir)
    $dlg.OverwritePrompt  = $true
    if ($dlg.ShowDialog($window) -ne $true) { return }
    try {
        Save-Config -Path $dlg.FileName -Config $cfg
        Show-Info ("Exported to {0}" -f $dlg.FileName)
    } catch {
        Show-Error ("Export failed: " + $_.Exception.Message)
    }
})

$ctl.BtnImport.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title       = 'Import GitHerd config'
    $dlg.Filter      = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $dlg.InitialDirectory = (Get-DefaultShareDir)
    $dlg.CheckFileExists = $true
    if ($dlg.ShowDialog($window) -ne $true) { return }

    $imported = $null
    try {
        $raw = Get-Content -LiteralPath $dlg.FileName -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'File is empty.' }
        $imported = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Show-Error ("Import failed: " + $_.Exception.Message)
        return
    }
    if ($null -eq $imported -or
        $imported.PSObject.Properties.Match('repos').Count -eq 0) {
        Show-Error "Selected file is not a GitHerd config (missing 'repos' array)."
        return
    }

    if ($reposVm.Count -gt 0) {
        $resp = [System.Windows.MessageBox]::Show(
            ("Replace your current config with the contents of`n{0}?" -f $dlg.FileName),
            'Import config', 'YesNo', 'Question')
        if ($resp -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    Set-StateFromConfig -Config $imported
    Update-Count
    if ($reposVm.Count -gt 0) {
        $ctl.RepoList.SelectedIndex = 0
    } else {
        Bind-Detail -Vm $null
    }

    # Non-blocking warning for paths that don't exist on this machine.
    $missing = @()
    foreach ($vm in $reposVm) {
        $p = ([string]$vm.path).Trim()
        if ($p -and -not (Test-Path -LiteralPath $p)) {
            $label = ([string]$vm.name).Trim()
            if (-not $label) { $label = $p }
            $missing += $label
        }
    }
    if ($missing.Count -gt 0) {
        $list = ($missing | Select-Object -First 5) -join ', '
        if ($missing.Count -gt 5) { $list += (", +{0} more" -f ($missing.Count - 5)) }
        Show-Info ("Imported. {0} repo path(s) don't exist on this machine - update them before saving: {1}" -f $missing.Count, $list)
    } else {
        Show-Info ("Imported from {0}" -f $dlg.FileName)
    }
})

# ---- Validate + save --------------------------------------------------------
function Validate-And-Build {
    $repos = @()
    $names = @{}
    $i = 0
    foreach ($vm in $reposVm) {
        $i++
        $name   = ([string]$vm.name).Trim()
        $path   = ([string]$vm.path).Trim()
        $master = ([string]$vm.master).Trim()

        if (-not $name -and -not $path -and -not $master) { continue }

        if (-not $name)   { throw "Repo #${i}: Name is required." }
        if (-not $path)   { throw "Repo '$name': Path is required." }
        if (-not $master) { throw "Repo '$name': Master branch is required." }
        if ($name.Contains('"') -or $path.Contains('"') -or $master.Contains('"')) {
            throw "Repo '$name': double-quotes (`") are not allowed in any field."
        }
        $key = $name.ToLowerInvariant()
        if ($names.ContainsKey($key)) { throw "Duplicate repository name: '$name'." }
        $names[$key] = $true

        $repos += [pscustomobject]@{
            name       = $name
            path       = $path
            master     = $master
            auto_merge = [bool]$vm.auto_merge
        }
    }
    if ($repos.Count -eq 0) { throw 'Add at least one repository.' }

    $finalCmd = [string]$ctl.TxtFinal.Text
    if ($finalCmd.Contains('"')) {
        throw 'Final command may not contain double-quotes (").'
    }

    $timeout = 600
    if (-not [int]::TryParse($ctl.TxtTimeout.Text, [ref]$timeout)) {
        throw "Worker timeout must be an integer (got '$($ctl.TxtTimeout.Text)')."
    }
    if ($timeout -lt 10 -or $timeout -gt 86400) {
        throw "Worker timeout must be between 10 and 86400 seconds."
    }

    return [pscustomobject]@{
        repos            = $repos
        final_command    = $finalCmd
        max_wait_seconds = $timeout
    }
}

function Try-Save {
    try {
        Push-Detail-To-Vm
        $cfg = Validate-And-Build
        Save-Config -Path $ConfigPath -Config $cfg
        Show-Error $null
        return $true
    } catch {
        Show-Error $_.Exception.Message
        return $false
    }
}

$script:resultExitCode = 2

$ctl.BtnSave.Add_Click({    if (Try-Save) { $script:resultExitCode = 0;  $window.Close() } })
$ctl.BtnSaveRun.Add_Click({ if (Try-Save) { $script:resultExitCode = 10; $window.Close() } })
$ctl.BtnCancel.Add_Click({  $script:resultExitCode = 2; $window.Close() })

# ---- Initial state ----------------------------------------------------------
Update-Count
if ($reposVm.Count -gt 0) {
    $ctl.RepoList.SelectedIndex = 0
} else {
    Bind-Detail -Vm $null
}

[void]$window.ShowDialog()
exit $script:resultExitCode
