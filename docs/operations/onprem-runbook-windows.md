# On-Premises Windows Runbook

Last updated: 2026-06-26 KST

This runbook extends [windows-shared-backend.md](windows-shared-backend.md) for
a longer-lived on-premises Windows API runtime. It does not replace the existing
local smoke scripts.

## Repository Setup

```powershell
cd C:\services\LALA-next
git fetch origin --prune
git switch dev
git pull --ff-only origin dev
uv sync --extra dev
```

Use a service directory owned by the operator team. Do not run the shared API
from a personal Downloads or Desktop path.

## Secret Injection

Create an OS-protected env file outside the repository, for example:

```powershell
C:\services\lala-secrets\api.env
```

The file must be readable only by the service account and operators. It should
use dotenv-style `NAME=value` lines so the Windows start script can import it.
Do not commit it.

Apply restrictive ACLs after creating the file. Replace `<service-account>` with
the actual Windows service identity in the private runbook:

```powershell
$ServiceAccount = "DOMAIN\lala-api"
icacls C:\services\lala-secrets\api.env /inheritance:r
icacls C:\services\lala-secrets\api.env /grant:r "${ServiceAccount}:R" "Administrators:F"
```

Required runtime defaults:

```dotenv
LALA_STATIC_SNAPSHOT_FALLBACK=false
LALA_PUBLIC_CONTEST_ACCESS=false
KEY_VAULT_URL=
```

Set `LALA_PUBLIC_CONTEST_ACCESS=true` only for a time-boxed public review window
and record the owner and expiry in the private runbook.

## Start API

For a foreground rehearsal:

```powershell
New-Item -ItemType Directory -Force .\runtime\logs | Out-Null
.\scripts\windows\start_api.ps1 `
  -HostName 0.0.0.0 `
  -Port 8080 `
  -EnvFile C:\services\lala-secrets\api.env `
  -AccessLogPath .\runtime\logs\api-access.jsonl
```

For live AI or Speech checks, set the required env values locally first and add:

```powershell
-EnableLiveAI -EnableLiveSpeech
```

Do not use `-KeyVaultUrl` for the normal on-premises runtime unless Azure Key
Vault is intentionally retained as a temporary secret source.

## Long-Running Operation

The first acceptable long-running Windows setup can be one of:

- Windows Task Scheduler task running the start script under a service account.
- NSSM or approved service wrapper.
- An approved process manager already used by the team.

The wrapper must:

- set the working directory to the repository root;
- call `scripts\windows\start_api.ps1` with the approved `-EnvFile` path;
- load secrets without printing them;
- restart on failure only after logs are persisted;
- write stdout/stderr to `runtime/logs` or an operator-owned log directory;
- avoid logging request bodies, auth headers, DSNs, or generated content.

## Smoke Checks

Local host check:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080"
```

LAN or reverse-proxy check:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl "https://<onprem-api-host>"
```

DB schema check:

```powershell
.\scripts\windows\verify_db_schema.ps1 `
  -EnvFile C:\services\lala-secrets\api.env `
  -ConnectTimeout 30
```

The ready response must show DB-backed operation before cutover:

- `data.status=ok`
- `db=configured`
- `postgis=configured`

## Logs

For request correlation:

```powershell
.\scripts\windows\inspect_access_log.ps1 `
  -Path .\runtime\logs\api-access.jsonl `
  -RequestId <request-id>
```

The access log must not contain query strings, request bodies, API keys, bearer
tokens, DSNs, or generated docent/audio content.

## Restart And Rollback

Before restart:

1. Save the current commit hash.
2. Confirm Azure API health for rollback.
3. Stop the Windows service or foreground process.
4. Start the API from the intended commit.
5. Rerun smoke checks.

If smoke fails after a cutover, revert DNS to the Azure API target and keep the
on-premises logs for diagnosis.
