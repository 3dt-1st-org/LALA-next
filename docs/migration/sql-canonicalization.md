# SQL Canonicalization

Wave 1 establishes folder boundaries only. It does not apply migrations to a live database.

Folders:

- `sql/canonical`: non-destructive shared schema baseline.
- `sql/dev_reset`: local-only destructive reset or seed scripts.

Rules:

- `sql/canonical` must not contain `DROP TABLE`.
- Credentials and DSNs must not be committed.
- Azure PostgreSQL remains the source of truth unless a later migration explicitly changes that decision.
- Local Windows DB is a resettable development target only.

