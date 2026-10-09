$ErrorActionPreference='Stop'
function Get-MidgardJson([string]$Url) {
    Invoke-RestMethod -Uri $Url -Headers @{'User-Agent'='MidgardPOV-Setup';Accept='application/vnd.github+json'} -TimeoutSec 15
}
function Save-MidgardDownload([string]$Url,[string]$Path) {
    Invoke-WebRequest -UseBasicParsing -Uri $Url -Headers @{'User-Agent'='MidgardPOV-Setup'} -OutFile $Path -TimeoutSec 20 | Out-Null
}
function Get-MidgardBlobHash([string]$Path) {
    $taskBytes=[IO.File]::ReadAllBytes($Path)
    $taskPrefix=[Text.Encoding]::ASCII.GetBytes("blob $($taskBytes.Length)`0")
    $taskData=New-Object byte[] ($taskPrefix.Length+$taskBytes.Length)
    [Array]::Copy($taskPrefix,0,$taskData,0,$taskPrefix.Length)
    [Array]::Copy($taskBytes,0,$taskData,$taskPrefix.Length,$taskBytes.Length)
    $taskHasher=[Security.Cryptography.SHA1]::Create()
    try { return ([BitConverter]::ToString($taskHasher.ComputeHash($taskData))).Replace('-','').ToLowerInvariant() }
    finally { $taskHasher.Dispose() }
}
function Get-MidgardOnlinePayload([string]$Bundle,[string]$CacheRoot) {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $taskApi='https://api.github.com/repos/D3MediaCoding/MidgardPOV'
    $taskCommit=Get-MidgardJson "$taskApi/commits/main"
    $taskRevision=[string]$taskCommit.sha
    if ($taskRevision -notmatch '^[0-9a-f]{40}$') { throw 'Invalid GitHub source revision.' }
    $taskTree=Get-MidgardJson "$taskApi/git/trees/$taskRevision`?recursive=1"
    if ($taskTree.truncated) { throw 'GitHub file listing is incomplete.' }
    $taskFiles=@($taskTree.tree | Where-Object { $_.type -eq 'blob' -and $_.mode -eq '100644' -and $_.path -match '^Mods/MidgardFirstPerson/Scripts/[A-Za-z0-9_-]+\.lua$' })
    if ($taskFiles.Count -lt 10 -or $taskFiles.Count -gt 64 -or -not ($taskFiles.path -contains 'Mods/MidgardFirstPerson/Scripts/main.lua')) { throw 'GitHub mod source listing is incomplete.' }
    $taskCache=[IO.Path]::GetFullPath($CacheRoot)
    New-Item -ItemType Directory -Path $taskCache -Force | Out-Null
    $taskStage=Join-Path $taskCache ('download-'+[guid]::NewGuid().ToString('N'))
    $taskPayload=Join-Path $taskStage 'Payload'
    New-Item -ItemType Directory -Path $taskPayload -Force | Out-Null
    Copy-Item -Path (Join-Path $Bundle '*') -Destination $taskPayload -Recurse
    $taskScripts=Join-Path $taskPayload 'Mods\MidgardFirstPerson\Scripts'
    # Remove only the copied bundle's Lua modules, inside our new cache folder.
    if (-not ([IO.Path]::GetFullPath($taskScripts)).StartsWith($taskStage+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid update cache path.' }
    Get-ChildItem -LiteralPath $taskScripts -Filter '*.lua' -File | Remove-Item
    foreach ($taskFile in $taskFiles) {
        if ([string]$taskFile.sha -notmatch '^[0-9a-f]{40}$' -or $taskFile.size -gt 2097152) { throw 'Invalid GitHub mod file metadata.' }
        $taskTarget=Join-Path $taskPayload $taskFile.path
        Save-MidgardDownload "https://raw.githubusercontent.com/D3MediaCoding/MidgardPOV/$taskRevision/$($taskFile.path)" $taskTarget
        if ((Get-MidgardBlobHash $taskTarget) -ne $taskFile.sha) { throw "GitHub source verification failed: $($taskFile.path)" }
    }
    return [pscustomobject]@{Payload=$taskPayload;Revision=$taskRevision;Version='0.9.0'}
}
