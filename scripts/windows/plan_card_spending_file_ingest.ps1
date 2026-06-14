param(
    [string]$Python = "",
    [string]$KeyVaultUrl = "",
    [switch]$Preview,
    [switch]$Apply,
    [string]$Confirm = "",
    [string]$FilePath = "",
    [string]$CsvPath = "",
    [string]$RegionMap = "",
    [string]$SourceName = "data_portal",
    [string]$DatasetName = "경기도_카드 소비 데이터",
    [string]$VisitorType = "domestic",
    [int]$RowLimit = 0,
    [int]$ConnectTimeout = 5,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Push-Location $RepoRoot
try {
    if (-not $Python) {
        $VenvPython = Join-Path $RepoRoot ".venv\Scripts\python.exe"
        if (Test-Path $VenvPython) {
            $Python = $VenvPython
        } else {
            $Python = "python"
        }
    }

    if ($KeyVaultUrl) {
        [Environment]::SetEnvironmentVariable("KEY_VAULT_URL", $KeyVaultUrl, "Process")
    }

    $EnvFile = Join-Path $RepoRoot ".env"
    if (Test-Path $EnvFile) {
        Get-Content $EnvFile | ForEach-Object {
            $line = $_.Trim()
            if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
                return
            }
            $name, $value = $line.Split("=", 2)
            $name = $name.Trim()
            $value = $value.Trim().Trim('"').Trim("'")
            if ($name -and -not [Environment]::GetEnvironmentVariable($name, "Process")) {
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
    }

    if (-not $Json) {
        Write-Host "Planning LALA-next card spending file ingestion."
        Write-Host "Default mode is dry-run plan only."
        Write-Host "Preview mode parses a local CSV/XLSX file but does not mutate DB."
        Write-Host "Apply mode requires ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1."
        Write-Host "DB_DSN value is never printed by this script."
    }

    $resolvedFilePath = $FilePath
    if (-not $resolvedFilePath -and $CsvPath) {
        $resolvedFilePath = $CsvPath
    }

    $toolArgs = @(
        "-m",
        "apps.api.app.tools.run_card_spending_file_ingest",
        "--source-name",
        $SourceName,
        "--dataset-name",
        $DatasetName,
        "--visitor-type",
        $VisitorType,
        "--row-limit",
        "$RowLimit",
        "--connect-timeout",
        "$ConnectTimeout"
    )
    if ($resolvedFilePath) {
        $toolArgs += @("--file-path", $resolvedFilePath)
    }
    if ($RegionMap) {
        $toolArgs += @("--region-map", $RegionMap)
    }
    if ($Json) {
        $toolArgs += "--json"
    }
    if ($Preview) {
        $toolArgs += "--preview"
    }
    if ($Apply) {
        $toolArgs += "--apply"
    }
    if ($Confirm) {
        $toolArgs += @("--confirm", $Confirm)
    }

    & $Python @toolArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Card spending file ingest command failed."
    }
} finally {
    Pop-Location
}
