from __future__ import annotations

from dataclasses import dataclass
from typing import Any

REQUIRED_EXTENSIONS = ("postgis", "vector", "pgcrypto")
REQUIRED_SCHEMAS = (
    "travel",
    "culture",
    "economy",
    "community",
    "ingest",
    "analytics",
    "rag",
    "ops",
    "compat",
)
REQUIRED_RELATIONS = (
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


@dataclass(frozen=True)
class DbSchemaReport:
    extensions: dict[str, bool]
    schemas: dict[str, bool]
    relations: dict[str, bool]

    @property
    def ok(self) -> bool:
        return all(self.extensions.values()) and all(self.schemas.values()) and all(
            self.relations.values()
        )

    def missing(self) -> dict[str, list[str]]:
        return {
            "extensions": [name for name, present in self.extensions.items() if not present],
            "schemas": [name for name, present in self.schemas.items() if not present],
            "relations": [name for name, present in self.relations.items() if not present],
        }

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "extensions": self.extensions,
            "schemas": self.schemas,
            "relations": self.relations,
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

    return DbSchemaReport(extensions=extensions, schemas=schemas, relations=relations)


def _presence_map(cur, sql: str, names: tuple[str, ...]) -> dict[str, bool]:
    result: dict[str, bool] = {}
    for name in names:
        cur.execute(sql, (name,))
        row = cur.fetchone()
        result[name] = bool(row and row[0])
    return result
