# SQL Canonicalization

Wave 1 establishes a non-destructive canonical SQL baseline and a guarded
plan/apply path. It does not run an unreviewed live migration.

Folders:

- `sql/canonical`: non-destructive shared schema baseline.
- `sql/dev_reset`: local-only destructive reset or seed scripts.

Canonical order:

1. `000_extensions_and_schemas.sql`: PostGIS, pgvector, pgcrypto, and schemas.
2. `010_travel_core_tables.sql`: public place read model and place enrichment history.
3. `020_travel_domain_tables.sql`: weather, docent script, and place event tables.
4. `030_community_core_tables.sql`: provider-neutral community keyword and mention tables.
5. `035_data_pipeline_tables.sql`: source file, culture, economy, and analytics tables.
6. `036_rag_knowledge_tables.sql`: pgvector-backed RAG knowledge chunks.
7. `040_ops_core_tables.sql`: job, dependency, and cost operation tables.
8. `050_views_and_indexes.sql`: stable read views for API/reporting, plus
   read-only compatibility views for legacy Flask-shaped handoff data.

Rules:

- `sql/canonical` must not contain destructive statements such as `DROP TABLE`,
  `DROP SCHEMA`, `DROP VIEW`, `TRUNCATE`, broad `DELETE FROM`, or `ALTER TABLE
  ... DROP COLUMN`.
- Credentials and DSNs must not be committed.
- Azure PostgreSQL remains the source of truth unless a later migration explicitly changes that decision.
- Local Windows DB is a resettable development target only.
- Compatibility views live under the `compat` schema. They do not replace or
  shadow canonical `travel.*` table names.

## Dev Reset and Seed Plan

`sql/dev_reset` is intentionally outside the shared canonical migration path.
It can contain local-only reset or seed helpers. The default command is a
dry-run plan:

```bash
scripts/unix/plan_dev_reset.sh
```

The plan reports file order, statement counts, SHA-256 hashes, and any secret or
marker findings. It does not read `DB_DSN`, does not connect to PostgreSQL, and
does not apply SQL.

Apply mode exists for localhost development databases only:

```bash
ALLOW_DEV_RESET_APPLY=1 \
  scripts/unix/plan_dev_reset.sh \
  --apply \
  --confirm APPLY_DEV_RESET_SQL
```

The apply guard rejects non-local hosts before connecting and still does not
print `DB_DSN`. Current seed files insert public/demo Suwon data for local DB
experiments after the canonical schema exists.

## Plan and Apply Guard

Generate the canonical rollout plan:

```powershell
.\scripts\windows\apply_canonical_sql.ps1
```

The default command does not require `DB_DSN`, does not connect to PostgreSQL,
and does not apply SQL. It reports:

- The sorted canonical file order.
- Statement counts.
- SHA-256 hashes for review and handoff.
- Any destructive or secret-like safety finding.

Apply mode is intentionally guarded. It requires `-Apply`, the exact confirm
string, and `ALLOW_CANONICAL_SQL_APPLY=1`:

```powershell
$env:ALLOW_CANONICAL_SQL_APPLY = "1"
.\scripts\windows\apply_canonical_sql.ps1 `
  -Apply `
  -Confirm APPLY_CANONICAL_SQL `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/
```

Apply mode runs the canonical files in sorted order inside one transaction with
short lock and statement timeouts. It does not print `DB_DSN`. If any statement
fails, PostgreSQL rolls the transaction back through the driver context.

## Read-Only Rollout Verification

Before pointing the shared Windows backend at a live PostgreSQL target, verify
that the database already satisfies this canonical baseline:

```powershell
.\scripts\windows\verify_db_schema.ps1
```

The verification path is intentionally read-only. It checks:

- Required extensions: `postgis`, `vector`, `pgcrypto`.
- Required schemas: `travel`, `culture`, `economy`, `community`, `ingest`,
  `analytics`, `rag`, `ops`, and `compat`.
- Required API/reporting relations, including `travel.public_places`,
  `travel.latest_weather`, `compat.legacy_places_api`, and
  `ops.dependency_latest`.

This command does not run `sql/canonical/*.sql`, does not apply migrations, and
does not print `DB_DSN`. A non-zero exit means the DB is not yet safe to treat as
the canonical shared target.
