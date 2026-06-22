param(
    [switch]$Preview,
    [switch]$Apply,
    [string]$Confirm = "",
    [string]$Category = "all",
    [int]$Limit = 10,
    [int]$ItemsPerPlace = 10,
    [string]$Provider = "naver_blog",
    [string]$WeekStart = "",
    [int]$Timeout = 10,
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
    Write-Host "Planning LALA-next review/mention preprocessing."
    Write-Host "Default mode is dry-run plan only."
    Write-Host "Preview mode calls Naver Blog Search but does not mutate DB."
    Write-Host "Apply mode requires ALLOW_REVIEW_MENTION_INGEST_APPLY=1."
    Write-Host "DB_DSN, NAVER_CLIENT_ID, and NAVER_CLIENT_SECRET values are never printed by this script."
}

$toolArgs = @(
    "-m", "apps.api.app.tools.run_review_mention_ingest",
    "--category", $Category,
    "--limit", "$Limit",
    "--items-per-place", "$ItemsPerPlace",
    "--provider", $Provider,
    "--timeout", "$Timeout",
    "--connect-timeout", "$ConnectTimeout"
)
if ($WeekStart) {
    $toolArgs += @("--week-start", $WeekStart)
}
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
