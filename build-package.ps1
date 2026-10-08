$ErrorActionPreference='Stop'
$taskRelease=Join-Path $PSScriptRoot 'dist\MidgardPOV-0.8.1'
$taskPayload=Join-Path $taskRelease 'Payload'
New-Item -ItemType Directory -Path (Join-Path $taskPayload 'Mods\MidgardFirstPerson\Scripts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Setup.ps1'),(Join-Path $PSScriptRoot 'installer\InstallerCore.ps1'),(Join-Path $PSScriptRoot 'installer\Install.cmd') -Destination $taskRelease
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'vendor\UE4SS_v3.0.1\dwmapi.dll') -Destination $taskPayload
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'vendor\UE4SS_v3.0.1-1161-g6eb3d9bc\ue4ss\UE4SS.dll') -Destination $taskPayload
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'staging\UE4SS-settings.ini') -Destination $taskPayload
$taskSettingsPath=Join-Path $taskPayload 'UE4SS-settings.ini'
$taskSettings=[IO.File]::ReadAllText($taskSettingsPath)
$taskSettings=[regex]::Replace($taskSettings,'(?m)^MajorVersion\s*=.*$','MajorVersion = 4')
$taskSettings=[regex]::Replace($taskSettings,'(?m)^MinorVersion\s*=.*$','MinorVersion = 27')
[IO.File]::WriteAllText($taskSettingsPath,$taskSettings,[Text.UTF8Encoding]::new($false))
# Ship only active modules, never personal settings, logs or machine paths.
foreach ($taskName in @('main','config','controls','preferences','appearance','crosshair','aim','graphics','menu','navigation')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Mods\MidgardFirstPerson\Scripts\$taskName.lua") -Destination (Join-Path $taskPayload 'Mods\MidgardFirstPerson\Scripts')
}
Set-Content -LiteralPath (Join-Path $taskPayload 'Mods\mods.txt') -Value 'MidgardFirstPerson : 1' -Encoding ASCII
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\START-HERE.txt') -Destination $taskRelease
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\LICENSE-UE4SS.txt') -Destination $taskRelease
Compress-Archive -LiteralPath $taskRelease -DestinationPath (Join-Path $PSScriptRoot 'dist\MidgardPOV-0.8.1.zip') -CompressionLevel Optimal -Force
Write-Output (Join-Path $PSScriptRoot 'dist\MidgardPOV-0.8.1.zip')
