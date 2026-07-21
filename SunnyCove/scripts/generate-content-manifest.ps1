param(
    [string]$ContentRoot = "$PSScriptRoot\..\Resources\GameContent",
    [string]$ContentVersion = "2026.07.0",
    [string]$MinimumAppVersion = "0.1.0"
)

$ErrorActionPreference = "Stop"
$ContentRoot = (Resolve-Path -LiteralPath $ContentRoot).Path
$dataFiles = @()
$assetFiles = @()

Get-ChildItem -LiteralPath (Join-Path $ContentRoot 'data') -Filter *.json -File |
    Where-Object { $_.Name -ne 'content-manifest.json' } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($ContentRoot.Length + 1).Replace('\', '/')
        $dataFiles += [ordered]@{
            path = $relative
            bytes = $_.Length
            hash = "sha256:$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
        }
    }

Get-ChildItem -LiteralPath $ContentRoot -Filter *.svg -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($ContentRoot.Length + 1).Replace('\', '/')
        $assetFiles += [ordered]@{
            path = $relative
            bytes = $_.Length
            hash = "sha256:$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
        }
    }

$manifest = [ordered]@{
    schemaVersion = '1.0.0'
    contentVersion = $ContentVersion
    minAppVersion = $MinimumAppVersion
    generatedAt = [DateTime]::UtcNow.ToString('o')
    integrity = [ordered]@{ algorithm = 'sha256'; manifestHash = 'sha256:generated-at-build' }
    dataFiles = $dataFiles
    assets = $assetFiles
}
$target = Join-Path $ContentRoot 'data\content-manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $target -Encoding UTF8
Write-Output "Manifest erzeugt: $($dataFiles.Count) JSON-Dateien, $($assetFiles.Count) SVG-Assets -> $target"
