# Azure Resources

Wave 1 resources are in resource group `3dt-final-team1` in subscription `27db5ec6-d206-4028-b5e1-6004dca5eeef`.

LALA-next must use only the LALA-next Key Vault, `lala-next-kv-27db5e`, with `KEY_VAULT_URL=https://lala-next-kv-27db5e.vault.azure.net/`. The existing ONMU vault, `onmu-dev-kv-27db5e`, is in the same resource group but is not used by this repository. The API code allowlists the LALA-next vault host and ignores other Key Vault URLs. Secret loading tries Azure SDK credentials first and then falls back to Azure CLI for Windows dev sessions.

Verified on 2026-06-11 with Azure CLI: both `lala-next-kv-27db5e` and `onmu-dev-kv-27db5e` exist in `3dt-final-team1`, but their secret name sets are separate. LALA-next stores only the `azure-openai-*`, `azure-speech-*`, and `ios-api-key` names listed below; ONMU stores ONMU dev/db/oauth/minio names and is intentionally not referenced by the API allowlist.

| Resource | Name | Location | Purpose |
|---|---|---|---|
| Key Vault | `lala-next-kv-27db5e` | `koreacentral` | LALA-next secret storage |
| Azure OpenAI | `lala-next-aoai-27db5e` | `koreacentral` | AI API account |
| Azure OpenAI deployment | `gpt-4o-mini` | `koreacentral` | Wave 1 text generation deployment |
| Azure Speech | `lala-next-speech-27db5e` | `koreacentral` | Wave 1 opt-in text-to-speech account |

Secrets stored in Key Vault:

- `ios-api-key`
- `azure-openai-endpoint`
- `azure-openai-key`
- `azure-openai-deployment`
- `azure-openai-api-version`
- `azure-speech-key`
- `azure-speech-region`
- `azure-speech-endpoint`

The secret values are intentionally not recorded in this repository.

Live AI calls are opt-in with `LALA_ENABLE_LIVE_AI=true`. Live text-to-speech calls are opt-in with `LALA_ENABLE_LIVE_SPEECH=true`. This keeps unit tests and basic smoke checks deterministic while still allowing demo runs to use `gpt-4o-mini` and Azure Speech.

## Azure Verification

Use the dedicated Azure check when you need to prove the shared backend is pointed at LALA-next resources rather than ONMU resources:

```powershell
az login
.\scripts\windows\verify_azure_resources.ps1
```

The script verifies:

- Subscription `27db5ec6-d206-4028-b5e1-6004dca5eeef`.
- Resource group `3dt-final-team1`.
- Key Vault `lala-next-kv-27db5e`.
- Expected LALA-next secret names, without printing values.
- Azure OpenAI account `lala-next-aoai-27db5e`.
- Azure OpenAI deployment `gpt-4o-mini`.
- Azure Speech account `lala-next-speech-27db5e`.
- ONMU vault name separation.

## Local Configuration

`.env.example` includes non-secret resource identifiers and endpoints. For local development, prefer Azure login plus the LALA-next `KEY_VAULT_URL` so the API can load secrets from `lala-next-kv-27db5e`.

```powershell
az login
Copy-Item .env.example .env
python -m uvicorn apps.api.app.main:app --host 0.0.0.0 --port 8080
```

If Key Vault access is unavailable, set process-local environment variables instead. Do not commit `.env`.
