param(
    [switch]$Preview,
    [switch]$Apply,
    [string]$Confirm = "",
    [string]$Category = "all",
    [int]$Limit = 250,
    [int]$ConnectTimeout = 5,
    [string]$Python = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "_common.ps1")

$root = Get-RepoRoot
$pythonExe = Select-Python -Python $Python
Set-Location $root

if (-not $Json) {
    Write-Host "Planning LALA-next review attribute scoring."
    Write-Host "Default mode is dry-run plan only."
    Write-Host "Preview mode reads DB aggregates but does not mutate DB."
    Write-Host "Apply mode requires ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1."
    Write-Host "DB_DSN value is never printed by this script."
}

$toolArgs = @(
    "-m", "apps.api.app.tools.run_review_attribute_batch",
    "--category", $Category,
    "--limit", "$Limit",
    "--connect-timeout", "$ConnectTimeout"
)
if ($Json) {
    $toolArgs += "--json"
}
if ($Preview) {
    $toolArgs += "--preview"
}
if ($Apply) {
    $toolArgs += @("--apply", "--confirm", $Confirm)
}

& $pythonExe @toolArgs
exit $LASTEXITCODE
