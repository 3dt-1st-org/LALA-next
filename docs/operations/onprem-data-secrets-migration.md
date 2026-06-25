# On-Premises Data And Secrets Migration

Last updated: 2026-06-26 KST

This document describes how to move LALA's database and runtime configuration
from Azure-managed services to on-premises equivalents. It is a runbook draft:
execute these steps only during an approved maintenance or rehearsal window.

## Safety Rules

- Do not print or commit `DB_DSN`, passwords, tokens, Key Vault URLs, or live
  resource names.
- Use placeholders in issue comments and Markdown.
- Keep Azure healthy until rollback is no longer needed.
- Restore into a rehearsal database before restoring into the final on-premises
  runtime database.
- Keep `LALA_STATIC_SNAPSHOT_FALLBACK=false` for normal runtime checks.

## Database Export From Azure

Resolve connection details from Azure CLI or the private runbook. Build the
source DSN in the operator shell without echoing it.

Use `pg_dump` from the same PostgreSQL major version as the Azure source server
or newer. Record the source server major version and dump client version in the
private runbook, but do not commit live server names or DSNs.

Recommended export shape:

```bash
pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file runtime/backups/lala-azure-<date>.dump \
  "$AZURE_SOURCE_DSN"
```

Store the dump in an ignored path or approved backup location. Do not commit
dump files.

## Restore To On-Premises PostgreSQL

Restore into a clean rehearsal database first:

```bash
createdb lala_rehearsal
pg_restore \
  --dbname "$ONPREM_REHEARSAL_DSN" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  runtime/backups/lala-azure-<date>.dump
```

The restore operator must either be able to create required extensions and
schemas, or a database administrator must pre-create `pgcrypto`, `postgis`, and
`vector` in the target database. Use a short-lived restore/operator credential
for this step. Do not reuse a database-owner credential as the long-lived API
`DB_DSN`.

Then verify:

```bash
DB_DSN="$ONPREM_REHEARSAL_DSN" \
  scripts/unix/verify_db_schema.sh \
  --json \
  --connect-timeout 30 \
  --python .venv/bin/python
```

If canonical schema verification fails, inspect the missing extension/schema
first. Do not patch production data ad hoc.

## Canonical SQL Fallback

If the restore target is empty or intentionally rebuilt, preview canonical SQL:

```bash
scripts/unix/apply_canonical_sql.sh --json --connect-timeout 30 --python .venv/bin/python
```

Apply only after review:

```bash
ALLOW_CANONICAL_SQL_APPLY=1 \
  scripts/unix/apply_canonical_sql.sh \
  --apply \
  --confirm APPLY_CANONICAL_SQL \
  --json \
  --connect-timeout 30 \
  --python .venv/bin/python
```

Windows equivalents are documented in
[windows-shared-backend.md](windows-shared-backend.md).

## Secret Inventory Migration

Build a private inventory with three columns:

| Secret name | On-premises env name | Owner |
|---|---|---|
| `db-dsn` | `DB_DSN` | backend operator |
| `public-data-service-key` | `PUBLIC_DATA_SERVICE_KEY` | data/API operator |
| `kopis-api-key` | `KOPIS_API_KEY` | data/API operator |
| `naver-client-id` | `NAVER_CLIENT_ID` | API operator |
| `naver-client-secret` | `NAVER_CLIENT_SECRET` | API operator |
| `kakao-javascript-key` | `KAKAO_JAVASCRIPT_KEY` | frontend/API operator |
| `kakao-rest-api-key` | `KAKAO_REST_API_KEY` | API operator |
| `azure-openai-endpoint` | `AZURE_OPENAI_ENDPOINT` | AI operator |
| `azure-openai-key` | `AZURE_OPENAI_KEY` | AI operator |
| `azure-openai-deployment` | `AZURE_OPENAI_DEPLOYMENT` | AI operator |
| `azure-openai-docent-deployment` | `AZURE_OPENAI_DOCENT_DEPLOYMENT` | AI operator |
| `azure-openai-review-batch-deployment` | `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` | AI operator |
| `azure-openai-api-version` | `AZURE_OPENAI_API_VERSION` | AI operator |
| `azure-speech-region` | `AZURE_SPEECH_REGION` | speech operator |
| `azure-speech-endpoint` | `AZURE_SPEECH_ENDPOINT` | speech operator |
| `azure-speech-key` | `AZURE_SPEECH_KEY` | speech operator |

The tracked repository may list secret names, but never the values.

## On-Premises Env File Rules

- Store env files outside the repository.
- Restrict read access to the service account and operators.
- Keep a separate smoke credential if public contest access is disabled.
- Keep `KEY_VAULT_URL` empty unless Azure Key Vault remains a temporary source.
- Rotate `DB_DSN` after a failed or aborted migration rehearsal if it was shared
  too broadly.

## Backup And Restore Routine

Before public cutover, configure a repeatable backup job outside git:

- daily custom-format `pg_dump` for the LALA database;
- 7 to 14 days of local encrypted or access-restricted retention;
- one weekly off-host copy to an approved backup location;
- monthly restore drill into a disposable database;
- additional restore drill before contest/review windows or major data refreshes.

The restore drill must rerun `verify_db_schema.sh` or
`verify_db_schema.ps1`, then start an API against the rehearsal DSN and pass
`/readyz` plus the API smoke matrix. A backup that has never been restored is
not accepted as migration evidence.

## Post-Restore Data Checks

Run read-only checks before starting the public API:

```bash
scripts/unix/verify_db_schema.sh --json --connect-timeout 30 --python .venv/bin/python
```

Then start the API and verify:

```bash
curl -fsS http://127.0.0.1:8080/readyz
scripts/unix/smoke_api_matrix.sh --base-url http://127.0.0.1:8080
```

Expected readiness for cutover rehearsal:

- `data.status=ok`
- `db=configured`
- `postgis=configured`
- public-data key configured when weather fallback is expected
- no static snapshot fallback in normal operation

## Data Freshness After Restore

After restore, schedule or manually rerun approved refresh jobs as needed:

- Tour API ingest.
- KCISA culture info ingest.
- KOPIS ingest.
- Card spending file ingest when a new approved file exists.
- Weather observation refresh.
- Place score batch.
- RAG index refresh.

Each guarded apply should record `ops.job_runs` evidence. Do not rely on a DB
restore alone if the judging/demo window needs fresh weather or source rows.
