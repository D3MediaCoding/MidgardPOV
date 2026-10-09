# Windows PowerShell 5.1 compatible, GUI installer; no administrator requirement.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'InstallerCore.ps1')
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
$taskSelectedPayload=Join-Path $PSScriptRoot 'Payload'
$taskSelectedRevision=''
$taskOnlineReady=$false
function Find-Midgard {
    $taskSteam=(Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $taskLibraries=@($taskSteam,'C:\Program Files (x86)\Steam') | Where-Object { $_ }
    if ($taskSteam) {
        $taskVdf=Join-Path $taskSteam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $taskVdf) {
            $taskVdfText=Get-Content -LiteralPath $taskVdf -Raw
            foreach ($taskMatch in [regex]::Matches($taskVdfText,'"path"\s+"([^"]+)"')) { $taskLibraries+=$taskMatch.Groups[1].Value.Replace('\\','\') }
        }
    }
    foreach ($taskLibrary in $taskLibraries) {
        $taskGame=Join-Path $taskLibrary 'steamapps\common\Tribes of Midgard'
        if (Test-Path -LiteralPath (Join-Path $taskGame 'TOM\Binaries\Win64\TOM-Win64-Shipping.exe')) { return $taskGame }
    }
    return ''
}
$taskForm=New-Object Windows.Forms.Form
$taskForm.Text='Midgard POV - Setup'
$taskForm.ClientSize=New-Object Drawing.Size(600,300)
$taskForm.StartPosition='CenterScreen'; $taskForm.FormBorderStyle='FixedDialog'; $taskForm.MaximizeBox=$false
$taskForm.Font=New-Object Drawing.Font('Segoe UI',10)
$taskTitle=New-Object Windows.Forms.Label
$taskTitle.Text='Midgard POV'; $taskTitle.Location=New-Object Drawing.Point(22,18); $taskTitle.Size=New-Object Drawing.Size(555,32)
$taskTitle.Font=New-Object Drawing.Font('Segoe UI',18,[Drawing.FontStyle]::Bold)
$taskInfo=New-Object Windows.Forms.Label
$taskInfo.Text='First person, third person, mouse aiming and vivid graphics.'
$taskInfo.Location=New-Object Drawing.Point(22,60); $taskInfo.Size=New-Object Drawing.Size(555,26)
$taskPath=New-Object Windows.Forms.TextBox
$taskPath.Location=New-Object Drawing.Point(22,104); $taskPath.Size=New-Object Drawing.Size(435,28); $taskPath.Text=Find-Midgard
$taskBrowse=New-Object Windows.Forms.Button
$taskBrowse.Text='Browse...'; $taskBrowse.Location=New-Object Drawing.Point(467,102); $taskBrowse.Size=New-Object Drawing.Size(110,32)
$taskBrowse.Add_Click({
    $taskDialog=New-Object Windows.Forms.FolderBrowserDialog
    $taskDialog.Description='Select the Tribes of Midgard Steam folder'; $taskDialog.ShowNewFolderButton=$false
    if ($taskDialog.ShowDialog() -eq 'OK') { $taskPath.Text=$taskDialog.SelectedPath }
    $taskDialog.Dispose()
})
$taskInstall=New-Object Windows.Forms.Button
$taskInstall.Text='Install / Update'; $taskInstall.Location=New-Object Drawing.Point(22,155); $taskInstall.Size=New-Object Drawing.Size(195,40)
$taskUninstall=New-Object Windows.Forms.Button
$taskUninstall.Text='Uninstall'; $taskUninstall.Location=New-Object Drawing.Point(229,155); $taskUninstall.Size=New-Object Drawing.Size(130,40)
$taskStatus=New-Object Windows.Forms.Label
$taskStatus.Location=New-Object Drawing.Point(22,212); $taskStatus.Size=New-Object Drawing.Size(555,70)
$taskStatus.Text='Close the game first. After installation, enter a world and click Mod settings or press Insert.'
$taskInstall.Add_Click({
    try {
        if (-not $taskOnlineReady) {
            $taskRecordPath=Join-Path (Get-MidgardDestination $taskPath.Text) '.midgard-pov-install.json'
            if (Test-Path -LiteralPath $taskRecordPath) { throw 'Reopen setup when GitHub is available to update an existing installation.' }
        }
        $taskStatus.Text=Install-Midgard $taskPath.Text $taskSelectedPayload $taskSelectedRevision
    }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Installation stopped','OK','Error') | Out-Null }
})
$taskUninstall.Add_Click({
    try { $taskStatus.Text=Uninstall-Midgard $taskPath.Text }
    catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Uninstall stopped','OK','Error') | Out-Null }
})
$taskForm.Controls.AddRange(@($taskTitle,$taskInfo,$taskPath,$taskBrowse,$taskInstall,$taskUninstall,$taskStatus))
$taskForm.Add_Shown({
    $taskInstall.Enabled=$false; $taskUninstall.Enabled=$false
    $taskStatus.Text='Checking GitHub for the latest mod update...'
    [Windows.Forms.Application]::DoEvents()
    try {
        $taskLatest=Get-MidgardOnlinePayload (Join-Path $PSScriptRoot 'Payload') (Join-Path $env:LOCALAPPDATA 'MidgardPOV\Updates')
        $script:taskSelectedPayload=$taskLatest.Payload
        $script:taskSelectedRevision=$taskLatest.Revision
        $script:taskOnlineReady=$true
        $taskStatus.Text='Latest GitHub mod files verified. Close the game and click Install / Update.'
        if ($taskPath.Text) {
            $taskInstalledRecord=Join-Path (Get-MidgardDestination $taskPath.Text) '.midgard-pov-install.json'
            if (Test-Path -LiteralPath $taskInstalledRecord) {
                $taskInstalled=Get-Content -LiteralPath $taskInstalledRecord -Raw | ConvertFrom-Json
                if ($taskInstalled.Product -eq 'MidgardPOV' -and $taskInstalled.SourceRevision -ne $taskLatest.Revision) {
                    $taskStatus.Text=Install-Midgard $taskPath.Text $taskSelectedPayload $taskSelectedRevision
                } else { $taskStatus.Text='Your mod is up to date with GitHub.' }
            }
        }
    } catch {
        $taskStatus.Text='Update check: '+$_.Exception.Message+' The bundled installer remains available.'
    } finally {
        $taskInstall.Enabled=$true; $taskUninstall.Enabled=$true
        if (-not $taskOnlineReady -and $taskPath.Text) {
            try {
                $taskExisting=Join-Path (Get-MidgardDestination $taskPath.Text) '.midgard-pov-install.json'
                if (Test-Path -LiteralPath $taskExisting) {
                    $taskInstall.Enabled=$false
                    $taskStatus.Text='GitHub could not be checked. Your installed mod was kept. Reopen setup when online to update.'
                }
            } catch { }
        }
    }
})
[void]$taskForm.ShowDialog()
$taskForm.Dispose()
