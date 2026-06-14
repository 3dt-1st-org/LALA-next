# Azure Resources

Wave 1 resources are in resource group `3dt-final-team1` in subscription `27db5ec6-d206-4028-b5e1-6004dca5eeef`.

LALA-next must use only the LALA-next Key Vault, `lala-next-kv-27db5e`, with `KEY_VAULT_URL=https://lala-next-kv-27db5e.vault.azure.net/`. The existing ONMU vault, `onmu-dev-kv-27db5e`, is in the same resource group but is not used by this repository. The API code allowlists the LALA-next vault host and ignores other Key Vault URLs. Secret loading tries Azure SDK credentials first and then falls back to Azure CLI for Windows dev sessions.

Verified on 2026-06-11 with Azure CLI: both `lala-next-kv-27db5e` and `onmu-dev-kv-27db5e` exist in `3dt-final-team1`, but LALA-next runtime still allowlists only the LALA-next vault host. After operator approval, ONMU `int-cors-origins` was copied into the LALA-next vault as `cors-allow-origins` for Flutter Web/browser contract checks. A same-day hash comparison showed the ONMU `int-cors-origins` value and LALA `cors-allow-origins` value are identical. Other ONMU dev/db/oauth/minio/redis/social-provider names were not wired into LALA-next because they belong to ONMU runtime ownership or project-specific identity flows.

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

Optional bearer transition secret:

- `api-bearer-token`

Optional live database rollout secret:

- `db-dsn`

Optional Flutter Web/browser CORS secret:

- `cors-allow-origins`

Optional OAuth/Entra identity rollout configuration secrets:

- `oauth-issuer`
- `oauth-audience`
- `oauth-jwks-url`
- `oauth-client-id`
- `oauth-required-scopes`

The secret values are intentionally not recorded in this repository.

To review whether any ONMU Key Vault values should be reused, run the
non-mutating reuse plan:

```bash
scripts/unix/plan_key_vault_reuse.sh
```

```powershell
.\scripts\windows\plan_key_vault_reuse.ps1
```

The plan currently allows only `int-cors-origins` as a reviewed source for the
LALA `cors-allow-origins` setting. It rejects ONMU DB, OAuth/social-provider,
storage, Redis, API token, Azure OpenAI, and Speech values as LALA runtime
inputs.

Live AI calls are opt-in with `LALA_ENABLE_LIVE_AI=true`. Live text-to-speech calls are opt-in with `LALA_ENABLE_LIVE_SPEECH=true`. This keeps unit tests and basic smoke checks deterministic while still allowing demo runs to use `gpt-4o-mini` and Azure Speech.

## Azure Verification

Use the dedicated Azure check when you need to prove the shared backend is pointed at LALA-next resources rather than ONMU resources:

```bash
az login
scripts/unix/verify_azure_resources.sh
```

```powershell
az login
.\scripts\windows\verify_azure_resources.ps1
```

The script verifies:

- Subscription `27db5ec6-d206-4028-b5e1-6004dca5eeef`.
- Resource group `3dt-final-team1`.
- Key Vault `lala-next-kv-27db5e`.
- Expected LALA-next secret names, without printing values.
- Optional transition, DB, CORS, and OAuth/Entra configuration secret names,
  without printing values.
- Azure OpenAI account `lala-next-aoai-27db5e`.
- Azure OpenAI deployment `gpt-4o-mini`.
- Azure Speech account `lala-next-speech-27db5e`.
- ONMU vault name separation.

To verify PostgreSQL rollout readiness, including the optional `db-dsn` secret
name and Azure Database for PostgreSQL Flexible Server target, run:

```bash
scripts/unix/verify_db_resources.sh
```

```powershell
.\scripts\windows\verify_db_resources.ps1
```

Use `-RequireDatabase` when the database target is expected to exist and the
check should fail if any DB rollout prerequisite is missing.

## Local Configuration

`.env.example` includes non-secret resource identifiers and endpoints. For local development, prefer Azure login plus the LALA-next `KEY_VAULT_URL` so the API can load secrets from `lala-next-kv-27db5e`.

```powershell
az login
Copy-Item .env.example .env
python -m uvicorn apps.api.app.main:app --host 0.0.0.0 --port 8080 --no-access-log
```

If Key Vault access is unavailable, set process-local environment variables instead. Do not commit `.env`.
