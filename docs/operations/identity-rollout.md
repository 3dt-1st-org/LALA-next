# Identity Rollout Plan

Wave 1 still protects `/api/v1/*` with static transition credentials:
`API_BEARER_TOKEN` or `IOS_API_KEY`. OAuth/Entra configuration can also be
planned, surfaced in readiness, and used for signed RS256 JWT validation when
the issuer, audience, JWKS URL, and required scopes are configured. Flutter
token acquisition via the Logto dart SDK is implemented (merged PRs e9abd91,
c701b99, e9a3566); static credential retirement and external activation remain
approval-gated work.

Generate the non-mutating plan:

```bash
scripts/unix/plan_identity_rollout.sh
```

```powershell
.\scripts\windows\plan_identity_rollout.ps1
```

The plan does not create Entra app registrations, Key Vault secrets, Flutter
tokens, or client secrets. It only prints proposed commands and approval gates
for:

- Entra API app registration naming.
- Delegated API scope review.
- Flutter public client app registration review.
- OAuth/Logto secret names (AWS Secrets Manager in operational profiles; Azure
  Key Vault in local/ci).
- Static-plus-OAuth transition smoke checks.
- Static auth retirement only after JWT validation, Logto SDK token
  acquisition is activated for the rollout build, and rollback are approved.

## OAuth Secret Boundary

In operational profiles (`api`/`worker`), OAuth/Logto secrets resolve from
**AWS Secrets Manager** with secret ids prefixed `lala-next/`
(e.g. `lala-next/logto-endpoint`, `lala-next/logto-api-audience`). The API reads
them fail-closed via `resolve_runtime_secret(..., key_vault_loader=None)` — there
is **no Key Vault fallback** in `api`/`worker` profiles. Azure Key Vault
(`lala-key-vault`) is a `local`/`ci`-only developer fallback, per the
`_env_or_secret` profile branching in `config.py`; it is **not** the operational
secret source.

The authoritative identity is Logto-derived: `LOGTO_ENDPOINT` +
`LOGTO_API_AUDIENCE` make the API derive the issuer (`<endpoint>/oidc`) and JWKS
URL (`<endpoint>/oidc/jwks`) via `derive_logto_oidc_urls`, so
issuer/audience/JWKS are NOT separately registered. The Logto secret ids below
are the AWS Secrets Manager secret names used in operational profiles:

- `logto-endpoint` (authoritative; issuer + JWKS are derived from it)
- `logto-api-audience` (authoritative)
- `logto-management-endpoint` (optional; falls back to `logto-endpoint`)
- Flutter client identifiers + redirect URIs (`LOGTO_WEB_APP_ID` /
  `LOGTO_NATIVE_APP_ID`), configured via dart-defines / build config rather than
  the API secret store.

Legacy `oauth-*` secrets remain available as a fallback only when the Logto
endpoint is not set:

- `oauth-issuer`
- `oauth-audience`
- `oauth-jwks-url`
- `oauth-client-id`
- `oauth-required-scopes`

Do not point LALA-next runtime at `onmu-source-vault`. The only ONMU value
currently reused is the optional browser CORS origin list, already copied into
the LALA vault as `cors-allow-origins` and verified to match by hash on
2026-06-11. ONMU DB URLs, API tokens, social-provider secrets, Redis, and MinIO
settings are project-specific and are not LALA runtime inputs.

Use `scripts/unix/plan_key_vault_reuse.sh` or
`scripts/windows/plan_key_vault_reuse.ps1` when this boundary needs to be
reviewed again. The plan is non-mutating and does not read or print secret
values.

## Readiness States

`/readyz.data.checks.client_identity` reports:

- `missing`: neither static auth nor complete OAuth configuration is present.
- `static`: static bearer/API-key auth is configured.
- `transition`: static auth and complete OAuth configuration are both present.
- `oauth-configured`: OAuth configuration is present without static auth.

`/readyz.data.checks.jwt_validation` reports `configured` when API-side JWT
validation has enough issuer, audience, JWKS URL, and required-scope
configuration to validate presented bearer JWTs. In `oauth-configured` mode,
`/api/v1/*` requires a valid signed JWT with all required scopes.

During the transition window, keep `API_BEARER_TOKEN` or `IOS_API_KEY`
available until the Logto SDK token acquisition path has been activated for the
rollout build and rollback has been approved.

For operator smoke with an already-issued OAuth/Entra token, set
`LALA_SMOKE_BEARER_TOKEN` in the smoke-shell environment. Do not reuse
`API_BEARER_TOKEN` for this purpose unless you are intentionally testing the
static transition token path.

Before real Entra registrations exist, use `scripts/unix/smoke_oauth_jwt.sh` or
`scripts/windows/smoke_oauth_jwt.ps1` to prove the API verifier end to end with
local-only test keys and a local JWKS server.

## Approval Gates

- Do not create Entra registrations without owner approval.
- Do not add Flutter client secrets; Flutter is a public client.
- Do not remove static credentials until API JWT validation, activated Logto
  SDK token acquisition, smoke tests, and rollback are approved together.
- Do not commit tenant IDs, client IDs tied to private environments, tokens, or
  screenshots containing credentials.
