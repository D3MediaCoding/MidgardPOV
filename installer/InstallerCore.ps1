$ErrorActionPreference = 'Stop'
function Get-MidgardDestination([string]$GameFolder) {
    $taskCandidate = [IO.Path]::GetFullPath($GameFolder)
    if (-not (Test-Path -LiteralPath (Join-Path $taskCandidate 'TOM-Win64-Shipping.exe'))) {
        $taskCandidate = Join-Path $taskCandidate 'TOM\Binaries\Win64'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $taskCandidate 'TOM-Win64-Shipping.exe'))) { throw 'Select the Tribes of Midgard Steam installation folder.' }
    return (Resolve-Path -LiteralPath $taskCandidate).Path
}
function Get-MidgardPath([string]$Root,[string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Invalid absolute path in mod record.' }
    $taskPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $taskPath = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $taskPath.StartsWith($taskPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Mod path escaped the selected folder.' }
    return $taskPath
}
function Assert-MidgardClosed {
    if (Get-Process -Name 'TOM-Win64-Shipping','TOM' -ErrorAction SilentlyContinue) { throw 'Close Tribes of Midgard before installing or uninstalling.' }
}
function Install-Midgard([string]$GameFolder,[string]$Payload) {
    Assert-MidgardClosed
    $taskRoot=Get-MidgardDestination $GameFolder
    $taskManifestPath=Join-Path $taskRoot '.midgard-pov-install.json'
    $taskOld=@{}
    if (Test-Path -LiteralPath $taskManifestPath) {
        $taskRecord=Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
        if ($taskRecord.Product -ne 'MidgardPOV') { throw 'Unrecognized installation record.' }
        foreach ($taskEntry in $taskRecord.Files) {
            $taskTarget=Get-MidgardPath $taskRoot $taskEntry.Path
            if ((Test-Path -LiteralPath $taskTarget) -and (Get-FileHash -LiteralPath $taskTarget -Algorithm SHA256).Hash -ne $taskEntry.SHA256) {
                throw "A previously installed file was edited: $($taskEntry.Path). Back it up before replacing it."
            }
            $taskOld[$taskEntry.Path]=$taskEntry
        }
    }
    $taskPayloadRoot=(Resolve-Path -LiteralPath $Payload).Path.TrimEnd('\')+'\'
    $taskPlan=@()
    foreach ($taskSource in Get-ChildItem -LiteralPath $Payload -File -Recurse) {
        $taskRelative=$taskSource.FullName.Substring($taskPayloadRoot.Length)
        $taskTarget=Get-MidgardPath $taskRoot $taskRelative
        if ((Test-Path -LiteralPath $taskTarget) -and -not $taskOld.ContainsKey($taskRelative)) { throw "Existing file belongs to another installation: $taskRelative. This installer will not overwrite it."
        }
        $taskHash=(Get-FileHash -LiteralPath $taskSource.FullName -Algorithm SHA256).Hash
        $taskPlan+= [pscustomobject]@{Path=$taskRelative;Source=$taskSource.FullName;Target=$taskTarget;SHA256=$taskHash}
    }
    if ($taskPlan.Count -lt 4 -or -not (Test-Path -LiteralPath (Join-Path $Payload 'UE4SS.dll'))) { throw 'The package Payload is incomplete. Extract the whole ZIP first.' }
    $taskBackup=Join-Path $taskRoot ('MidgardPOV-backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    $taskChanged=@()
    try {
        foreach ($taskChange in $taskPlan) {
            $taskExisted=Test-Path -LiteralPath $taskChange.Target
            $taskBackupPath=Get-MidgardPath $taskBackup $taskChange.Path
            if ($taskExisted) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $taskBackupPath) -Force | Out-Null
                Copy-Item -LiteralPath $taskChange.Target -Destination $taskBackupPath
            }
            $taskChanged+=[pscustomobject]@{Target=$taskChange.Target;Backup=$taskBackupPath;Existed=$taskExisted}
            New-Item -ItemType Directory -Path (Split-Path -Parent $taskChange.Target) -Force | Out-Null
            Copy-Item -LiteralPath $taskChange.Source -Destination $taskChange.Target
        }
        foreach ($taskChange in $taskPlan) { $taskOld[$taskChange.Path]=[pscustomobject]@{Path=$taskChange.Path;SHA256=$taskChange.SHA256} }
        $taskRecord=[pscustomobject]@{Product='MidgardPOV';Version='0.8';Files=@($taskOld.Values)}
        $taskTemporary=$taskManifestPath+'.tmp'
        $taskRecord | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $taskTemporary -Encoding UTF8
        Move-Item -LiteralPath $taskTemporary -Destination $taskManifestPath -Force
    } catch {
        for ($taskIndex=$taskChanged.Count-1;$taskIndex -ge 0;$taskIndex--) {
            $taskChange=$taskChanged[$taskIndex]
            if ($taskChange.Existed) { Copy-Item -LiteralPath $taskChange.Backup -Destination $taskChange.Target }
            elseif (Test-Path -LiteralPath $taskChange.Target) { Remove-Item -LiteralPath $taskChange.Target }
        }
        throw
    }
    return "Installed Midgard POV 0.8. Launch the game, enter a world, and open Mod settings or press Insert."
}
function Uninstall-Midgard([string]$GameFolder) {
    Assert-MidgardClosed
    $taskRoot=Get-MidgardDestination $GameFolder
    $taskManifestPath=Join-Path $taskRoot '.midgard-pov-install.json'
    if (-not (Test-Path -LiteralPath $taskManifestPath)) { throw 'No Midgard POV installation record found in this folder.' }
    $taskRecord=Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
    if ($taskRecord.Product -ne 'MidgardPOV') { throw 'Unrecognized installation record.' }
    $taskTargets=@()
    foreach ($taskEntry in $taskRecord.Files) {
        $taskTarget=Get-MidgardPath $taskRoot $taskEntry.Path
        if ((Test-Path -LiteralPath $taskTarget) -and (Get-FileHash -LiteralPath $taskTarget -Algorithm SHA256).Hash -ne $taskEntry.SHA256) {
            throw "File was edited; uninstall stopped to preserve it: $($taskEntry.Path)"
        }
        $taskTargets+=$taskTarget
    }
    foreach ($taskTarget in $taskTargets) { if (Test-Path -LiteralPath $taskTarget) { Remove-Item -LiteralPath $taskTarget } }
    Remove-Item -LiteralPath $taskManifestPath
    return 'Uninstalled. Saves, personal settings, logs and update backups remain.'
}
