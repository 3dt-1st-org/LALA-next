# Identity Rollout Plan

Wave 1 still protects `/api/v1/*` with static transition credentials:
`API_BEARER_TOKEN` or `IOS_API_KEY`. OAuth/Entra configuration can also be
planned, surfaced in readiness, and used for signed RS256 JWT validation when
the issuer, audience, JWKS URL, and required scopes are configured. Flutter
token acquisition and static credential retirement remain later approval-gated
work.

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
- LALA-next Key Vault secret names for OAuth configuration.
- Static-plus-OAuth transition smoke checks.
- Static auth retirement only after JWT validation, Flutter token acquisition,
  and rollback are approved.

## Key Vault Boundary

OAuth rollout configuration belongs in `lala-next-kv-27db5e`:

- `oauth-issuer`
- `oauth-audience`
- `oauth-jwks-url`
- `oauth-client-id`
- `oauth-required-scopes`

Do not point LALA-next runtime at `onmu-dev-kv-27db5e`. The only ONMU value
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
available until Flutter token acquisition has been implemented and rollback has
been approved.

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
- Do not remove static credentials until API JWT validation, Flutter token
  acquisition, smoke tests, and rollback are approved together.
- Do not commit tenant IDs, client IDs tied to private environments, tokens, or
  screenshots containing credentials.
