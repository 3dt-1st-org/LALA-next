from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict, dataclass
from typing import Any, Sequence

from apps.api.app.core.config import get_settings
from apps.api.app.core.redaction import redact_secret_text

CONFIRM_TEXT = "APPLY_AI_PLACE_ENRICHMENT"
ALLOW_ENV = "ALLOW_AI_PLACE_ENRICHMENT_APPLY"
PROMPT_VERSION = "place-ai-enrichment-v1"


@dataclass(frozen=True)
class PlaceCandidate:
    place_id: str
    name_ko: str
    category: str
    address_ko: str | None = None
    region_name_ko: str | None = None
    name_en: str | None = None
    address_en: str | None = None
    region_name_en: str | None = None
    is_indoor: bool | None = None

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> "PlaceCandidate":
        return cls(
            place_id=str(row.get("place_id") or ""),
            name_ko=str(row.get("name_ko") or ""),
            category=str(row.get("category") or ""),
            address_ko=_optional_text(row.get("address_ko")),
            region_name_ko=_optional_text(row.get("region_name_ko")),
            name_en=_optional_text(row.get("name_en")),
            address_en=_optional_text(row.get("address_en")),
            region_name_en=_optional_text(row.get("region_name_en")),
            is_indoor=_optional_bool(row.get("is_indoor")),
        )

    def to_prompt_record(self) -> dict[str, Any]:
        return {
            "place_id": self.place_id,
            "name_ko": self.name_ko,
            "category": self.category,
            "address_ko": self.address_ko,
            "region_name_ko": self.region_name_ko,
            "existing": {
                "name_en": self.name_en,
                "address_en": self.address_en,
                "region_name_en": self.region_name_en,
                "is_indoor": self.is_indoor,
            },
        }


@dataclass(frozen=True)
class PlaceEnrichment:
    place_id: str
    name_en: str | None = None
    address_en: str | None = None
    region_name_en: str | None = None
    is_indoor: bool | None = None
    confidence: float | None = None
    reason: str | None = None

    def has_values(self) -> bool:
        return any(
            value is not None
            for value in (self.name_en, self.address_en, self.region_name_en, self.is_indoor)
        )


SYSTEM_PROMPT = """\
You enrich Korean local place records for a local travel app.

Return ONLY a JSON object:
{
  "results": [
    {
      "place_id": "same id as input",
      "name_en": "public-facing English name or null",
      "address_en": "English address/romanization from the supplied address only or null",
      "region_name_en": "English region name or null",
      "is_indoor": true | false | null,
      "confidence": 0.0-1.0,
      "reason": "short reason"
    }
  ]
}

Rules:
1. Preserve existing English values when they are already present and reasonable.
2. Translate or romanize only the supplied Korean text. Do not invent missing address details.
3. Use concise, natural English for cultural events, attractions, and restaurants.
4. For attractions, classify is_indoor for weather filtering: museums, galleries, libraries,
   theaters, indoor experience centers, markets/malls, and visitor centers are indoor; parks,
   mountains, rivers, plazas, fortresses, beaches, trails, temples with outdoor grounds, and
   heritage sites are outdoor. Use null when uncertain.
5. For restaurants and events, set is_indoor to null unless the supplied name clearly describes
   a physical indoor attraction.
6. Return the same count as the input and keep each place_id unchanged.
"""


def parse_ai_response(raw: str, candidates: Sequence[PlaceCandidate]) -> list[PlaceEnrichment]:
    payload = json.loads(_strip_code_fence(raw))
    if isinstance(payload, list):
        items = payload
    elif isinstance(payload, dict):
        items = _first_list_value(payload)
    else:
        raise ValueError("Azure OpenAI returned a non-JSON-object response.")

    candidate_ids = {candidate.place_id for candidate in candidates}
    parsed: list[PlaceEnrichment] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        fallback_id = candidates[index].place_id if index < len(candidates) else ""
        place_id = str(item.get("place_id") or item.get("id") or fallback_id)
        if place_id not in candidate_ids and index < len(candidates):
            place_id = candidates[index].place_id
        parsed.append(
            PlaceEnrichment(
                place_id=place_id,
                name_en=_optional_text(item.get("name_en")),
                address_en=_optional_text(item.get("address_en")),
                region_name_en=_optional_text(item.get("region_name_en") or item.get("region_en")),
                is_indoor=_optional_bool(item.get("is_indoor")),
                confidence=_optional_float(item.get("confidence")),
                reason=_optional_text(item.get("reason")),
            )
        )
    return parsed


def ensure_place_ai_columns(conn: Any) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS travel.place_enrichments (
                id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
                place_id text NOT NULL REFERENCES travel.places(place_id),
                enrichment_type text NOT NULL,
                name_en text,
                address_en text,
                region_name_en text,
                is_indoor boolean,
                attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
                confidence numeric(5, 4),
                source_method text NOT NULL,
                model_name text,
                prompt_version text,
                generated_at timestamptz NOT NULL DEFAULT now()
            );
            """
        )
    conn.commit()


def fetch_candidates(
    *,
    dsn: str,
    category: str,
    limit: int,
    connect_timeout: int,
) -> list[PlaceCandidate]:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    sql = """
        SELECT
            place_id,
            name_ko,
            name_en,
            category,
            address_ko,
            address_en,
            region_name_ko,
            region_name_en,
            is_indoor
        FROM travel.places
        WHERE (%s = 'all' OR category = %s)
          AND (
              name_en IS NULL OR length(trim(name_en)) = 0
              OR (address_ko IS NOT NULL AND length(trim(coalesce(address_en, ''))) = 0)
              OR (region_name_ko IS NOT NULL AND length(trim(coalesce(region_name_en, ''))) = 0)
              OR (category = 'attraction' AND is_indoor IS NULL)
          )
        ORDER BY updated_at DESC, place_id
        LIMIT %s
    """
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        ensure_place_ai_columns(conn)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, (category, category, limit))
            return [PlaceCandidate.from_row(dict(row)) for row in cur.fetchall()]


def generate_enrichments(
    *,
    candidates: Sequence[PlaceCandidate],
    batch_size: int,
) -> list[PlaceEnrichment]:
    if not candidates:
        return []
    settings = get_settings()
    missing = _missing_aoai_settings(settings)
    if missing:
        raise RuntimeError("Azure OpenAI config is missing: " + ", ".join(missing))

    try:
        from openai import AzureOpenAI
    except Exception as exc:
        raise RuntimeError("openai package is required for AI enrichment.") from exc

    client = AzureOpenAI(
        azure_endpoint=settings.azure_openai_endpoint,
        api_key=settings.azure_openai_key,
        api_version=settings.azure_openai_api_version,
    )

    enrichments: list[PlaceEnrichment] = []
    for start in range(0, len(candidates), batch_size):
        batch = list(candidates[start : start + batch_size])
        response = client.chat.completions.create(
            model=settings.azure_openai_deployment,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": json.dumps(
                        [candidate.to_prompt_record() for candidate in batch],
                        ensure_ascii=False,
                    ),
                },
            ],
            temperature=0.1,
            max_tokens=4000,
            response_format={"type": "json_object"},
        )
        raw = response.choices[0].message.content or ""
        enrichments.extend(parse_ai_response(raw, batch))
    return enrichments


def apply_enrichments(
    *,
    dsn: str,
    enrichments: Sequence[PlaceEnrichment],
    connect_timeout: int,
) -> int:
    import psycopg2

    if not enrichments:
        return 0

    settings = get_settings()
    update_sql = """
        UPDATE travel.places
        SET
            name_en = COALESCE(NULLIF(trim(name_en), ''), %(name_en)s),
            address_en = COALESCE(NULLIF(trim(address_en), ''), %(address_en)s),
            region_name_en = COALESCE(NULLIF(trim(region_name_en), ''), %(region_name_en)s),
            is_indoor = CASE
                WHEN category = 'attraction' AND is_indoor IS NULL THEN %(is_indoor)s
                ELSE is_indoor
            END,
            updated_at = now()
        WHERE place_id = %(place_id)s
    """
    insert_sql = """
        INSERT INTO travel.place_enrichments (
            place_id,
            enrichment_type,
            name_en,
            address_en,
            region_name_en,
            is_indoor,
            attributes,
            confidence,
            source_method,
            model_name,
            prompt_version
        )
        VALUES (
            %(place_id)s,
            'place_profile',
            %(name_en)s,
            %(address_en)s,
            %(region_name_en)s,
            %(is_indoor)s,
            %(attributes)s::jsonb,
            %(confidence)s,
            'azure_openai',
            %(model)s,
            %(version)s
        )
    """
    updated = 0
    with psycopg2.connect(dsn, connect_timeout=connect_timeout) as conn:
        ensure_place_ai_columns(conn)
        with conn.cursor() as cur:
            for item in enrichments:
                if not item.has_values():
                    continue
                params = {
                    "place_id": item.place_id,
                    "name_en": item.name_en,
                    "address_en": item.address_en,
                    "region_name_en": item.region_name_en,
                    "is_indoor": item.is_indoor,
                    "attributes": json.dumps(
                        {
                            "reason": item.reason,
                        },
                        ensure_ascii=False,
                    ),
                    "confidence": item.confidence,
                    "model": settings.azure_openai_deployment,
                    "version": PROMPT_VERSION,
                }
                cur.execute(update_sql, params)
                updated += cur.rowcount
                cur.execute(insert_sql, params)
        conn.commit()
    return updated


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Plan, preview, or apply Azure OpenAI enrichment for travel.places."
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    parser.add_argument(
        "--dry-run-ai",
        action="store_true",
        help="Call Azure OpenAI and print a preview without updating rows.",
    )
    parser.add_argument("--apply", action="store_true", help="Call Azure OpenAI and update DB rows.")
    parser.add_argument("--confirm", default="", help=f"Required with --apply: {CONFIRM_TEXT}")
    parser.add_argument(
        "--category",
        choices=["all", "attraction", "restaurant", "event"],
        default="all",
    )
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=20)
    parser.add_argument("--connect-timeout", type=int, default=5)
    args = parser.parse_args(argv)

    if args.limit <= 0:
        _write(args, {"ok": False, "mode": "plan", "error": "--limit must be positive."})
        return 2
    if args.batch_size <= 0:
        _write(args, {"ok": False, "mode": "plan", "error": "--batch-size must be positive."})
        return 2
    if args.apply and args.dry_run_ai:
        _write(args, {"ok": False, "mode": "plan", "error": "Use either --apply or --dry-run-ai."})
        return 2

    if not args.apply and not args.dry_run_ai:
        _write(
            args,
            {
                "ok": True,
                "mode": "plan",
                "live_ai_call": False,
                "db_mutation": False,
                "target": "travel.places",
                "prompt_version": PROMPT_VERSION,
                "enriched_columns": [
                    "name_en",
                    "address_en",
                    "region_name_en",
                    "is_indoor",
                    "travel.place_enrichments",
                ],
            },
        )
        return 0

    if args.apply:
        guard_error = _apply_guard_error(args)
        if guard_error:
            _write(args, {"ok": False, "mode": "apply", "error": guard_error})
            return 2

    settings = get_settings()
    dsn = os.getenv("DB_DSN") or settings.db_dsn
    if not dsn:
        _write(args, {"ok": False, "mode": _mode(args), "error": "DB_DSN is not configured."})
        return 2

    try:
        candidates = fetch_candidates(
            dsn=dsn,
            category=args.category,
            limit=args.limit,
            connect_timeout=args.connect_timeout,
        )
        enrichments = generate_enrichments(candidates=candidates, batch_size=args.batch_size)
        updated_rows = 0
        if args.apply:
            updated_rows = apply_enrichments(
                dsn=dsn,
                enrichments=enrichments,
                connect_timeout=args.connect_timeout,
            )
    except Exception as exc:
        _write(
            args,
            {
                "ok": False,
                "mode": _mode(args),
                "error": redact_secret_text(
                    str(exc) or exc.__class__.__name__,
                    (dsn, settings.azure_openai_key),
                ),
            },
        )
        return 2

    _write(
        args,
        {
            "ok": True,
            "mode": _mode(args),
            "live_ai_call": True,
            "db_mutation": bool(args.apply),
            "schema_prepare": True,
            "target": "travel.places",
            "candidate_count": len(candidates),
            "generated_count": len(enrichments),
            "updated_rows": updated_rows,
            "prompt_version": PROMPT_VERSION,
            "preview": [asdict(item) for item in enrichments[:5]],
        },
    )
    return 0


def _apply_guard_error(args: argparse.Namespace) -> str:
    if args.confirm != CONFIRM_TEXT:
        return f"--apply requires --confirm {CONFIRM_TEXT}."
    if os.getenv(ALLOW_ENV) != "1":
        return f"--apply requires {ALLOW_ENV}=1 in the process environment."
    return ""


def _write(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
        return

    print("LALA-next place AI enrichment")
    print(f"mode={payload.get('mode')}")
    print(f"status={'ok' if payload.get('ok') else 'degraded'}")
    print(f"target={payload.get('target', 'travel.places')}")
    print(f"prompt_version={payload.get('prompt_version', PROMPT_VERSION)}")
    if "live_ai_call" in payload:
        print(f"live_ai_call={str(payload.get('live_ai_call')).lower()}")
    if "db_mutation" in payload:
        print(f"db_mutation={str(payload.get('db_mutation')).lower()}")
    if payload.get("error"):
        print(f"error={payload['error']}")
        return
    for key in ("candidate_count", "generated_count", "updated_rows"):
        if key in payload:
            print(f"{key}={payload[key]}")
    for item in payload.get("enriched_columns") or []:
        print(f"enriched_column={item}")
    for item in payload.get("preview") or []:
        print(
            "preview="
            + json.dumps(
                {
                    "place_id": item.get("place_id"),
                    "name_en": item.get("name_en"),
                    "region_name_en": item.get("region_name_en"),
                    "is_indoor": item.get("is_indoor"),
                    "confidence": item.get("confidence"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )


def _mode(args: argparse.Namespace) -> str:
    return "apply" if args.apply else "dry-run-ai"


def _missing_aoai_settings(settings: Any) -> list[str]:
    missing: list[str] = []
    if not settings.azure_openai_endpoint:
        missing.append("AZURE_OPENAI_ENDPOINT")
    if not settings.azure_openai_key:
        missing.append("AZURE_OPENAI_KEY")
    if not settings.azure_openai_deployment:
        missing.append("AZURE_OPENAI_DEPLOYMENT")
    if not settings.azure_openai_api_version:
        missing.append("AZURE_OPENAI_API_VERSION")
    return missing


def _first_list_value(payload: dict[str, Any]) -> list[Any]:
    if isinstance(payload.get("results"), list):
        return payload["results"]
    for value in payload.values():
        if isinstance(value, list):
            return value
    raise ValueError("Azure OpenAI JSON response did not include a results list.")


def _strip_code_fence(raw: str) -> str:
    text = (raw or "").strip()
    if not text.startswith("```"):
        return text
    lines = text.splitlines()
    if len(lines) >= 3 and lines[-1].strip() == "```":
        return "\n".join(lines[1:-1]).removeprefix("json").strip()
    return text.strip("`").strip()


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text or text.lower() in {"null", "none", "n/a", "unknown"}:
        return None
    return text


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return min(max(parsed, 0.0), 1.0)


def _optional_bool(value: Any) -> bool | None:
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"true", "indoor", "inside", "실내", "1", "yes"}:
        return True
    if text in {"false", "outdoor", "outside", "실외", "0", "no"}:
        return False
    return None


if __name__ == "__main__":
    sys.exit(main())
