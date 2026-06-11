# Live Azure Smoke - 2026-06-11

This note records the controller-session live dependency smoke for the Wave 1
LALA-next backend. It intentionally excludes secret values and generated audio
content.

## Scope

The smoke used the LALA-next-only Azure resources in resource group
`3dt-final-team1`:

- Key Vault: `lala-next-kv-27db5e`
- Azure OpenAI account: `lala-next-aoai-27db5e`
- Azure OpenAI deployment: `gpt-4o-mini`
- Azure Speech account: `lala-next-speech-27db5e`

The ONMU Key Vault `onmu-dev-kv-27db5e` exists in the same resource group, but
was not used.

## Commands

The API was started on a temporary local port with LALA-next Key Vault secret
preload and live AI/Speech enabled:

```powershell
.\scripts\windows\start_api.ps1 `
  -Port 8093 `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ `
  -EnableLiveAI `
  -EnableLiveSpeech
```

The paid smoke was run against the temporary API process:

```powershell
.\scripts\windows\smoke_api.ps1 `
  -BaseUrl http://127.0.0.1:8093 `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/ `
  -PaidDependency
```

## Result

Passed.

Observed checks:

- `GET /healthz`
- `GET /readyz`
- `GET /openapi.json`
- `GET /api/v1/places`
- `GET /api/v1/weather`
- `GET /api/v1/plans/intervention`
- `POST /api/v1/docents/script`
- paid `POST /api/v1/docents/script` backed by Azure OpenAI
- paid `POST /api/v1/docents/audio` returning `audio/mpeg` bytes

After the smoke, the temporary API process was stopped and no LALA-next uvicorn
process remained.
