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
      20 - User clicked "Update now" (caller should run lib\update.ps1 then re-launch the UI)
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
Add-Type -AssemblyName System.Windows.Forms   # legacy fallback only

# ---- Modern (Vista) folder picker via IFileOpenDialog ----------------------
# .NET Framework 4.x's FolderBrowserDialog is the small, non-resizable legacy
# dialog. The Vista-style IFileOpenDialog with FOS_PICKFOLDERS is resizable
# and uses the modern Explorer UI. We register a tiny COM-interop wrapper once
# per session and fall back to FolderBrowserDialog if interop fails.
if (-not ('Githerd.FolderPicker' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Githerd {
    public static class FolderPicker {
        const uint FOS_PICKFOLDERS    = 0x00000020;
        const uint FOS_FORCEFILESYSTEM = 0x00000040;
        const uint FOS_PATHMUSTEXIST  = 0x00000800;
        const uint SIGDN_FILESYSPATH  = 0x80058000;

        public static string Pick(IntPtr owner, string title, string initialDir) {
            IFileOpenDialog dialog = null;
            try {
                dialog = (IFileOpenDialog)new FileOpenDialog();
                uint opts;
                dialog.GetOptions(out opts);
                dialog.SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
                if (!string.IsNullOrEmpty(title)) dialog.SetTitle(title);
                if (!string.IsNullOrEmpty(initialDir)) {
                    IShellItem item;
                    Guid iidShellItem = typeof(IShellItem).GUID;
                    int hr = SHCreateItemFromParsingName(initialDir, IntPtr.Zero, ref iidShellItem, out item);
                    if (hr == 0 && item != null) {
                        try { dialog.SetFolder(item); }
                        finally { Marshal.ReleaseComObject(item); }
                    }
                }
                int showHr = dialog.Show(owner);
                if (showHr != 0) return null; // cancelled or failed
                IShellItem result;
                dialog.GetResult(out result);
                try {
                    string path;
                    result.GetDisplayName(SIGDN_FILESYSPATH, out path);
                    return path;
                } finally {
                    Marshal.ReleaseComObject(result);
                }
            } finally {
                if (dialog != null) Marshal.ReleaseComObject(dialog);
            }
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHCreateItemFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
            IntPtr pbc,
            [In] ref Guid riid,
            out IShellItem ppv);

        [ComImport, ClassInterface(ClassInterfaceType.None), Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
        class FileOpenDialog { }

        [ComImport, Guid("d57c7288-d4ad-4768-be02-9d969532d960"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IFileOpenDialog {
            // IModalWindow
            [PreserveSig] int Show(IntPtr parent);
            // IFileDialog
            void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
            void SetFileTypeIndex(uint iFileType);
            void GetFileTypeIndex(out uint piFileType);
            void Advise(IntPtr pfde, out uint pdwCookie);
            void Unadvise(uint dwCookie);
            void SetOptions(uint fos);
            void GetOptions(out uint fos);
            void SetDefaultFolder(IShellItem psi);
            void SetFolder(IShellItem psi);
            void GetFolder(out IShellItem ppsi);
            void GetCurrentSelection(out IShellItem ppsi);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
            void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
            void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
            void GetResult(out IShellItem ppsi);
            void AddPlace(IShellItem psi, uint fdap);
            void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
            void Close([MarshalAs(UnmanagedType.Error)] int hr);
            void SetClientGuid([In] ref Guid guid);
            void ClearClientData();
            void SetFilter(IntPtr pFilter);
            // IFileOpenDialog
            void GetResults(out IntPtr ppenum);
            void GetSelectedItems(out IntPtr ppsai);
        }

        [ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItem {
            void BindToHandler(IntPtr pbc, [In] ref Guid bhid, [In] ref Guid riid, out IntPtr ppv);
            void GetParent(out IShellItem ppsi);
            void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
            void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
            void Compare(IShellItem psi, uint hint, out int piOrder);
        }
    }
}
'@
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- Config IO --------------------------------------------------------------

function New-DefaultConfig {
    [pscustomobject]@{
        working_dir      = ''
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
    public static readonly DependencyProperty MasterRemoteProperty =
        DependencyProperty.Register("master_remote", typeof(string), typeof(GitherdRepoVM));

    public string name       { get { return (string)GetValue(NameProperty); }   set { SetValue(NameProperty, value); } }
    public string path       { get { return (string)GetValue(PathProperty); }   set { SetValue(PathProperty, value); } }
    public string master     { get { return (string)GetValue(MasterProperty); } set { SetValue(MasterProperty, value); } }
    public bool   auto_merge { get { return (bool)GetValue(AutoMergeProperty); } set { SetValue(AutoMergeProperty, value); } }
    public string master_remote { get { return (string)GetValue(MasterRemoteProperty); } set { SetValue(MasterRemoteProperty, value); } }
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
    $masterRemote = if ($auto) { 'upstream' } else { 'origin' }
    if ($Source -and $Source.PSObject.Properties.Match('master_remote').Count -gt 0 -and
        -not [string]::IsNullOrWhiteSpace([string]$Source.master_remote)) {
        $masterRemote = [string]$Source.master_remote
    } elseif (-not $auto -and $Source -and
              $Source.PSObject.Properties.Match('pull_remote').Count -gt 0 -and
              -not [string]::IsNullOrWhiteSpace([string]$Source.pull_remote)) {
        $masterRemote = [string]$Source.pull_remote
    }
    $vm.master_remote = $masterRemote
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
foreach ($n in 'ErrorBox','ErrorText','BtnDismissBanner','RepoList','RepoCount','BtnAdd','BtnRemove',
                'BtnImport','BtnExport','BtnHelp','LblVersion',
                'MenuReportBug','MenuSuggest','MenuCheckUpdates','MenuOpenReadme',
                'UpdateBanner','UpdateBannerText','BtnWhatsNew','BtnUpdateNow','BtnDismissUpdate',
                'TxtWorkingDir','BtnBrowseWorkingDir',
                'DetailPanel','EmptyState','TxtName','TxtPath','BtnBrowse','TxtMaster',
                'CmbMasterRemote','ChkAutoMerge','TxtFinal','TxtTimeout','BtnCancel','BtnSave','BtnSaveRun') {
    $ctl[$n] = $window.FindName($n)
}

# ---- Version badge ----------------------------------------------------------
$versionFile = Join-Path $PSScriptRoot '..\VERSION'
$ghVersion   = ''
if (Test-Path -LiteralPath $versionFile) {
    try { $ghVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim() } catch { }
}
if ($ghVersion) {
    $ctl.LblVersion.Text = "v$ghVersion"
    $window.Title        = "GitHerd v$ghVersion - Configuration"
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
    $workingDir = ''
    if ($Config -and $Config.PSObject.Properties.Match('working_dir').Count -gt 0 -and $null -ne $Config.working_dir) {
        $workingDir = [string]$Config.working_dir
    }
    $ctl.TxtWorkingDir.Text = $workingDir
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

$ctl.BtnDismissBanner.Add_Click({ Show-Error $null })

function Bind-Detail {
    param($Vm)
    $script:suppressDetailWrite = $true
    if ($null -eq $Vm) {
        $ctl.DetailPanel.Visibility = 'Collapsed'
        $ctl.EmptyState.Visibility  = 'Visible'
        $ctl.TxtName.Text = ''; $ctl.TxtPath.Text = ''; $ctl.TxtMaster.Text = ''
        $ctl.CmbMasterRemote.Items.Clear()
        $ctl.CmbMasterRemote.IsEnabled = $false
        $ctl.ChkAutoMerge.IsChecked = $false
        $ctl.ChkAutoMerge.IsEnabled = $false
    } else {
        $ctl.DetailPanel.Visibility = 'Visible'
        $ctl.EmptyState.Visibility  = 'Collapsed'
        $ctl.TxtName.Text   = [string]$Vm.name
        $ctl.TxtPath.Text   = [string]$Vm.path
        $ctl.TxtMaster.Text = [string]$Vm.master
        $ctl.CmbMasterRemote.IsEnabled = $true
        $ctl.ChkAutoMerge.IsEnabled = $true
        $ctl.ChkAutoMerge.IsChecked = [bool]$Vm.auto_merge
    }
    $script:current = $Vm
    $script:suppressDetailWrite = $false
    if ($null -ne $Vm) { Refresh-MasterRemoteOptions }
}

function Push-Detail-To-Vm {
    if ($script:suppressDetailWrite -or $null -eq $script:current) { return }
    $script:current.name       = $ctl.TxtName.Text
    $script:current.path       = $ctl.TxtPath.Text
    $script:current.master     = $ctl.TxtMaster.Text
    $selection = [string]$ctl.CmbMasterRemote.SelectedItem
    if ($selection) { $script:current.master_remote = $selection }
    $script:current.auto_merge = [bool]$ctl.ChkAutoMerge.IsChecked
}

# ---- Wire events ------------------------------------------------------------
$ctl.RepoList.Add_SelectionChanged({
    Bind-Detail -Vm $ctl.RepoList.SelectedItem
})

$ctl.TxtName.Add_TextChanged({   Push-Detail-To-Vm })
$ctl.TxtPath.Add_TextChanged({
    Push-Detail-To-Vm
    Refresh-MasterRemoteOptions
})
$ctl.TxtMaster.Add_TextChanged({ Push-Detail-To-Vm })
$ctl.CmbMasterRemote.Add_SelectionChanged({ Push-Detail-To-Vm })
$ctl.ChkAutoMerge.Add_Click({ Push-Detail-To-Vm })

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

function Get-WorkingDir {
    $wd = ([string]$ctl.TxtWorkingDir.Text).Trim()
    return $wd
}

function Show-FolderPicker {
    param(
        [string]$Title,
        [string]$InitialDir
    )
    $hwnd = [IntPtr]::Zero
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        $hwnd = $helper.Handle
    } catch {}

    $init = ''
    if ($InitialDir) {
        try {
            if (Test-Path -LiteralPath $InitialDir) {
                $init = (Resolve-Path -LiteralPath $InitialDir).Path
            }
        } catch {}
    }

    try {
        return [Githerd.FolderPicker]::Pick($hwnd, $Title, $init)
    } catch {
        # Fallback to the legacy dialog if the Vista picker fails for any reason.
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($Title) { $dlg.Description = $Title }
        if ($init)  { $dlg.SelectedPath = $init }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dlg.SelectedPath
        }
        return $null
    }
}

function Resolve-RepoPath {
    # Returns an absolute path for the given (possibly relative) repo path,
    # joining with the configured working directory if needed.
    param([string]$RepoPath)
    if ([string]::IsNullOrWhiteSpace($RepoPath)) { return '' }
    if ([System.IO.Path]::IsPathRooted($RepoPath)) { return $RepoPath }
    $wd = Get-WorkingDir
    if (-not $wd) { return $RepoPath }
    return (Join-Path $wd $RepoPath)
}

function Get-RepoRemotes {
    param([string]$RepoPath)
    $resolved = Resolve-RepoPath $RepoPath
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        return @()
    }

    try {
        $output = @(& git -C $resolved remote 2>$null)
        if ($LASTEXITCODE -ne 0) { return @() }
        return @($output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    } catch {
        return @()
    }
}

function Refresh-MasterRemoteOptions {
    if ($script:suppressDetailWrite -or $null -eq $script:current) { return }

    $selected = [string]$script:current.master_remote
    if ([string]::IsNullOrWhiteSpace($selected)) { $selected = 'origin' }

    $options = New-Object System.Collections.Generic.List[string]
    foreach ($remote in @((@(Get-RepoRemotes ([string]$script:current.path))) + @($selected, 'origin'))) {
        if ($remote -and -not $options.Contains([string]$remote)) {
            $options.Add([string]$remote)
        }
    }

    $script:suppressDetailWrite = $true
    try {
        $ctl.CmbMasterRemote.Items.Clear()
        foreach ($option in $options) { [void]$ctl.CmbMasterRemote.Items.Add($option) }
        $ctl.CmbMasterRemote.SelectedItem = $selected
    } finally {
        $script:suppressDetailWrite = $false
    }
}

$ctl.TxtWorkingDir.Add_TextChanged({ Refresh-MasterRemoteOptions })

function Try-Relativize-Under-WorkingDir {
    # If $Selected lives under the working dir, return the path relative to it
    # (no leading ".\"); otherwise return $Selected unchanged.
    param([string]$Selected)
    if ([string]::IsNullOrWhiteSpace($Selected)) { return $Selected }
    $wd = Get-WorkingDir
    if (-not $wd) { return $Selected }
    try {
        $wdFull  = [System.IO.Path]::GetFullPath($wd).TrimEnd('\','/')
        $selFull = [System.IO.Path]::GetFullPath($Selected).TrimEnd('\','/')
    } catch { return $Selected }
    if ([string]::IsNullOrEmpty($wdFull)) { return $Selected }
    if ([string]::Equals($selFull, $wdFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return '.'
    }
    $prefix = $wdFull + '\'
    if ($selFull.Length -gt $prefix.Length -and
        $selFull.Substring(0, $prefix.Length).Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $selFull.Substring($prefix.Length)
    }
    return $Selected
}

$ctl.BtnBrowse.Add_Click({
    if ($null -eq $script:current) { return }
    # Always prefer the working directory as the starting location so picking
    # a sub-folder is fast. Fall back to the resolved current repo path if
    # working_dir is unset/missing.
    $initial = ''
    $wd = Get-WorkingDir
    if ($wd -and (Test-Path -LiteralPath $wd)) {
        $initial = $wd
    } else {
        $resolved = Resolve-RepoPath ([string]$script:current.path)
        if ($resolved -and (Test-Path -LiteralPath $resolved)) { $initial = $resolved }
    }
    $picked = Show-FolderPicker -Title 'Select repository folder' -InitialDir $initial
    if ($picked) {
        $ctl.TxtPath.Text = (Try-Relativize-Under-WorkingDir $picked)
    }
})

$ctl.BtnBrowseWorkingDir.Add_Click({
    $cur = Get-WorkingDir
    $picked = Show-FolderPicker -Title 'Select working directory' -InitialDir $cur
    if ($picked) {
        $ctl.TxtWorkingDir.Text = $picked
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
        $exportCfg = $cfg | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        if ($exportCfg.PSObject.Properties.Match('working_dir').Count -gt 0) {
            $exportCfg.working_dir = ''
        }
        if ($exportCfg.repos) {
            foreach ($r in $exportCfg.repos) { $r.path = '' }
        }
        Save-Config -Path $dlg.FileName -Config $exportCfg
        Show-Info ("Exported to {0}. Working directory and repo paths were not included - recipients will set their own." -f $dlg.FileName)
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

    # Non-blocking warning: blank paths (from a portable share) and
    # paths that don't exist on this machine are both shown distinctly.
    $blank   = 0
    $missing = @()
    foreach ($vm in $reposVm) {
        $p = ([string]$vm.path).Trim()
        $label = ([string]$vm.name).Trim()
        if (-not $label) { $label = '(unnamed)' }
        if (-not $p) {
            $blank++
        } else {
            $resolved = Resolve-RepoPath $p
            if (-not (Test-Path -LiteralPath $resolved)) {
                $missing += $label
            }
        }
    }
    $parts = @()
    $wd = Get-WorkingDir
    if ($wd -and -not (Test-Path -LiteralPath $wd)) {
        $parts += "working directory '$wd' doesn't exist on this machine"
    }
    if ($blank -gt 0) {
        $parts += "{0} repo(s) need a path - click Browse to set them" -f $blank
    }
    if ($missing.Count -gt 0) {
        $list = ($missing | Select-Object -First 5) -join ', '
        if ($missing.Count -gt 5) { $list += (", +{0} more" -f ($missing.Count - 5)) }
        $parts += "{0} path(s) don't exist on this machine: {1}" -f $missing.Count, $list
    }
    if ($parts.Count -gt 0) {
        Show-Info ("Imported. " + ($parts -join ' | ') + ". Update before saving.")
    } else {
        Show-Info ("Imported from {0}" -f $dlg.FileName)
    }
})

# ---- Help menu --------------------------------------------------------------
$script:HelpUrls = @{
    Bug        = 'https://github.com/william051200/githerd/issues/new?template=bug.yml'
    Suggestion = 'https://github.com/william051200/githerd/issues/new?template=suggestion.yml'
    Readme     = 'https://github.com/william051200/githerd#readme'
}

function Open-Url([string]$url) {
    try {
        Start-Process $url | Out-Null
    } catch {
        Show-Error ("Couldn't open {0}: {1}" -f $url, $_.Exception.Message)
    }
}

$ctl.BtnHelp.Add_Click({
    $menu = $ctl.BtnHelp.ContextMenu
    if ($null -eq $menu) { return }
    $menu.PlacementTarget = $ctl.BtnHelp
    $menu.Placement       = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $menu.IsOpen          = $true
})
$ctl.MenuReportBug.Add_Click({  Open-Url $script:HelpUrls.Bug })
$ctl.MenuSuggest.Add_Click({    Open-Url $script:HelpUrls.Suggestion })
$ctl.MenuOpenReadme.Add_Click({ Open-Url $script:HelpUrls.Readme })

# ---- Update notification ----------------------------------------------------
$script:UpdateCacheDir   = Join-Path $env:LOCALAPPDATA 'GitHerd'
$script:UpdateCacheFile  = Join-Path $script:UpdateCacheDir 'update-check.json'
$script:UpdateDismissFile = Join-Path $script:UpdateCacheDir 'update-dismissed.json'
$script:UpdateCheckPs    = Join-Path $PSScriptRoot '..\lib\update-check.ps1'
$script:LatestTag        = $null   # set when banner is shown

function Normalize-Tag([string]$Tag) {
    if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }
    return $Tag.Trim().TrimStart('v','V')
}

function Compare-SemVer([string]$A, [string]$B) {
    $pa = ($A -split '[.+-]') | ForEach-Object { [int]($_ -replace '\D','0') }
    $pb = ($B -split '[.+-]') | ForEach-Object { [int]($_ -replace '\D','0') }
    $len = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $len; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return  1 }
    }
    return 0
}

function Get-DismissedTag {
    if (-not (Test-Path -LiteralPath $script:UpdateDismissFile)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $script:UpdateDismissFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        return [string]$obj.dismissed_tag
    } catch { return $null }
}

function Set-DismissedTag([string]$Tag) {
    try {
        if (-not (Test-Path -LiteralPath $script:UpdateCacheDir)) {
            New-Item -ItemType Directory -Path $script:UpdateCacheDir -Force | Out-Null
        }
        @{ dismissed_tag = $Tag } | ConvertTo-Json | Set-Content -LiteralPath $script:UpdateDismissFile -Encoding UTF8
    } catch {}
}

function Get-LatestTagFromCache {
    if (-not (Test-Path -LiteralPath $script:UpdateCacheFile)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $script:UpdateCacheFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        return [string]$obj.latest_tag
    } catch { return $null }
}

function Refresh-UpdateBanner {
    param([switch]$RespectDismiss)

    $ctl.UpdateBanner.Visibility = 'Collapsed'
    $script:LatestTag = $null

    if (-not $ghVersion) { return $false }

    $tag = Get-LatestTagFromCache
    $latestNum = Normalize-Tag $tag
    if (-not $latestNum) { return $false }

    if ((Compare-SemVer $ghVersion $latestNum) -ge 0) { return $false }

    if ($RespectDismiss) {
        $dismissed = Normalize-Tag (Get-DismissedTag)
        if ($dismissed -and (Compare-SemVer $dismissed $latestNum) -ge 0) {
            return $false
        }
    }

    $script:LatestTag = $tag
    $ctl.UpdateBannerText.Text = ("🎉  GitHerd v{0} is available. You're on v{1}." -f $latestNum, $ghVersion)
    $ctl.UpdateBanner.Visibility = 'Visible'
    return $true
}

$ctl.BtnWhatsNew.Add_Click({
    if ([string]::IsNullOrWhiteSpace($script:LatestTag)) { return }
    $tag = $script:LatestTag
    if (-not $tag.StartsWith('v')) { $tag = 'v' + $tag.TrimStart('v','V') }
    Open-Url ("https://github.com/william051200/githerd/releases/tag/" + $tag)
})

$ctl.BtnDismissUpdate.Add_Click({
    if ($script:LatestTag) { Set-DismissedTag $script:LatestTag }
    $ctl.UpdateBanner.Visibility = 'Collapsed'
})

$ctl.BtnUpdateNow.Add_Click({
    $script:resultExitCode = 20
    $window.Close()
})

$ctl.MenuCheckUpdates.Add_Click({
    if (-not (Test-Path -LiteralPath $script:UpdateCheckPs)) {
        Show-Error "update-check.ps1 is missing - reinstall GitHerd."
        return
    }
    Show-Info "Checking for updates..."
    try {
        # -Force ignores the daily throttle; -Quiet suppresses console output.
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script:UpdateCheckPs -Force -Quiet | Out-Null
    } catch {
        Show-Error ("Update check failed: " + $_.Exception.Message)
        return
    }
    # Force-refresh: ignore dismissal so the user sees the result of an explicit check.
    if (Refresh-UpdateBanner) {
        Show-Error $null
    } else {
        $tag = Normalize-Tag (Get-LatestTagFromCache)
        if (-not $tag) { $tag = $ghVersion }
        Show-Info ("You're up to date - v{0}." -f $tag)
    }
})

# Initial banner render (honors dismissal).
[void](Refresh-UpdateBanner -RespectDismiss)

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
        $masterRemote = ([string]$vm.master_remote).Trim()
        if (-not $masterRemote) { $masterRemote = if ($vm.auto_merge) { 'upstream' } else { 'origin' } }
        if ($masterRemote.StartsWith('-') -or $masterRemote -match '[\s"&|<>^%!()]') {
            throw "Repo '$name': Master repo '$masterRemote' contains characters that are unsafe for CMD."
        }

        $repos += [pscustomobject]@{
            name       = $name
            path       = $path
            master     = $master
            auto_merge = [bool]$vm.auto_merge
            master_remote = $masterRemote
        }
    }
    if ($repos.Count -eq 0) { throw 'Add at least one repository.' }

    $finalCmd = [string]$ctl.TxtFinal.Text
    if ($finalCmd.Contains('"')) {
        throw 'Final command may not contain double-quotes (").'
    }

    $workingDir = ([string]$ctl.TxtWorkingDir.Text).Trim()
    if ($workingDir.Contains('"')) {
        throw 'Working directory may not contain double-quotes (").'
    }

    $timeout = 600
    if (-not [int]::TryParse($ctl.TxtTimeout.Text, [ref]$timeout)) {
        throw "Worker timeout must be an integer (got '$($ctl.TxtTimeout.Text)')."
    }
    if ($timeout -lt 10 -or $timeout -gt 86400) {
        throw "Worker timeout must be between 10 and 86400 seconds."
    }

    return [pscustomobject]@{
        working_dir      = $workingDir
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
