$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\installer\UpdateCore.ps1')
. (Join-Path $PSScriptRoot '..\installer\InstallerCore.ps1')
$taskFixture=Join-Path $PSScriptRoot ('updater-fixture-'+[guid]::NewGuid().ToString('N'))
$taskBundle=Join-Path $taskFixture 'Bundle'
$taskGame=Join-Path $taskFixture 'Game'
New-Item -ItemType Directory -Path (Join-Path $taskBundle 'Mods\MidgardFirstPerson\Scripts'),$taskGame -Force | Out-Null
foreach ($taskName in @('UE4SS.dll','dwmapi.dll','UE4SS-settings.ini')) { Set-Content -LiteralPath (Join-Path $taskBundle $taskName) -Value 'fixture loader; never executed' }
Set-Content -LiteralPath (Join-Path $taskBundle 'Mods\MidgardFirstPerson\Scripts\main.lua') -Value 'bundled source'
Set-Content -LiteralPath (Join-Path $taskGame 'TOM-Win64-Shipping.exe') -Value 'fixture; never executed'
$script:taskRevision='1234567890123456789012345678901234567890'
$script:taskFiles=@()
$script:taskDownloadSource=Join-Path $taskFixture 'Source.lua'
Set-Content -LiteralPath $script:taskDownloadSource -Value 'verified updated source'
$taskHash=Get-MidgardBlobHash $script:taskDownloadSource
foreach ($taskName in @('main','config','controls','preferences','appearance','crosshair','aim','graphics','menu','navigation')) {
    $script:taskFiles+=[pscustomobject]@{path="Mods/MidgardFirstPerson/Scripts/$taskName.lua";type='blob';mode='100644';sha=$taskHash;size=25}
}
$script:taskFiles+=[pscustomobject]@{path='installer/Setup.ps1';type='blob';mode='100644';sha=$taskHash;size=25}
$script:taskCorrupt=$false
function Get-MidgardJson([string]$Url) {
    if ($Url.EndsWith('/commits/main')) { return [pscustomobject]@{sha=$script:taskRevision} }
    return [pscustomobject]@{tree=$script:taskFiles;truncated=$false}
}
function Save-MidgardDownload([string]$Url,[string]$Path) {
    if ($Url -notlike "https://raw.githubusercontent.com/D3MediaCoding/MidgardPOV/$script:taskRevision/Mods/MidgardFirstPerson/Scripts/*.lua") { throw 'Unpinned source download.' }
    Copy-Item -LiteralPath $script:taskDownloadSource -Destination $Path
    if ($script:taskCorrupt) { Add-Content -LiteralPath $Path -Value 'corrupt' }
}
$taskOnline=Get-MidgardOnlinePayload $taskBundle (Join-Path $taskFixture 'Cache')
if ($taskOnline.Revision -ne $script:taskRevision -or (Get-ChildItem -LiteralPath (Join-Path $taskOnline.Payload 'Mods\MidgardFirstPerson\Scripts') -File).Count -ne 10) { throw 'Source update failed.' }
if (Test-Path -LiteralPath (Join-Path $taskOnline.Payload 'installer\Setup.ps1')) { throw 'Updater downloaded executable setup code.' }
Install-Midgard $taskGame $taskOnline.Payload $taskOnline.Revision | Out-Null
$taskRecord=Get-Content -LiteralPath (Join-Path $taskGame '.midgard-pov-install.json') -Raw | ConvertFrom-Json
if ($taskRecord.SourceRevision -ne $script:taskRevision) { throw 'Revision not recorded.' }
$taskPrefs=Join-Path $taskGame 'Mods\MidgardFirstPerson\Scripts\user_settings.ini'
Set-Content -LiteralPath $taskPrefs -Value 'FOV=115'
Install-Midgard $taskGame $taskOnline.Payload $taskOnline.Revision | Out-Null
if ((Get-Content -LiteralPath $taskPrefs -Raw) -notmatch '115') { throw 'Update lost settings.' }
$script:taskCorrupt=$true
$taskRejected=$false
try { Get-MidgardOnlinePayload $taskBundle (Join-Path $taskFixture 'Cache') | Out-Null } catch { $taskRejected=$true }
if (-not $taskRejected) { throw 'Corrupt download accepted.' }
$script:taskCorrupt=$false
$script:taskRevision='../bad'
$taskRejected=$false
try { Get-MidgardOnlinePayload $taskBundle (Join-Path $taskFixture 'Cache') | Out-Null } catch { $taskRejected=$true }
if (-not $taskRejected) { throw 'Invalid revision accepted.' }
function Get-MidgardJson([string]$Url) { throw 'Simulated offline GitHub' }
$taskRejected=$false
try { Get-MidgardOnlinePayload $taskBundle (Join-Path $taskFixture 'Cache') | Out-Null } catch { $taskRejected=$true }
if (-not $taskRejected -or (Get-Content -LiteralPath $taskPrefs -Raw) -notmatch '115') { throw 'Offline behavior failed.' }
Write-Output 'PASS: pinned source downloads, blob verification, source-only filtering, revision tracking, settings retention, corruption rejection and offline failure.'
Write-Output $taskFixture
