from __future__ import annotations

from dataclasses import dataclass
from typing import Any

REQUIRED_EXTENSIONS = ("postgis", "vector", "pgcrypto")
REQUIRED_SCHEMAS = (
    "travel",
    "culture",
    "economy",
    "community",
    "identity",
    "ingest",
    "analytics",
    "rag",
    "ops",
    "compat",
)
REQUIRED_RELATIONS = (
    "identity.users",
    "identity.deleted_users",
    "travel.places",
    "travel.place_enrichments",
    "travel.weather_observations",
    "travel.docent_scripts",
    "travel.place_events",
    "culture.events",
    "economy.card_spending_area_monthly",
    "economy.card_spending_demographics",
    "economy.franchise_brands",
    "economy.franchise_locations",
    "community.keyword_watchlist",
    "community.ingest_runs",
    "community.ingest_tasks",
    "community.posts",
    "community.place_mentions_weekly",
    "ingest.source_files",
    "analytics.place_business_identity",
    "analytics.place_score_snapshots",
    "rag.knowledge_chunks",
    "ops.job_runs",
    "ops.dependency_checks",
    "ops.daily_costs",
    "travel.public_places",
    "travel.latest_weather",
    "compat.legacy_places_api",
    "compat.legacy_docent_scripts_api",
    "ops.dependency_latest",
)

REQUIRED_COLUMNS = {
    "identity.users.id": ("uuid", "NO"),
    "identity.users.issuer": ("text", "NO"),
    "identity.users.subject": ("text", "NO"),
    "identity.users.status": ("text", "NO"),
    "identity.users.created_at": ("timestamp with time zone", "NO"),
    "identity.users.last_seen_at": ("timestamp with time zone", "NO"),
    "identity.users.deletion_requested_at": ("timestamp with time zone", "YES"),
    "identity.deleted_users.identity_digest": ("bytea", "NO"),
    "identity.deleted_users.deleted_at": ("timestamp with time zone", "NO"),
}

REQUIRED_UNIQUE_CONSTRAINTS = {
    "identity.users(issuer,subject)": ("identity", "users", ("issuer", "subject")),
    "identity.deleted_users(identity_digest)": (
        "identity",
        "deleted_users",
        ("identity_digest",),
    ),
}


@dataclass(frozen=True)
class DbSchemaReport:
    extensions: dict[str, bool]
    schemas: dict[str, bool]
    relations: dict[str, bool]
    columns: dict[str, bool]
    unique_constraints: dict[str, bool]

    @property
    def ok(self) -> bool:
        return (
            all(self.extensions.values())
            and all(self.schemas.values())
            and all(self.relations.values())
            and all(self.columns.values())
            and all(self.unique_constraints.values())
        )

    def missing(self) -> dict[str, list[str]]:
        return {
            "extensions": [name for name, present in self.extensions.items() if not present],
            "schemas": [name for name, present in self.schemas.items() if not present],
            "relations": [name for name, present in self.relations.items() if not present],
            "columns": [name for name, present in self.columns.items() if not present],
            "unique_constraints": [
                name for name, present in self.unique_constraints.items() if not present
            ],
        }

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "extensions": self.extensions,
            "schemas": self.schemas,
            "relations": self.relations,
            "columns": self.columns,
            "unique_constraints": self.unique_constraints,
            "missing": self.missing(),
        }


def inspect_canonical_schema(*, dsn: str, connect_timeout: int = 5) -> DbSchemaReport:
    if not dsn:
        raise ValueError("DB_DSN is required.")
    try:
        import psycopg2
    except Exception as exc:
        raise RuntimeError("psycopg2 is required for DB schema verification.") from exc

    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        with conn.cursor() as cur:
            extensions = _presence_map(
                cur,
                "SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = %s)",
                REQUIRED_EXTENSIONS,
            )
            schemas = _presence_map(
                cur,
                "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = %s)",
                REQUIRED_SCHEMAS,
            )
            relations = _presence_map(
                cur,
                "SELECT to_regclass(%s) IS NOT NULL",
                REQUIRED_RELATIONS,
            )
            columns = _column_presence_map(cur)
            unique_constraints = _unique_constraint_presence_map(cur)

    return DbSchemaReport(
        extensions=extensions,
        schemas=schemas,
        relations=relations,
        columns=columns,
        unique_constraints=unique_constraints,
    )


def _presence_map(cur, sql: str, names: tuple[str, ...]) -> dict[str, bool]:
    result: dict[str, bool] = {}
    for name in names:
        cur.execute(sql, (name,))
        row = cur.fetchone()
        result[name] = bool(row and row[0])
    return result


def _column_presence_map(cur) -> dict[str, bool]:
    result: dict[str, bool] = {}
    sql = """
        SELECT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = %s
              AND table_name = %s
              AND column_name = %s
              AND data_type = %s
              AND is_nullable = %s
        )
    """
    for name, (data_type, is_nullable) in REQUIRED_COLUMNS.items():
        schema, table, column = name.split(".", 2)
        cur.execute(sql, (schema, table, column, data_type, is_nullable))
        row = cur.fetchone()
        result[name] = bool(row and row[0])
    return result


def _unique_constraint_presence_map(cur) -> dict[str, bool]:
    result: dict[str, bool] = {}
    sql = """
        SELECT EXISTS (
            SELECT 1
            FROM pg_constraint constraint_row
            JOIN pg_class relation ON relation.oid = constraint_row.conrelid
            JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
            WHERE namespace.nspname = %s
              AND relation.relname = %s
              AND constraint_row.contype = 'u'
              AND ARRAY(
                    SELECT attribute.attname::text
                    FROM unnest(constraint_row.conkey) WITH ORDINALITY AS key(attnum, position)
                    JOIN pg_attribute attribute
                      ON attribute.attrelid = relation.oid
                     AND attribute.attnum = key.attnum
                    ORDER BY key.position
                  ) = %s::text[]
        )
    """
    for name, (schema, table, columns) in REQUIRED_UNIQUE_CONSTRAINTS.items():
        cur.execute(sql, (schema, table, list(columns)))
        row = cur.fetchone()
        result[name] = bool(row and row[0])
    return result
