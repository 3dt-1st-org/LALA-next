# Operator-pending SQL

SQL in this directory is a reviewed proposal for a separately approved,
operator-run migration. It is intentionally outside `sql/canonical/`.

The canonical runner discovers every `sql/canonical/*.sql` file and executes
the complete ordered plan in one transaction. A comment cannot exclude a file
from that plan, so pending SQL must not be placed under `sql/canonical/` until
the schema change is explicitly approved for that runner.

Pending SQL is not applied by tests, CI, startup, or any normal application
path. Moving a proposal here does not apply it or change runtime schema
compatibility requirements.
