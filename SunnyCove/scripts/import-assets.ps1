param(
    [string]$Source = "$env:USERPROFILE\Desktop\SunnyCoveAssets"
)

$ErrorActionPreference = "Stop"
$destination = Join-Path $PSScriptRoot "..\Resources\GameContent"

if (-not (Test-Path -Path $Source -PathType Container)) {
    throw "Asset-Paket nicht gefunden: $Source"
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
$managedFolders = @('appstore', 'board', 'characters', 'data', 'generators', 'items', 'restoration', 'ui')
foreach ($folder in $managedFolders) {
    $sourceFolder = Join-Path $Source $folder
    if (-not (Test-Path -Path $sourceFolder -PathType Container)) {
        throw "Asset-Unterordner fehlt: $sourceFolder"
    }
    Copy-Item -Path $sourceFolder -Destination $destination -Recurse -Force
}

$svgCount = @(Get-ChildItem -Path $destination -Filter *.svg -Recurse).Count
$jsonCount = @(Get-ChildItem -Path (Join-Path $destination 'data') -Filter *.json -ErrorAction SilentlyContinue).Count
Write-Output "Sunny-Cove-Inhalte importiert: $svgCount SVG-Dateien, $jsonCount JSON-Dateien."
