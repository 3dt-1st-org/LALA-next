# Windows Shared Backend Runbook

Wave 1 runs the FastAPI public API as the shared backend edge.

## Start

```powershell
cd C:\Users\EL035\dataschool\LALA-next
.\scripts\windows\start_api.ps1 -Port 8080
```

The script uses `.venv\Scripts\python.exe` automatically when it exists. Use
`-Python <path-to-python.exe>` to override the interpreter. Use `-KeyVaultUrl`
to set the LALA-next Key Vault URL for the started API process. When a Key Vault
URL is provided, the script loads known LALA-next secrets into process
environment variables without printing their values.

For a live Azure demo:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080 -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -EnableLiveAI -EnableLiveSpeech
```

## Smoke

```powershell
az login
Copy-Item .env.example .env
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080"
```

The smoke script does not print secret values. If Key Vault access is unavailable, set `IOS_API_KEY` as a process-local environment variable before running authenticated checks.

For live Azure OpenAI and Speech validation:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080" -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ -PaidDependency
```

## LAN Exposure

Use `127.0.0.1` for operator-only checks and the Windows host LAN IP for real
device checks. Before sharing the URL, verify:

```powershell
ipconfig
Test-NetConnection -ComputerName 127.0.0.1 -Port 8080
```

If teammates cannot connect from the same network, check Windows Firewall,
VPN/tunnel routing, and whether the API was started with `-HostName 0.0.0.0`.
Do not ask mobile clients to use `localhost`.

## Logs and Restart

For a short demo, a foreground `start_api.ps1` terminal is enough. For a longer
shared session, assign one operator who owns the process and captures logs:

```powershell
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Force .\runtime\logs | Out-Null
.\scripts\windows\start_api.ps1 -Port 8080 *> ".\runtime\logs\api-$stamp.log"
```

`runtime/` is ignored by git. If `/healthz` fails, stop and restart the API
process from the same branch/commit, then rerun smoke before handing the URL
back to teammates.

## Handoff

Share this format with teammates:

```text
Backend URL: http://<host>:8080
Mode: shared LAN dev
Branch/build: main or commit SHA
DB target: skeleton or approved dev DB
Health: /healthz
Ready: /readyz
Known degraded features: DB/Azure live calls are not required in Wave 1
```
