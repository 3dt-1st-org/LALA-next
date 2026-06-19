# Live DB Rollout

This runbook turns the canonical SQL baseline into a live PostgreSQL target only
after the Azure resource and secret boundary is clear.

## Current Gate

The LALA-next API already knows how to load `DB_DSN` from the LALA-next Key
Vault secret name `db-dsn`. The rollout gate is whether an approved PostgreSQL
Flexible Server, database, extension allowlist, and `db-dsn` secret exist.

Generate the non-mutating rollout plan first:

```bash
scripts/unix/plan_db_rollout.sh
```

```powershell
.\scripts\windows\plan_db_rollout.ps1
```

The plan includes the proposed resource names, canonical SQL file hashes,
approval gates, and copy-paste candidate commands. It does not create Azure
resources, does not apply SQL, and does not print secrets. The default proposed
PostgreSQL server name is `lala-postgres-server`; change it with
`--postgres-server-name` or `-PostgresServerName` before approval if the team
chooses a different name.

Check that state without printing secrets:

```bash
scripts/unix/verify_db_resources.sh
```

```powershell
.\scripts\windows\verify_db_resources.ps1
```

Use the strict form before applying SQL:

```bash
scripts/unix/verify_db_resources.sh \
  --postgres-server-name <server-name> \
  --database-name lala \
  --require-database
```

```powershell
.\scripts\windows\verify_db_resources.ps1 `
  -PostgresServerName <server-name> `
  -DatabaseName lala `
  -RequireDatabase
```

The strict check requires:

- Key Vault `lala-key-vault`.
- Key Vault secret name `db-dsn`.
- An Azure Database for PostgreSQL Flexible Server in resource group
  `<LALA_AZURE_RESOURCE_GROUP>`.
- Database `lala` unless another database name is passed.
- `azure.extensions` allowlist entries for `POSTGIS`, `VECTOR`, and `PGCRYPTO`.

Secret values are never printed.

## Apply Sequence

Run the canonical plan first:

```bash
scripts/unix/apply_canonical_sql.sh
```

```powershell
.\scripts\windows\apply_canonical_sql.ps1
```

Apply only after the plan and database target are approved:

```bash
ALLOW_CANONICAL_SQL_APPLY=1 \
  scripts/unix/apply_canonical_sql.sh \
  --apply \
  --confirm APPLY_CANONICAL_SQL \
  --key-vault-url <KEY_VAULT_URL>
```

```powershell
$env:ALLOW_CANONICAL_SQL_APPLY = "1"
.\scripts\windows\apply_canonical_sql.ps1 `
  -Apply `
  -Confirm APPLY_CANONICAL_SQL `
  -KeyVaultUrl <KEY_VAULT_URL>
```

Then verify the schema:

```bash
scripts/unix/verify_db_schema.sh \
  --key-vault-url <KEY_VAULT_URL>
```

```powershell
.\scripts\windows\verify_db_schema.ps1 `
  -KeyVaultUrl <KEY_VAULT_URL>
```

Finally start and smoke the API:

```bash
scripts/unix/start_api.sh \
  --port 8080 \
  --key-vault-url <KEY_VAULT_URL>

scripts/unix/smoke_api.sh \
  --base-url http://127.0.0.1:8080 \
  --key-vault-url <KEY_VAULT_URL>
```

```powershell
.\scripts\windows\start_api.ps1 `
  -Port 8080 `
  -KeyVaultUrl <KEY_VAULT_URL>

.\scripts\windows\smoke_api.ps1 `
  -BaseUrl http://127.0.0.1:8080 `
  -KeyVaultUrl <KEY_VAULT_URL>
```

## Current Evidence

Controller check on 2026-06-11 found no PostgreSQL Flexible Server in resource
group `<LALA_AZURE_RESOURCE_GROUP>` and no `db-dsn` secret name in Key Vault
`lala-key-vault`. ONMU DB URL candidates in `onmu-source-vault` were
checked without printing values; they point at localhost dev ports from this Mac
and did not pass the LALA canonical schema verifier. That means live DB rollout
is not ready yet; the API should continue to use deterministic skeleton fallback
until the database target is provisioned and approved.
