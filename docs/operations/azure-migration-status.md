# Azure Migration Status

Last updated: 2026-06-20 KST

This note records the shared dev migration path without exposing live Key Vault
URLs, database passwords, bearer tokens, or generated Azure resource names.
Use GitHub environment variables, GitHub environment secrets, and Azure CLI
queries to resolve live names during operations.

## Completed

- Azure Container Apps, Azure Database for PostgreSQL Flexible Server, Key
  Vault, Application Insights, Log Analytics, managed identity, and ACR were
  provisioned in the same Azure region.
- GitHub Actions deploys the API from the `dev` branch with OIDC. No branch
  protection rule was added.
- `LALA_PUBLIC_DEMO_MODE` is fixed to `false` for shared dev and should remain
  `false` for production and review deployments.
- The normal runtime path is PostgreSQL plus Key Vault plus reviewed ingest,
  scoring, and RAG jobs.
- Bundled static data is documented only as an offline, read-only snapshot
  fallback for DB outage handling or isolated local checks.
- The API client transition token is stored as the GitHub `dev` environment
  secret `AZURE_API_BEARER_TOKEN`, then written by Bicep into Key Vault as
  `api-bearer-token`.
- The PostgreSQL administrator password is stored as the GitHub `dev`
  environment secret `AZURE_POSTGRES_ADMIN_PASSWORD`, then used by Bicep to
  create the Key Vault `db-dsn` secret.
- The `db-dsn` secret URL-encodes the PostgreSQL password before composing the
  DSN. This keeps generated passwords with URL-sensitive characters from
  breaking runtime DB readiness.
- Canonical SQL was applied manually to the shared dev PostgreSQL target after
  previewing the SQL plan. The schema verifier passed for all canonical schemas,
  tables, views, and required extensions.

## Manual Data Rollout Order

Run these steps from a trusted operator machine. Keep secrets in process-local
environment variables or GitHub/Azure secret stores only.

1. Resolve the live PostgreSQL host and API FQDN with Azure CLI.
2. Temporarily allow the operator IP on the PostgreSQL firewall.
3. Build `DB_DSN` in the shell without printing it.
4. Preview canonical SQL:

```bash
scripts/unix/apply_canonical_sql.sh --json --connect-timeout 30 --python .venv/bin/python
```

5. Apply canonical SQL:

```bash
ALLOW_CANONICAL_SQL_APPLY=1 \
  scripts/unix/apply_canonical_sql.sh \
  --apply \
  --confirm APPLY_CANONICAL_SQL \
  --json \
  --connect-timeout 30 \
  --python .venv/bin/python
```

6. Verify canonical schema:

```bash
scripts/unix/verify_db_schema.sh --json --connect-timeout 30 --python .venv/bin/python
```

7. Ingest official static/dynamic sources into the canonical DB. Start with the
   official Tour API path, then add Culture Info, KOPIS, and card-spending
   files as source access and row volumes are verified.

```bash
scripts/unix/plan_tour_api_ingest.sh --preview --rows 20 --python .venv/bin/python
ALLOW_TOUR_API_INGEST_APPLY=1 \
  scripts/unix/plan_tour_api_ingest.sh \
  --apply \
  --confirm APPLY_TOUR_API_INGEST \
  --rows 200 \
  --python .venv/bin/python
```

8. Recompute local-value score snapshots after places and source signals exist:

```bash
scripts/unix/plan_place_score_batch.sh --preview --limit 20 --python .venv/bin/python
ALLOW_PLACE_SCORE_BATCH_APPLY=1 \
  scripts/unix/plan_place_score_batch.sh \
  --apply \
  --confirm APPLY_PLACE_SCORE_BATCH \
  --python .venv/bin/python
```

9. Build the RAG index from static and dynamic canonical data:

```bash
scripts/unix/plan_rag_index.sh --preview --source all --limit 20 --python .venv/bin/python
ALLOW_RAG_INDEX_APPLY=1 \
  scripts/unix/plan_rag_index.sh \
  --apply \
  --confirm APPLY_RAG_INDEX \
  --source all \
  --embedding-method local-hash \
  --python .venv/bin/python
```

10. Smoke the deployed API with the transition bearer token. `/readyz` should
    report configured client auth and DB readiness after the runtime has picked
    up the refreshed Key Vault values.

## Still Open

- Re-run the Azure dev deployment after any Bicep or GitHub secret change so
  Key Vault secrets and the Container App revision stay aligned.
- Deploy Flutter web with the same transition bearer token only from deployment
  secrets until OAuth or a backend-for-frontend proxy replaces the static token.
- Move `api.lala-next.cloud` from the current placeholder target to the Azure
  Container App custom domain after DNS access is available.
- Remove the temporary operator PostgreSQL firewall rule after data rollout is
  complete.
- Add production-grade identity, private networking, and observability gates
  before treating the environment as durable production hosting.
