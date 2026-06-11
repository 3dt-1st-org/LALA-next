param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$OutputPath = ".\artifacts\openapi\lala-next-openapi.json"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ResolvedOutputPath = $OutputPath
if (-not [System.IO.Path]::IsPathRooted($ResolvedOutputPath)) {
    $ResolvedOutputPath = Join-Path $RepoRoot $ResolvedOutputPath
}

$OutputDirectory = Split-Path -Parent $ResolvedOutputPath
if (-not $OutputDirectory) {
    $OutputDirectory = $RepoRoot
    $ResolvedOutputPath = Join-Path $RepoRoot $ResolvedOutputPath
}
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null

$schemaUrl = "$($BaseUrl.TrimEnd('/'))/openapi.json"
Write-Host "Exporting OpenAPI schema from $schemaUrl"

$schema = Invoke-RestMethod -Method Get -Uri $schemaUrl
$schema |
    ConvertTo-Json -Depth 100 |
    Set-Content -Path $ResolvedOutputPath -Encoding UTF8

Write-Host "OpenAPI schema written to $ResolvedOutputPath"
