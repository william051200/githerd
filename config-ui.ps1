#Requires -Version 5.0
<#
.SYNOPSIS
    WinForms editor for githerd's config.json.

.DESCRIPTION
    Edits the repo list, final post-sync command, and max wait timeout.
    Exit codes:
      0  - Saved and closed (or Cancel without changes)
      10 - Saved with "Save & Run" (caller should launch the sync)
      2  - User cancelled
      1  - Error
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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
        # Seed from sibling config.example.json if available so a fresh checkout
        # opens with a sensible starting point.
        $example = Join-Path (Split-Path -Parent $source) 'config.example.json'
        if (Test-Path -LiteralPath $example) {
            $source = $example
        } else {
            return New-DefaultConfig
        }
    }
    try {
        $raw = Get-Content -LiteralPath $source -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return New-DefaultConfig }
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to read $Path`n$($_.Exception.Message)`n`nStarting with empty config.",
            'Config load error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return New-DefaultConfig
    }
}

function Save-Config {
    param(
        [string]$Path,
        $Config
    )
    $json = $Config | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

$config = Load-Config -Path $ConfigPath

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'githerd - Configuration'
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(700, 500)

# ---- Repos label ----
$lblRepos = New-Object System.Windows.Forms.Label
$lblRepos.Text = 'Repositories'
$lblRepos.Location = New-Object System.Drawing.Point(12, 10)
$lblRepos.AutoSize = $true
$lblRepos.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblRepos)

# ---- Repos grid ----
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(12, 35)
$grid.Size = New-Object System.Drawing.Size(860, 280)
$grid.Anchor = 'Top,Left,Right'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'
$grid.MultiSelect = $false

$colName   = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.HeaderText = 'Name'
$colName.Name = 'name'

$colPath   = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPath.HeaderText = 'Path'
$colPath.Name = 'path'
$colPath.FillWeight = 200

$colMaster = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colMaster.HeaderText = 'Master Branch'
$colMaster.Name = 'master'

$colAuto   = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colAuto.HeaderText = 'Auto Merge'
$colAuto.Name = 'auto_merge'
$colAuto.FillWeight = 60

$grid.Columns.AddRange([System.Windows.Forms.DataGridViewColumn[]]@($colName, $colPath, $colMaster, $colAuto))
$form.Controls.Add($grid)

foreach ($r in @($config.repos)) {
    if ($null -eq $r) { continue }
    $auto = $false
    if ($r.PSObject.Properties.Match('auto_merge').Count -gt 0) { $auto = [bool]$r.auto_merge }
    [void]$grid.Rows.Add($r.name, $r.path, $r.master, $auto)
}

# ---- Add / Remove / Browse buttons ----
$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add Repo'
$btnAdd.Location = New-Object System.Drawing.Point(12, 325)
$btnAdd.Size = New-Object System.Drawing.Size(100, 26)
$btnAdd.Anchor = 'Top,Left'
$btnAdd.Add_Click({
    $idx = $grid.Rows.Add('', '', 'main', $true)
    $grid.ClearSelection()
    $grid.Rows[$idx].Selected = $true
    $grid.CurrentCell = $grid.Rows[$idx].Cells['name']
    $grid.FirstDisplayedScrollingRowIndex = $idx
    $grid.BeginEdit($true)
})
$form.Controls.Add($btnAdd)

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = 'Remove Selected'
$btnRemove.Location = New-Object System.Drawing.Point(118, 325)
$btnRemove.Size = New-Object System.Drawing.Size(120, 26)
$btnRemove.Anchor = 'Top,Left'
$btnRemove.Add_Click({
    if ($grid.SelectedRows.Count -gt 0) {
        $grid.Rows.Remove($grid.SelectedRows[0])
    }
})
$form.Controls.Add($btnRemove)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse Path...'
$btnBrowse.Location = New-Object System.Drawing.Point(244, 325)
$btnBrowse.Size = New-Object System.Drawing.Size(110, 26)
$btnBrowse.Anchor = 'Top,Left'
$btnBrowse.Add_Click({
    if ($grid.SelectedRows.Count -eq 0) { return }
    $row = $grid.SelectedRows[0]
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select repository folder'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $row.Cells['path'].Value = $dlg.SelectedPath
    }
})
$form.Controls.Add($btnBrowse)

# ---- Path hint ----
$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = 'Path: absolute (C:\code\my-repo) or relative to where you run sync.bat (.\my-repo). Use Browse Path... to fill it in.'
$lblHint.Location = New-Object System.Drawing.Point(360, 330)
$lblHint.AutoSize = $true
$lblHint.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblHint)

# ---- Final command ----
$lblCmd = New-Object System.Windows.Forms.Label
$lblCmd.Text = 'Final command (run after all repos sync; leave blank to skip):'
$lblCmd.Location = New-Object System.Drawing.Point(12, 365)
$lblCmd.AutoSize = $true
$form.Controls.Add($lblCmd)

$txtCmd = New-Object System.Windows.Forms.TextBox
$txtCmd.Location = New-Object System.Drawing.Point(12, 385)
$txtCmd.Size = New-Object System.Drawing.Size(860, 70)
$txtCmd.Anchor = 'Top,Left,Right'
$txtCmd.Multiline = $true
$txtCmd.ScrollBars = 'Vertical'
$txtCmd.Font = New-Object System.Drawing.Font('Consolas', 10)
$txtCmd.Text = [string]$config.final_command
$form.Controls.Add($txtCmd)

# ---- Max wait ----
$lblWait = New-Object System.Windows.Forms.Label
$lblWait.Text = 'Max wait (seconds):'
$lblWait.Location = New-Object System.Drawing.Point(12, 470)
$lblWait.AutoSize = $true
$form.Controls.Add($lblWait)

$numWait = New-Object System.Windows.Forms.NumericUpDown
$numWait.Location = New-Object System.Drawing.Point(140, 467)
$numWait.Size = New-Object System.Drawing.Size(100, 24)
$numWait.Minimum = 10
$numWait.Maximum = 86400
$numWait.Value = [Math]::Max(10, [int]([Math]::Min(86400, [int]($config.max_wait_seconds))))
$form.Controls.Add($numWait)

# ---- Bottom buttons ----
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = 'Save'
$btnSave.Size = New-Object System.Drawing.Size(100, 30)
$btnSave.Anchor = 'Bottom,Right'
$btnSave.Location = New-Object System.Drawing.Point(560, 535)
$form.Controls.Add($btnSave)

$btnSaveRun = New-Object System.Windows.Forms.Button
$btnSaveRun.Text = 'Save && Run'
$btnSaveRun.Size = New-Object System.Drawing.Size(110, 30)
$btnSaveRun.Anchor = 'Bottom,Right'
$btnSaveRun.Location = New-Object System.Drawing.Point(665, 535)
$form.Controls.Add($btnSaveRun)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'
$btnCancel.Size = New-Object System.Drawing.Size(90, 30)
$btnCancel.Anchor = 'Bottom,Right'
$btnCancel.Location = New-Object System.Drawing.Point(780, 535)
$form.Controls.Add($btnCancel)

$form.AcceptButton = $btnSave
$form.CancelButton = $btnCancel

$script:resultExitCode = 2  # default = cancelled

function Validate-And-Build {
    $repos = @()
    $names = @{}
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        $row = $grid.Rows[$i]
        $name   = ([string]$row.Cells['name'].Value).Trim()
        $path   = ([string]$row.Cells['path'].Value).Trim()
        $master = ([string]$row.Cells['master'].Value).Trim()
        $auto   = [bool]$row.Cells['auto_merge'].Value

        if (-not $name -and -not $path -and -not $master) { continue } # skip blank rows

        if (-not $name)   { throw "Row $($i+1): Name is required." }
        if (-not $path)   { throw "Row $($i+1): Path is required." }
        if (-not $master) { throw "Row $($i+1): Master branch is required." }
        if ($names.ContainsKey($name.ToLowerInvariant())) {
            throw "Row $($i+1): Duplicate name '$name'."
        }
        $names[$name.ToLowerInvariant()] = $true

        $repos += [pscustomobject]@{
            name       = $name
            path       = $path
            master     = $master
            auto_merge = $auto
        }
    }
    if ($repos.Count -eq 0) { throw 'Add at least one repository.' }

    return [pscustomobject]@{
        repos            = $repos
        final_command    = $txtCmd.Text
        max_wait_seconds = [int]$numWait.Value
    }
}

function Try-Save {
    try {
        $cfg = Validate-And-Build
        Save-Config -Path $ConfigPath -Config $cfg
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Validation error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
}

$btnSave.Add_Click({
    if (Try-Save) { $script:resultExitCode = 0; $form.Close() }
})
$btnSaveRun.Add_Click({
    if (Try-Save) { $script:resultExitCode = 10; $form.Close() }
})
$btnCancel.Add_Click({
    $script:resultExitCode = 2; $form.Close()
})

[void]$form.ShowDialog()
exit $script:resultExitCode
