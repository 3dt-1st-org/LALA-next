# AWS Secrets Manager team handoff

This is the source-of-truth handoff for LALA runtime secrets and reproducible Flutter builds. It deliberately contains no values, account IDs, private URLs, resource IDs, tokens, DSNs, or personal access data.

## Separation of responsibility

| Consumer | Receives | Must not receive |
| --- | --- | --- |
| EC2 API service role | Individual runtime secrets under `lala-next/` needed by `Settings.from_env()` | GitHub token, team member credentials, developer dotenv files |
| Worker service role | Only the API/worker entries needed for its enabled job | Flutter build key unless it genuinely needs it |
| CI deploy role | SSM deploy permission; it does not read application secret values | `secretsmanager:GetSecretValue` |
| Developer build role | At most `lala-next/naver-map-client-id`, a URL-restricted public client configuration value | `DB_DSN`, OpenAI, Naver Search API secret, Logto management, API bearer, or public-data keys |
| Developer workstation | Local `.env` or `.env.local` only when explicitly needed | A copied production runtime env file |

The API resolves each supported setting in this order: process environment, AWS Secrets Manager (`LALA_AWS_SM_PREFIX`, default `lala-next/`), then legacy Azure Key Vault. Normal AWS operation uses the EC2 instance role and individual Secrets Manager values. `LALA_STATIC_SNAPSHOT_FALLBACK=false` remains the normal state; a snapshot is an outage-only read-only fallback, never normal data.

## Secret inventory and ownership

`scripts/unix/sync_aws_secrets_manager.sh` follows the exact mapping in `apps/api/app/core/config.py`. It stores one scalar value per entry, with names such as `lala-next/openai-api-key` and `lala-next/db-dsn`.

- Authentication: `IOS_API_KEY`, `API_BEARER_TOKEN`, `LOGTO_*`, `OAUTH_*`.
- Data providers: `KAKAO_REST_API_KEY`, `NAVER_*`, `KOPIS_API_KEY`, `PUBLIC_DATA_SERVICE_KEY`, `GYEONGGI_DATA_DREAM_API_KEY`.
- Data/AI: `DB_DSN`, `OPENAI_API_KEY`, `OPENAI_*_MODEL`, `AZURE_SPEECH_*` when speech is enabled.

`NAVER_MAP_CLIENT_ID` is intentionally separate. It is public client build configuration and must be restricted in Naver Cloud Platform to LALA's allowed URLs. It may be made available to the dedicated build role only; it is distinct from the server-side `NAVER_CLIENT_ID` and `NAVER_CLIENT_SECRET` used by governed search ingestion.

Keep toggles and operational choices in the EC2 root-owned runtime env file, not in Secrets Manager: `LALA_PUBLIC_CONTEST_ACCESS`, `LALA_GUEST_ACCESS`, `LALA_ENABLE_LIVE_AI`, `LALA_ENABLE_LIVE_SPEECH`, feature flags, rate limits, `AWS_REGION`, `LALA_AWS_SM_PREFIX`, and `CORS_ALLOW_ORIGINS`.

## One-time operator setup

1. Authenticate AWS CLI with an operator role. Confirm access without printing identity details: `aws sts get-caller-identity --no-cli-pager >/dev/null`.
2. Create the EC2 instance role policy allowing only `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` for `lala-next/*` in the deployment region. Do not grant `ListSecrets`, create, update, or delete to the runtime role.
3. Create a distinct developer build policy allowing only those two actions on `lala-next/naver-map-client-id`. Do not reuse the EC2 role on laptops.
4. Run the value-free inventory first:

   ```bash
   scripts/unix/sync_aws_secrets_manager.sh --source-env /secure/path/lala.env
   ```

5. Review only the reported names and `present`/`absent` status. After an operator confirms the inventory, write it explicitly:

   ```bash
   scripts/unix/sync_aws_secrets_manager.sh \
     --source-env /secure/path/lala.env \
     --include-build-config \
     --apply --confirm SYNC_AWS_SECRETS
   ```

The command uses a mode-600 temporary file and AWS CLI `file://` input so the secret value is not placed in the CLI command line or output. It never prints values. It is safe to re-run: existing entries get a new version and absent dotenv names are left unchanged.

## Team build path

Most Flutter static analysis and unit tests need no secrets:

```bash
cd apps/flutter_app
flutter pub get
flutter analyze
flutter test
```

For an iOS, Android, or Web build that renders Naver map tiles, run the wrapper from the repository root. It supplies only the public API base URL, build SHA, and the URL-restricted Naver Dynamic Map client id:

```bash
scripts/unix/flutter_with_build_env.sh \
  --source-env /path/to/.env.local \
  -- flutter build ios --simulator
```

The wrapper checks an explicitly configured SSM parameter first, then the build-only Secrets Manager entry, and finally the trusted dotenv in an isolated subshell. It does not read or pass `NAVER_CLIENT_SECRET`, API bearer tokens, DB credentials, OpenAI keys, or Logto management secrets. For a non-production endpoint, pass `--api-base-url https://<approved-host>`.

Do not copy a production `.env` into an Orca worktree, a simulator, CI, screenshots, chat, or a pull request. A session that lacks a needed value must report the missing **name** and stop; it must not invent a key, switch to mock data, or weaken an integration check.

## Rotation and incident procedure

1. Rotate one provider credential in its own Secrets Manager entry.
2. Confirm the API process can read configuration through the instance role, then restart only the affected service during an approved window.
3. Check `/readyz` and the affected capability with safe status metadata.
4. Revoke the old provider credential only after the new version is healthy.
5. Record secret **name**, rotation timestamp, owner, and verification result in a private operational ticket. Never record a value or DSN.

For suspected exposure, immediately disable or revoke the upstream credential, rotate the corresponding entry, invalidate local dotenv copies, and review CI and access logs. Never paste a secret into a shell command, commit message, issue, PR comment, or handoff document.

## Pre-merge and session handoff checklist

- [ ] `aws sts get-caller-identity` succeeds for the operator role.
- [ ] EC2 role has read-only access to the exact `lala-next/*` entries it uses.
- [ ] Developer build role has only the restricted map-key entry, or uses a locally managed development key.
- [ ] Plan output was reviewed without values, then apply was explicitly confirmed by an operator.
- [ ] A clean worktree passes `flutter pub get`, `flutter analyze`, and `flutter test` without runtime credentials.
- [ ] A build wrapper invocation works without passing server secrets to Flutter.
- [ ] `/readyz` reports the expected DB-backed normal path after deployment.
- [ ] No secret values, live resource IDs, account IDs, DSNs, or raw dotenv files appear in `git diff`, artifacts, screenshots, or handoff notes.

Implementation sessions may use this document and the scripts' `--help` or plan mode. They must not execute `--apply`, authenticate AWS, deploy, read live secret values, or run real-device validation unless a human explicitly authorizes that separate operation. The controller owns simulator and device verification and records only safe build and response metadata.
