# Live DB Rollout

This runbook turns the canonical SQL baseline into a live PostgreSQL target only
after the Azure resource and secret boundary is clear.

## Current Gate

The LALA-next API already knows how to load `DB_DSN` from the LALA-next Key
Vault secret name `db-dsn`. The rollout gate is whether an approved PostgreSQL
Flexible Server, database, extension allowlist, and `db-dsn` secret exist.

Check that state without printing secrets:

```powershell
.\scripts\windows\verify_db_resources.ps1
```

Use the strict form before applying SQL:

```powershell
.\scripts\windows\verify_db_resources.ps1 `
  -PostgresServerName <server-name> `
  -DatabaseName lala `
  -RequireDatabase
```

The strict check requires:

- Key Vault `lala-next-kv-27db5e`.
- Key Vault secret name `db-dsn`.
- An Azure Database for PostgreSQL Flexible Server in resource group
  `3dt-final-team1`.
- Database `lala` unless another database name is passed.
- `azure.extensions` allowlist entries for `POSTGIS`, `VECTOR`, and `PGCRYPTO`.

Secret values are never printed.

## Apply Sequence

Run the canonical plan first:

```powershell
.\scripts\windows\apply_canonical_sql.ps1
```

Apply only after the plan and database target are approved:

```powershell
$env:ALLOW_CANONICAL_SQL_APPLY = "1"
.\scripts\windows\apply_canonical_sql.ps1 `
  -Apply `
  -Confirm APPLY_CANONICAL_SQL `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/
```

Then verify the schema:

```powershell
.\scripts\windows\verify_db_schema.ps1 `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/
```

Finally start and smoke the API:

```powershell
.\scripts\windows\start_api.ps1 `
  -Port 8080 `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/

.\scripts\windows\smoke_api.ps1 `
  -BaseUrl http://127.0.0.1:8080 `
  -KeyVaultUrl https://lala-next-kv-27db5e.vault.azure.net/
```

## Current Evidence

Controller check on 2026-06-11 found no PostgreSQL Flexible Server in resource
group `3dt-final-team1` and no `db-dsn` secret name in Key Vault
`lala-next-kv-27db5e`. That means live DB rollout is not ready yet; the API
should continue to use deterministic skeleton fallback until the database target
is provisioned and approved.
