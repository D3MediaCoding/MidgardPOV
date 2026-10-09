$ErrorActionPreference='Stop'
$taskDependencies=@{
    'vendor\UE4SS_v3.0.1\dwmapi.dll'='ce596412befa68c30b7f88f65beb77d9bdad55e9b96a276a5a9cf690c63f24bb'
    'vendor\UE4SS_v3.0.1-1161-g6eb3d9bc\ue4ss\UE4SS.dll'='f176dc36fd2bc7b8211dde6ba54ade6f66da5c8f3a79e3017a85b45c215e8242'
}
foreach ($taskDependency in $taskDependencies.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $taskDependency) -Algorithm SHA256).Hash -ne $taskDependencies[$taskDependency]) { throw "Loader hash mismatch: $taskDependency" }
}
$taskRelease=Join-Path $PSScriptRoot 'dist\MidgardPOV-0.9.0'
if (Test-Path -LiteralPath $taskRelease) { throw 'Release output folder already exists. Use a fresh output folder before rebuilding.' }
$taskPayload=Join-Path $taskRelease 'Payload'
New-Item -ItemType Directory -Path (Join-Path $taskPayload 'Mods\MidgardFirstPerson\Scripts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\Setup.ps1'),(Join-Path $PSScriptRoot 'installer\InstallerCore.ps1'),(Join-Path $PSScriptRoot 'installer\UpdateCore.ps1'),(Join-Path $PSScriptRoot 'installer\Install.cmd') -Destination $taskRelease
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
Compress-Archive -LiteralPath $taskRelease -DestinationPath (Join-Path $PSScriptRoot 'dist\MidgardPOV-0.9.0.zip') -CompressionLevel Optimal -Force
Write-Output (Join-Path $PSScriptRoot 'dist\MidgardPOV-0.9.0.zip')
