# Azure Resource Boundary

This repository intentionally does not record live Azure resource names,
subscription ids, Key Vault URLs, or service endpoints. Keep those identifiers
in ignored local environment files, deployment settings, or a team-private
runbook.

## Runtime Boundary

LALA must use a LALA-owned Key Vault when `KEY_VAULT_URL` is configured. Do not
point the API, workers, or smoke scripts at ONMU runtime vaults.

The API and helper scripts validate Key Vault URLs with these public rules:

- URL scheme must be `https`.
- Host must be an Azure Key Vault host.
- Host must not be an ONMU vault host.
- If `LALA_ALLOWED_KEY_VAULT_HOSTS` is set, the host must be listed there.

The only ONMU-derived value currently considered reusable is the optional CORS
origin list copied into LALA as `cors-allow-origins`. ONMU DB URLs, OAuth/social
provider values, API tokens, Redis, MinIO, Azure OpenAI, and Speech secrets are
not LALA runtime inputs.

## Secret Names

Expected LALA Key Vault secret names:

- `ios-api-key`
- `azure-openai-endpoint`
- `azure-openai-key`
- `azure-openai-deployment`
- `azure-openai-api-version`
- `azure-speech-key`
- `azure-speech-region`
- `azure-speech-endpoint`

Optional secret names:

- `api-bearer-token`
- `db-dsn`
- `cors-allow-origins`
- `oauth-issuer`
- `oauth-audience`
- `oauth-jwks-url`
- `oauth-client-id`
- `oauth-required-scopes`
- `kakao-rest-api-key`
- `kakao-javascript-key`
- `kakao-redirect-uri`
- `naver-client-id`
- `naver-client-secret`
- `kopis-api-key`
- `public-data-service-key`
- `gyeonggi-data-dream-api-key`

Secret values are never recorded in this repository.

## Verification

Use live Azure verification only after loading the real identifiers from a
private source:

```bash
export LALA_AZURE_SUBSCRIPTION_ID=<subscription-id>
export LALA_AZURE_RESOURCE_GROUP=<resource-group>
export LALA_KEY_VAULT_NAME=<key-vault-name>
export LALA_AZURE_OPENAI_ACCOUNT_NAME=<azure-openai-account>
export LALA_AZURE_SPEECH_ACCOUNT_NAME=<azure-speech-account>
export ONMU_KEY_VAULT_NAME=<onmu-comparison-vault>
scripts/unix/verify_azure_resources.sh
```

```powershell
$env:LALA_AZURE_SUBSCRIPTION_ID = "<subscription-id>"
$env:LALA_AZURE_RESOURCE_GROUP = "<resource-group>"
$env:LALA_KEY_VAULT_NAME = "<key-vault-name>"
$env:LALA_AZURE_OPENAI_ACCOUNT_NAME = "<azure-openai-account>"
$env:LALA_AZURE_SPEECH_ACCOUNT_NAME = "<azure-speech-account>"
$env:ONMU_KEY_VAULT_NAME = "<onmu-comparison-vault>"
.\scripts\windows\verify_azure_resources.ps1
```

To verify PostgreSQL rollout readiness:

```bash
scripts/unix/verify_db_resources.sh
```

```powershell
.\scripts\windows\verify_db_resources.ps1
```

Use `--require-database` or `-RequireDatabase` only when the database target is
expected to exist.

## Local Configuration

Copy `.env.example` to `.env` and fill values locally. The example file keeps
resource endpoints blank on purpose. If Key Vault access is unavailable, set
process-local environment variables instead. Do not commit `.env`.
