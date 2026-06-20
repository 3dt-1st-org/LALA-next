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
- `LALA_STATIC_SNAPSHOT_FALLBACK` is fixed to `false` for shared dev and should
  remain `false` for production and review deployments.
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
- Tour API place ingestion was applied for Gyeonggi (`areaCode=31`) and Seoul
  (`areaCode=1`) across attractions, culture venues, events, and restaurants.
  The current shared dev DB has 2,636 Tour API places: 1,294 Gyeonggi rows and
  1,342 Seoul rows.
- Official image coverage after Tour API ingestion is 2,327 rows: 1,135 Gyeonggi
  rows and 1,192 Seoul rows. Rows without official images should leave the image
  slot collapsed rather than using mock images.
- Fair Trade Commission franchise brand references were ingested from the public
  data API for 2025 into `economy.franchise_brands`: 11,712 rows after source
  duplicate collapse.
- Franchise/small-merchant identity matching was applied for the current
  restaurant slice: 1,000 rows in `analytics.place_business_identity`
  (`franchise_store=2`, `local_small_chain=34`, `independent_local=964`).
  Brand-level references with zero active franchise stores are excluded from
  franchise evidence, and restaurants that do not match loaded franchise
  references are classified as independent local instead of remaining unknown.
- `local-value-v2` score snapshots were generated for all 2,636 places.
  Historical `local-value-v1` and earlier `local-value-v2` snapshots remain in
  the table for audit/history; API reads select the latest score row and live
  `/api/v1/places` verified `formula_version=local-value-v2`.
- RAG knowledge chunks were regenerated for all 2,636 places with the
  local-hash embedding path.
- The production Flutter web build at `lala-next.cloud` was redeployed with
  `https://api.lala-next.cloud` as the API base URL and the transition bearer
  token from deployment secrets. Verification showed `healthz`, `readyz`, and
  `/api/v1/places` returning HTTP 200 from the vanity API domain, with DB-backed
  place rows and official image URLs.
- The extended API matrix smoke for `https://api.lala-next.cloud` covers 37
  route variants across place category/language filters, multiple map centers,
  daily planning, weather intervention, docent script categories, and docent
  `audio/mpeg` output.
- The Azure dev deploy workflow now runs the same authenticated `smoke_api.sh`
  and `smoke_api_matrix.sh` checks after every Container App revision update.
  The first workflow-gated matrix smoke passed on run `27857289530`; an
  operator-run matrix smoke against `https://api.lala-next.cloud` also passed
  with `checked=37`.
- Gabia DNS has been updated for the API vanity domain. `@` and `www` remain on
  Vercel, while `api` is a CNAME to the Azure Container Apps FQDN and
  `asuid.api` is the Azure custom-domain TXT validation record.
- Azure Container Apps custom hostname registration, managed certificate
  issuance, and SNI binding are complete for `api.lala-next.cloud`.
- The `dev` GitHub environment stores `AZURE_API_CUSTOM_DOMAIN_NAME` and
  `AZURE_API_CUSTOM_DOMAIN_CERTIFICATE_ID` as environment variables. The Azure
  deploy workflow passes them into Bicep so future dev deployments preserve the
  `api.lala-next.cloud` custom-domain binding instead of resetting ingress to
  the default Azure Container Apps FQDN only.

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

8. Ingest Fair Trade Commission brand-level franchise references, then classify
   restaurant business identity. Preview first; apply only with guarded process
   flags from a trusted operator shell.

```bash
scripts/unix/plan_franchise_reference_ingest.sh \
  --preview \
  --year 2025 \
  --rows 20 \
  --python .venv/bin/python

ALLOW_FRANCHISE_REFERENCE_INGEST_APPLY=1 \
  scripts/unix/plan_franchise_reference_ingest.sh \
  --apply \
  --confirm APPLY_FRANCHISE_REFERENCE_INGEST \
  --year 2025 \
  --rows 0 \
  --python .venv/bin/python

ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY=1 \
  scripts/unix/plan_franchise_identity_batch.sh \
  --apply \
  --confirm APPLY_FRANCHISE_IDENTITY_BATCH \
  --category restaurant \
  --limit 5000 \
  --python .venv/bin/python
```

9. Recompute local-value score snapshots after places and source signals exist:

```bash
scripts/unix/plan_place_score_batch.sh --preview --limit 20 --python .venv/bin/python
ALLOW_PLACE_SCORE_BATCH_APPLY=1 \
  scripts/unix/plan_place_score_batch.sh \
  --apply \
  --confirm APPLY_PLACE_SCORE_BATCH \
  --category all \
  --limit 3000 \
  --python .venv/bin/python
```

10. Rebuild RAG chunks after score regeneration:

```bash
ALLOW_RAG_INDEX_APPLY=1 \
  scripts/unix/plan_rag_index.sh \
  --apply \
  --confirm APPLY_RAG_INDEX \
  --source all \
  --embedding-method local-hash \
  --limit 3000 \
  --python .venv/bin/python
```

11. Smoke the deployed API with the transition bearer token. `/readyz` should
    report configured client auth and DB readiness after the runtime has picked
    up the refreshed Key Vault values.

12. Rebuild and redeploy Flutter web after backend URL or client auth changes.
    Pass `LALA_API_BASE_URL`, `LALA_API_BEARER_TOKEN`, `KAKAO_JAVASCRIPT_KEY`,
    and `LALA_UI_LANGUAGE` as build-time values from deployment secrets or
    trusted local shell variables.

13. Move the API vanity domain only after reviewing the DNS change. Ask Azure
    for the required validation record:

```bash
az containerapp hostname add \
  --name "$AZURE_CONTAINER_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --hostname api.lala-next.cloud
```

If Azure reports the `asuid.api.lala-next.cloud` TXT record is missing, add that
TXT record in Gabia first. Then replace the current `api` A record with a CNAME
to the Azure Container Apps FQDN, rerun the hostname add/bind command, and wait
for the managed certificate provisioning state to become `Succeeded`.

The current Gabia record shape is:

```text
A      @           76.76.21.21
A      www         76.76.21.21
CNAME  api         <azure-container-app-fqdn>.
TXT    asuid.api   <azure-custom-domain-validation-id>
```

After Azure reports the custom hostname binding as `SniEnabled`, verify
`https://api.lala-next.cloud` and rebuild Flutter web with
`LALA_API_BASE_URL=https://api.lala-next.cloud`.

## Still Open

- Re-run the Azure dev deployment after any Bicep or GitHub secret change so
  Key Vault secrets and the Container App revision stay aligned.
- Keep Flutter web using the transition bearer token only from deployment
  secrets until OAuth or a backend-for-frontend proxy replaces the static token.
- Remove the temporary operator PostgreSQL firewall rule during the next Azure
  lock maintenance window. The resource group currently has a `CanNotDelete`
  lock, so the rule deletion is blocked unless an authorized operator
  temporarily removes or scopes the lock.
- Add Culture Info, KOPIS, card-spending files, persistent weather observations,
  and review attribute signals, then regenerate scores and RAG chunks.
- Expand franchise matching with official location-level franchise references
  when a suitable source with branch addresses or coordinates is available.
  Current Fair Trade Commission ingestion covers brand-level statistics, so
  `economy.franchise_locations` intentionally remains empty.
- Decide retention/cleanup policy for historical `local-value-v1` score
  snapshots. They are harmless for current reads but should have an explicit
  audit/archive policy before production.
- Add production-grade identity, private networking, and observability gates
  before treating the environment as durable production hosting.
