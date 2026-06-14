# Development Reset SQL

This folder is reserved for local-only reset and seed scripts. It is not a
shared migration folder.

Rules:

- Do not run scripts from this folder against shared or production-like databases.
- Destructive statements belong here, not in `sql/canonical`.
- Seed scripts must use fake or public demo data only.
- Keep real credentials out of SQL files.
- Every SQL file must include the `local-only dev seed/reset SQL` marker.
- Default tooling is dry-run plan only:

```bash
scripts/unix/plan_dev_reset.sh
```

```powershell
.\scripts\windows\plan_dev_reset.ps1
```

Guarded apply exists only for local development databases. It requires an
explicit localhost `DB_DSN`, the exact confirm string, and a process-local allow
flag:

```bash
ALLOW_DEV_RESET_APPLY=1 \
  scripts/unix/plan_dev_reset.sh \
  --apply \
  --confirm APPLY_DEV_RESET_SQL
```

```powershell
$env:ALLOW_DEV_RESET_APPLY = "1"
.\scripts\windows\plan_dev_reset.ps1 `
  -Apply `
  -Confirm APPLY_DEV_RESET_SQL
```

The current files seed public/demo Suwon place, weather, docent-cache,
community, and ops rows for local DB experiments after the canonical
schema exists. They use `ON CONFLICT` or `WHERE NOT EXISTS` guards where the
schema has a suitable key. Live DB rollout still requires explicit approval and
must start from `scripts/unix/verify_db_resources.sh`, not this folder.
