# Azure Resources

Wave 1 resources are in resource group `3dt-final-team1` in subscription `27db5ec6-d206-4028-b5e1-6004dca5eeef`.

| Resource | Name | Location | Purpose |
|---|---|---|---|
| Key Vault | `lala-next-kv-27db5e` | `koreacentral` | LALA-next secret storage |
| Azure OpenAI | `lala-next-aoai-27db5e` | `koreacentral` | AI API account |
| Azure OpenAI deployment | `gpt-4o-mini` | `koreacentral` | Wave 1 text generation deployment |

Secrets stored in Key Vault:

- `ios-api-key`
- `azure-openai-endpoint`
- `azure-openai-key`
- `azure-openai-deployment`
- `azure-openai-api-version`

The secret values are intentionally not recorded in this repository.

Live AI calls are opt-in with `LALA_ENABLE_LIVE_AI=true`. This keeps unit tests and basic smoke checks deterministic while still allowing demo runs to use `gpt-4o-mini`.

## Local Configuration

`.env.example` includes non-secret resource identifiers and endpoints. For local development, prefer Azure login plus `KEY_VAULT_URL` so the API can load secrets from Key Vault.

```powershell
az login
Copy-Item .env.example .env
python -m uvicorn apps.api.app.main:app --host 0.0.0.0 --port 8080
```

If Key Vault access is unavailable, set process-local environment variables instead. Do not commit `.env`.
