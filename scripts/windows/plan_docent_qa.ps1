param(
    [switch]$Preview,
    [string]$Category = "all",
    [int]$Limit = 40,
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
    Write-Host "Planning LALA-next representative docent manual QA."
    Write-Host "Default mode is dry-run plan only."
    Write-Host "Preview mode reads DB/RAG signals but does not mutate DB or generate scripts."
    Write-Host "DB_DSN value is never printed by this script."
}

$toolArgs = @(
    "-m", "apps.api.app.tools.plan_docent_qa",
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

& $pythonExe @toolArgs
exit $LASTEXITCODE
