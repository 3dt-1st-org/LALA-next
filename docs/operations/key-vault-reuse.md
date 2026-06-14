# Key Vault Reuse Plan

LALA-next must run from `lala-next-kv-27db5e`. The ONMU vault
`onmu-dev-kv-27db5e` can be used only as a reviewed source for specific values
that are copied into the LALA-next vault. Do not point `KEY_VAULT_URL` at the
ONMU vault in LALA-next runtime.

Generate the non-mutating reuse plan:

```bash
scripts/unix/plan_key_vault_reuse.sh
```

```powershell
.\scripts\windows\plan_key_vault_reuse.ps1
```

The plan does not read, print, copy, or set secret values. It only classifies
which ONMU secret names are candidates and which categories must stay out of
LALA-next.

## Current Candidate

The only current reuse candidate is:

| Source ONMU secret | Target LALA secret | Use | Gate |
|---|---|---|---|
| `int-cors-origins` | `cors-allow-origins` | Browser CORS origin list for Flutter Web and local smoke | Copy only after owner approval, then verify without printing the value |

After a copy, verify with secret-name presence, hash comparison, or a CORS smoke
that does not expose the value:

```bash
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080 --cors-origin http://localhost:3000
```

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080 -CorsOrigin http://localhost:3000
```

## Rejected Categories

Do not reuse ONMU values in these categories:

- DB, database, PostgreSQL, or DSN values.
- OAuth/OIDC, client secret, or social-provider values.
- MinIO, storage, Blob, Redis, or cache values.
- API keys, bearer tokens, webhooks, or shared-access keys.
- Azure OpenAI, Speech, or Cognitive Services values.

LALA-next has separate Azure OpenAI and Speech resources and needs its own DB,
identity, storage, and integration credentials. Cross-wiring ONMU values here
would make the migration harder to reason about and harder to roll back.
