# Development Reset SQL

This folder is reserved for local-only reset and seed scripts.

Rules:

- Do not run scripts from this folder against shared or production-like databases.
- Destructive statements belong here, not in `sql/canonical`.
- Seed scripts must use fake or public demo data only.
- Keep real credentials out of SQL files.

Wave 1 intentionally does not include reset SQL because no live DB migration is being applied.

