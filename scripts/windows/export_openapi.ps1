param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$OutputPath = ".\artifacts\openapi\lala-next-openapi.json",
    [switch]$InProcess,
    [string]$Python = ""
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

if ($InProcess) {
    if (-not $Python) {
        $VenvPython = Join-Path $RepoRoot ".venv\Scripts\python.exe"
        if (Test-Path $VenvPython) {
            $Python = $VenvPython
        } else {
            $Python = "python"
        }
    }

    Write-Host "Exporting OpenAPI schema in-process"
    & $Python -m apps.api.app.tools.export_openapi --output $ResolvedOutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "In-process OpenAPI export failed."
    }
    exit 0
}

$schemaUrl = "$($BaseUrl.TrimEnd('/'))/openapi.json"
Write-Host "Exporting OpenAPI schema from $schemaUrl"

$schema = Invoke-RestMethod -Method Get -Uri $schemaUrl
$schema |
    ConvertTo-Json -Depth 100 |
    Set-Content -Path $ResolvedOutputPath -Encoding UTF8

Write-Host "OpenAPI schema written to $ResolvedOutputPath"
