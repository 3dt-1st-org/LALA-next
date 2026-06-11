# Windows Shared Backend Runbook

Wave 1 runs the FastAPI public API as the shared backend edge.

## Start

```powershell
cd C:\Users\EL035\dataschool\LALA-next
.\scripts\windows\start_api.ps1 -Port 8080
```

The script uses `.venv\Scripts\python.exe` automatically when it exists. Use
`-Python <path-to-python.exe>` to override the interpreter.

For a live Azure demo:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080 -EnableLiveAI -EnableLiveSpeech
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
.\scripts\windows\smoke_api.ps1 -BaseUrl "http://127.0.0.1:8080" -PaidDependency
```

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
