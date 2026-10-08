$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\installer\InstallerCore.ps1')
$taskFixture=Join-Path $PSScriptRoot ('installer-fixture-'+[guid]::NewGuid().ToString('N'))
$taskGame=Join-Path $taskFixture 'Game'
$taskPayload=Join-Path $taskFixture 'Payload'
New-Item -ItemType Directory -Path $taskGame,(Join-Path $taskPayload 'Mods\MidgardFirstPerson\Scripts') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $taskGame 'TOM-Win64-Shipping.exe') -Value 'fixture; never executed'
foreach ($taskName in @('UE4SS.dll','dwmapi.dll','UE4SS-settings.ini')) { Set-Content -LiteralPath (Join-Path $taskPayload $taskName) -Value 'fixture v1' }
Set-Content -LiteralPath (Join-Path $taskPayload 'Mods\MidgardFirstPerson\Scripts\main.lua') -Value 'fixture mod v1'
Install-Midgard $taskGame $taskPayload | Out-Null
$taskInstalled=Join-Path $taskGame 'Mods\MidgardFirstPerson\Scripts\main.lua'
$taskPreferences=Join-Path $taskGame 'Mods\MidgardFirstPerson\Scripts\user_settings.ini'
Set-Content -LiteralPath $taskPreferences -Value 'FOV=120'
Set-Content -LiteralPath (Join-Path $taskPayload 'Mods\MidgardFirstPerson\Scripts\main.lua') -Value 'fixture mod v2'
Install-Midgard $taskGame $taskPayload | Out-Null
if ((Get-Content -LiteralPath $taskInstalled -Raw) -notmatch 'v2') { throw 'Update failed.' }
if ((Get-Content -LiteralPath $taskPreferences -Raw) -notmatch 'FOV=120') { throw 'Preferences overwritten.' }
Set-Content -LiteralPath $taskInstalled -Value 'user edit'
$taskRejected=$false
try { Install-Midgard $taskGame $taskPayload | Out-Null } catch { $taskRejected=$true }
if (-not $taskRejected) { throw 'Edited-file install was not rejected.' }
$taskRejected=$false
try { Uninstall-Midgard $taskGame | Out-Null } catch { $taskRejected=$true }
if (-not $taskRejected -or -not (Test-Path -LiteralPath (Join-Path $taskGame 'UE4SS.dll'))) { throw 'Uninstall did not preserve edited files.' }
Copy-Item -LiteralPath (Join-Path $taskPayload 'Mods\MidgardFirstPerson\Scripts\main.lua') -Destination $taskInstalled
$taskRejected=$false
try { Get-MidgardPath $taskGame '..\outside.txt' | Out-Null } catch { $taskRejected=$true }
if (-not $taskRejected) { throw 'Path traversal was not rejected.' }
Uninstall-Midgard $taskGame | Out-Null
if ((Test-Path -LiteralPath $taskInstalled) -or -not (Test-Path -LiteralPath $taskPreferences)) { throw 'Uninstall file ownership failed.' }
Set-Content -LiteralPath (Join-Path $taskGame 'dwmapi.dll') -Value 'unrelated loader'
$taskRejected=$false
try { Install-Midgard $taskGame $taskPayload | Out-Null } catch { $taskRejected=$true }
if (-not $taskRejected -or (Test-Path -LiteralPath (Join-Path $taskGame 'UE4SS.dll'))) { throw 'Existing-loader conflict was not rejected before mutation.' }
Write-Output 'PASS: clean install, update backups, settings retention, edit/conflict protection, path containment and uninstall.'
# Preserve this tiny fixture and its update backups as test evidence.
Write-Output $taskFixture
