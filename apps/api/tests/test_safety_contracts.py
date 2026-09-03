from __future__ import annotations

import hashlib
import json
import re
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID

import pytest
from pydantic import ValidationError

from apps.api.app.core.key_vault import is_allowed_key_vault_url, key_vault_name_from_url
from apps.api.app.core.redaction import redact_secret_text
from apps.api.app.core.responses import safe_validation_details
from apps.api.app.schemas.local_signals import LocalSignalDraftCreate, LocalSignalPublicItem
from apps.api.app.services import docent_service, places_service, rag_index
from apps.api.app.services.review_ingest_governance import (
    ApprovedReviewAggregate,
    ReviewSourceRecord,
    ReviewSourceRegistration,
    approved_aggregate_from_record,
    classify_review_records,
    parse_review_record,
)
from apps.api.tests._bash import usable_bash

ROOT = Path(__file__).resolve().parents[3]
TEXT_SUFFIXES = {
    ".dart",
    ".bicep",
    ".dockerfile",
    ".env",
    ".example",
    ".md",
    ".ps1",
    ".py",
    ".sh",
    ".sql",
    ".toml",
    ".txt",
    ".yaml",
    ".yml",
}
EXPLICIT_TEXT_FILES = {
    ".dockerignore",
    ".env.example",
    ".gitignore",
}


def _tracked_text_files(*, include_tests: bool = True) -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    paths: list[Path] = []
    for rel_path in result.stdout.splitlines():
        path = ROOT / rel_path
        if not path.is_file():
            continue
        if not include_tests and "tests" in path.parts:
            continue
        if path.name in EXPLICIT_TEXT_FILES or path.suffix.lower() in TEXT_SUFFIXES:
            paths.append(path)
    return paths


def test_canonical_sql_has_no_shared_destructive_statements():
    canonical_dir = ROOT / "sql" / "canonical"
    destructive_patterns = [
        re.compile(r"\bDROP\s+(TABLE|SCHEMA|VIEW|MATERIALIZED\s+VIEW|DATABASE)\b", re.IGNORECASE),
        re.compile(r"\bTRUNCATE\b", re.IGNORECASE),
        re.compile(r"\bDELETE\s+FROM\b", re.IGNORECASE),
        re.compile(r"\bALTER\s+TABLE\b.*\bDROP\s+COLUMN\b", re.IGNORECASE | re.DOTALL),
    ]
    findings: list[str] = []
    for path in canonical_dir.glob("*.sql"):
        text = path.read_text(encoding="utf-8")
        for pattern in destructive_patterns:
            if pattern.search(text):
                findings.append(f"{path}: {pattern.pattern}")

    assert findings == []


def test_canonical_sql_declares_compatibility_views():
    views_sql = (ROOT / "sql" / "canonical" / "050_views_and_indexes.sql").read_text(
        encoding="utf-8"
    )

    assert "compat.legacy_places_api" in views_sql
    assert "compat.legacy_docent_scripts_api" in views_sql
    assert "travel.latest_weather" in views_sql


def _view_projection_columns(sql: str, view_name: str) -> set[str]:
    match = re.search(
        rf"CREATE\s+OR\s+REPLACE\s+VIEW\s+{re.escape(view_name)}\s+AS\s+SELECT\s+(.*?)\s+FROM\s+",
        sql,
        re.IGNORECASE | re.DOTALL,
    )
    assert match, f"protected view projection not found: {view_name}"

    columns: set[str] = set()
    for expression in match.group(1).split(","):
        expression = " ".join(expression.split())
        alias = re.search(r"\s+AS\s+([A-Za-z_][A-Za-z0-9_]*)$", expression, re.IGNORECASE)
        columns.add(alias.group(1) if alias else expression.rsplit(".", 1)[-1])
    return columns


def test_local_signal_views_and_schemas_enforce_downstream_safe_projection():
    sql = (ROOT / "sql" / "canonical" / "063_local_signals_contract.sql").read_text(
        encoding="utf-8"
    )
    public_columns = _view_projection_columns(sql, "community.local_signal_public")
    aggregate_columns = _view_projection_columns(sql, "community.local_signal_aggregate_candidates")

    assert public_columns == {
        "id",
        "kind",
        "source_language",
        "title",
        "body",
        "locality_level",
        "locality_code",
        "commercial_disclosure",
        "observation_date",
        "published_at",
        "created_at",
        "updated_at",
    }
    assert aggregate_columns == {
        "signal_id",
        "kind",
        "source_language",
        "locality_level",
        "locality_code",
        "observation_date",
        "aggregate_scope",
        "independent_signal_count",
        "minimum_signal_count",
        "delayed_until",
        "safe_summary_hash",
        "policy_version",
    }
    assert not aggregate_columns.intersection(
        {
            "body",
            "comment",
            "title",
            "author_issuer",
            "author_subject",
            "issuer",
            "subject",
            "latitude",
            "longitude",
            "lat",
            "lng",
            "private_draft",
        }
    )
    assert "status = 'published'" in sql
    assert "moderation_state = 'approved'" in sql
    assert "visibility = 'public'" in sql
    assert "eligibility.eligibility_status = 'eligible'" in sql

    assert set(LocalSignalPublicItem.model_fields) == {
        "id",
        "kind",
        "source_language",
        "title",
        "body",
        "locality_level",
        "locality_code",
        "commercial_disclosure",
        "observation_date",
        "published_at",
        "place_links",
        "translation",
        "display_language",
        "translation_available",
        "reaction_count",
        "comment_count",
    }
    assert set(LocalSignalPublicItem.model_fields).isdisjoint(
        {"status", "moderation_state", "author_issuer", "author_subject", "latitude", "longitude"}
    )
    assert set(LocalSignalDraftCreate.model_fields).isdisjoint(
        {"author_issuer", "author_subject", "provider", "source_name", "latitude", "longitude"}
    )

    public_item = LocalSignalPublicItem(
        id=UUID("00000000-0000-0000-0000-000000000063"),
        kind="place_tip",
        source_language="ko",
        title="공개 팁",
        body="공개된 장소 팁",
        locality_level="district",
        locality_code="suwon:paldalmun",
        commercial_disclosure="none",
        observation_date=datetime(2026, 7, 26, tzinfo=UTC).date(),
        published_at=datetime(2026, 7, 26, tzinfo=UTC),
    )
    assert "author_subject" not in public_item.model_dump()
    with pytest.raises(ValidationError):
        LocalSignalPublicItem.model_validate(
            {**public_item.model_dump(mode="json"), "status": "draft", "author_subject": "private"}
        )


def test_approved_naver_blog_evidence_stays_licensed_and_aggregate_only():
    registration = ReviewSourceRegistration(
        source_name="naver_blog_approved_api",
        provider="naver_blog",
        license_class="licensed",
        terms_version="naver-api-terms-v1",
        collection_method="approved_search_blog_api",
        retention_policy="normalized_attributes_and_aggregates_only",
        redaction_policy="no_raw_text_no_pii_downstream",
    )
    source_record = parse_review_record(
        {
            "source_name": registration.source_name,
            "provider": registration.provider,
            "external_key": "naver-post-1",
            "license_class": registration.license_class,
            "terms_version": registration.terms_version,
            "content_sha256": hashlib.sha256(b"approved-naver-record").hexdigest(),
            "received_at": datetime(2026, 7, 27, tzinfo=UTC),
            "category": "restaurant",
            "match_confidence": 0.94,
            "is_organic": True,
            "normalized_attributes": {"taste": 0.8, "service": 0.7},
        }
    )
    valid, quarantined = classify_review_records(
        registration=registration, records=[source_record.model_dump()]
    )
    assert len(valid) == 1
    assert quarantined == ()
    aggregate = approved_aggregate_from_record(valid[0])
    assert aggregate.source_name == registration.source_name
    assert set(aggregate.to_rag_metadata()) == {
        "source_name",
        "category",
        "mention_count",
        "organic_mention_count",
        "sentiment_score",
        "attribute_scores",
        "schema_version",
    }

    raw_blog_text = "RAW_APPROVED_NAVER_BLOG_BODY_SENTINEL"
    raw_record = source_record.model_dump()
    raw_record["body"] = raw_blog_text
    valid, quarantined = classify_review_records(registration=registration, records=[raw_record])
    assert valid == ()
    assert len(quarantined) == 1
    assert quarantined[0].reason_code == "schema_invalid_raw_text_field"
    assert raw_blog_text not in quarantined[0].model_dump_json()

    # Local Signals are first-party UGC: they have Logto-backed authors in SQL,
    # while governed review evidence has source/provider provenance instead.
    local_sql = (ROOT / "sql" / "canonical" / "063_local_signals_contract.sql").read_text(
        encoding="utf-8"
    )
    assert (
        "CONSTRAINT local_signals_source_kind_check CHECK (source_kind = 'first_party')"
        in local_sql
    )
    assert {"author_issuer", "author_subject"}.isdisjoint(ReviewSourceRecord.model_fields)
    assert {"provider", "source_name"}.isdisjoint(LocalSignalDraftCreate.model_fields)


def test_local_signal_and_review_projections_keep_raw_text_out_of_rag_and_docent():
    raw_signal_body = "RAW_LOCAL_SIGNAL_BODY_SENTINEL"
    raw_comment = "RAW_LOCAL_SIGNAL_COMMENT_SENTINEL"
    raw_blog_body = "RAW_NAVER_BLOG_BODY_SENTINEL"
    chunk = rag_index._place_mention_chunk(  # noqa: SLF001 -- contract boundary exercise
        {
            "id": "mention-1",
            "place_id": "place-1",
            "place_name_ko": "안전한 장소",
            "week_start": datetime(2026, 7, 21, tzinfo=UTC).date(),
            "provider": "naver_blog",
            "category": "restaurant",
            "mention_count": 8,
            "organic_mention_count": 6,
            "sentiment_score": 0.6,
            "attributes": {
                "review_attributes": {
                    "source": "approved_naver_blog",
                    "attribute_scores": {"taste": 0.8},
                    "evidence_terms": [raw_blog_body],
                    "summary_ko": raw_signal_body,
                    "source_review_phrase": raw_comment,
                },
                "review_quality": {"score": 0.8, "reason": raw_comment},
            },
        }
    )
    chunk_payload = json.dumps(chunk.to_public_dict(), ensure_ascii=False, sort_keys=True)
    assert raw_signal_body not in chunk_payload
    assert raw_comment not in chunk_payload
    assert raw_blog_body not in chunk_payload
    assert set(chunk.metadata["attributes"]["review_attributes"]) == {
        "source",
        "attribute_scores",
    }

    citations = docent_service.build_citations(
        [
            {
                "source_type": "place_mention",
                "source_id": "mention-1",
                "title_ko": "안전한 장소",
                "body_ko": raw_signal_body,
                "body_en": raw_blog_body,
                "metadata": {"language_avail": ["ko"]},
                "similarity": 0.82,
            }
        ]
    )
    assert set(citations[0]) == {
        "source_type",
        "source_id",
        "title",
        "language_avail",
        "similarity_band",
        "ref",
    }
    assert raw_signal_body not in json.dumps(citations, ensure_ascii=False)
    assert raw_blog_body not in json.dumps(citations, ensure_ascii=False)

    aggregate = ApprovedReviewAggregate(
        source_name="naver_blog_approved_api",
        aggregate_key="sha256:" + "a" * 16,
        category="restaurant",
        mention_count=8,
        organic_mention_count=6,
        sentiment_score=0.6,
        attribute_scores={"taste": 0.8},
    )
    aggregate_payload = aggregate.to_rag_metadata()
    assert raw_signal_body not in json.dumps(aggregate_payload, ensure_ascii=False)
    assert raw_comment not in json.dumps(aggregate_payload, ensure_ascii=False)
    assert raw_blog_body not in json.dumps(aggregate_payload, ensure_ascii=False)


def test_normal_place_path_fails_closed_instead_of_substituting_static_snapshot(monkeypatch):
    monkeypatch.setattr(
        places_service,
        "get_settings",
        lambda: SimpleNamespace(static_snapshot_fallback=False, db_dsn="configured"),
    )
    monkeypatch.setattr(
        places_service.db_repository,
        "fetch_places",
        lambda **kwargs: (_ for _ in ()).throw(
            places_service.db_repository.DatabaseReadError("database failure")
        ),
    )
    snapshot_calls: list[dict] = []
    monkeypatch.setattr(
        places_service.public_mvp_data,
        "fetch_places",
        lambda **kwargs: snapshot_calls.append(kwargs),
    )

    with pytest.raises(places_service.ServiceError) as exc_info:
        places_service.list_places(
            lat=37.2636,
            lng=127.0286,
            radius_m=1000,
            category="all",
            language="ko",
        )

    assert exc_info.value.code == "PLACES_DB_UNAVAILABLE"
    assert exc_info.value.retryable is True
    assert snapshot_calls == []
    assert "database failure" not in exc_info.value.message


def test_validation_and_operational_output_boundaries_redact_raw_input_and_secrets():
    raw_pii = "private-author-subject-and-body"
    details = safe_validation_details(
        [{"loc": ["body"], "msg": "invalid", "input": {"body": raw_pii}}]
    )
    assert raw_pii not in json.dumps(details, ensure_ascii=False)
    assert "input" not in details[0]

    credential = "test-opaque-value-never-log"
    dsn = f"postgresql://user:{credential}@db.example/lala"
    regex_redacted = redact_secret_text(f"dsn={dsn}")
    assert "postgresql://***:***@db.example/lala" in regex_redacted
    redacted = redact_secret_text(
        f"dsn={dsn} {'pass' + 'word'}={credential} {'service' + '_key'}={credential}", (dsn,)
    )
    assert credential not in redacted
    assert "dsn=[redacted]" in redacted
    assert "password=***" in redacted
    assert "service_key=***" in redacted


def test_repo_docs_and_scripts_do_not_contain_secret_literals():
    patterns = [
        re.compile(r"postgresql://[^\s<>]+:[^\s<>]+@"),
        re.compile(r"https://[a-z0-9-]+\.vault\.azure\.net/?", re.IGNORECASE),
        re.compile(r"^IOS_API_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^API_BEARER_TOKEN[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^POSTGRES_PASSWORD[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^OPENAI_API_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^AZURE_SPEECH_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile("SharedAccessKey" + "=", re.IGNORECASE),
        re.compile(r"BEGIN [A-Z ]*PRIVATE KEY"),
        re.compile(r"(?<![A-Za-z])sk-[A-Za-z0-9]{20,}"),
    ]
    findings: list[str] = []
    for path in _tracked_text_files(include_tests=False):
        text = path.read_text(encoding="utf-8")
        for pattern in patterns:
            match = pattern.search(text)
            if not match:
                continue
            findings.append(f"{path}: {pattern.pattern}")

    assert findings == []


def test_public_repo_does_not_contain_live_resource_identifiers():
    suffix = "27" + "db5e"
    banned = [
        f"lala-next-kv-{suffix}",
        f"onmu-dev-kv-{suffix}",
        f"lala-next-aoai-{suffix}",
        f"lala-next-speech-{suffix}",
        f"lala-next-pg-{suffix}",
        f"lala-next-eh-{suffix}",
        f"lalanextworker{suffix}",
        "27" + "db5ec6-d206-4028-b5e1-6004dca5eeef",
        "3dt-final-" + "team1",
    ]
    findings: list[str] = []
    for path in _tracked_text_files():
        text = path.read_text(encoding="utf-8")
        for value in banned:
            if value in text:
                findings.append(f"{path}: {value}")

    assert findings == []


def test_azure_dev_deploy_uses_oidc_and_dev_branch_only():
    workflow = (ROOT / ".github" / "workflows" / "azure-dev-deploy.yml").read_text(encoding="utf-8")

    assert "branches:\n      - dev" in workflow
    assert "id-token: write" in workflow
    assert "uses: azure/login@v2" in workflow
    assert "AZURE_CREDENTIALS" not in workflow
    assert "client-id: ${{ vars.AZURE_CLIENT_ID }}" in workflow
    assert "subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}" in workflow
    assert "AZURE_DEPLOY_PRINCIPAL_OBJECT_ID" in workflow
    assert 'deploymentPrincipalObjectId="$AZURE_DEPLOY_PRINCIPAL_OBJECT_ID"' in workflow
    assert "enableRoleAssignments=false" in workflow
    assert "LALA_PUBLIC_CONTEST_ACCESS" in workflow
    assert "vars.LALA_PUBLIC_CONTEST_ACCESS || 'true'" in workflow
    assert 'publicContestAccess="$LALA_PUBLIC_CONTEST_ACCESS"' in workflow
    assert "staticSnapshotFallback=false" in workflow
    assert "secrets.AZURE_POSTGRES_ADMIN_PASSWORD" in workflow
    assert "secrets.AZURE_API_BEARER_TOKEN" not in workflow
    assert 'apiBearerToken="$API_BEARER_TOKEN"' not in workflow
    assert "ALLOW_CANONICAL_SQL_APPLY" not in workflow
    assert "apply_canonical_sql" not in workflow
    assert "verify_db_schema" not in workflow
    assert "az postgres flexible-server firewall-rule" not in workflow
    assert 'SMOKE_BASE_URL="https://${API_FQDN}"' in workflow
    assert 'scripts/unix/smoke_api.sh --base-url "$SMOKE_BASE_URL"' in workflow
    assert (
        'scripts/unix/smoke_api_matrix.sh --base-url "$SMOKE_BASE_URL" --timeout 25 --profile deploy'
        in workflow
    )


def test_deployed_web_smoke_runs_public_location_flow():
    workflow = (ROOT / ".github" / "workflows" / "deployed-web-smoke.yml").read_text(
        encoding="utf-8"
    )

    assert "name: Deployed Web Smoke" in workflow
    assert "branches:\n      - dev" in workflow
    assert '"apps/flutter_app/**"' in workflow
    assert '"apps/api/app/**"' in workflow
    assert '"scripts/unix/smoke_flutter_web.sh"' in workflow
    assert "uses: actions/setup-node@v4" in workflow
    assert 'node-version: "24"' in workflow
    assert (
        '--web-url "https://lala-next.cloud/?qa=deployed-web-smoke-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"'
        in workflow
    )
    assert "--require-browser" in workflow
    assert "--fail-on-console-error" in workflow
    assert "Detect Flutter bundle changes" in workflow
    assert "grep -Eq '^apps/flutter_app/'" in workflow
    assert "require_build_sha=true" in workflow
    assert "primary_args+=(--expect-build-sha" in workflow
    assert "suwon_args+=(--expect-build-sha" in workflow
    assert "Upload browser smoke artifacts" in workflow
    assert "output/playwright/" in workflow


def test_azure_container_build_excludes_local_secrets():
    dockerignore = (ROOT / ".dockerignore").read_text(encoding="utf-8")
    dockerfile = (ROOT / "infra" / "azure" / "api.Dockerfile").read_text(encoding="utf-8")
    bicep = (ROOT / "infra" / "azure" / "main.bicep").read_text(encoding="utf-8")
    env_example = (ROOT / ".env.example").read_text(encoding="utf-8")

    assert ".env" in dockerignore
    assert ".env.*" in dockerignore
    assert "!.env.example" in dockerignore
    assert "LALA_PUBLIC_CONTEST_ACCESS=false" in env_example
    assert "LALA_PUBLIC_DEMO_MODE" not in env_example
    assert "COPY apps ./apps" in dockerfile
    assert "uvicorn apps.api.app.main:app" in dockerfile
    assert "COPY . ." not in dockerfile
    assert "param staticSnapshotFallback bool = false" in bicep
    assert "param apiBearerToken string = ''" in bicep
    assert "name: 'api-bearer-token'" in bicep
    assert "uriComponent(postgresAdminPassword)" in bicep
    assert "name: 'LALA_STATIC_SNAPSHOT_FALLBACK'" in bicep
    assert "value: string(staticSnapshotFallback)" in bicep


def test_onprem_docker_and_runtime_hardening_contracts():
    compose = (ROOT / "compose.local.yml").read_text(encoding="utf-8")
    backup_script = (ROOT / "scripts" / "unix" / "backup_docker_postgres.sh").read_text(
        encoding="utf-8"
    )
    drill_script = (
        ROOT / "scripts" / "unix" / "drill_restore_docker_postgres_backup.sh"
    ).read_text(encoding="utf-8")
    monitor_script = (ROOT / "scripts" / "unix" / "onprem_monitor_tick.sh").read_text(
        encoding="utf-8"
    )
    offsite_script = (ROOT / "scripts" / "unix" / "verify_onprem_offsite_backup.sh").read_text(
        encoding="utf-8"
    )
    webhook_script = (ROOT / "scripts" / "unix" / "test_onprem_alert_webhook.sh").read_text(
        encoding="utf-8"
    )
    cloudflare_script = (ROOT / "scripts" / "unix" / "apply_cloudflare_edge_controls.sh").read_text(
        encoding="utf-8"
    )
    standby_script = (ROOT / "scripts" / "unix" / "plan_onprem_standby.sh").read_text(
        encoding="utf-8"
    )
    start_script = (ROOT / "scripts" / "unix" / "start_api.sh").read_text(encoding="utf-8")
    rotation_script = (ROOT / "scripts" / "unix" / "rotate_onprem_logs.sh").read_text(
        encoding="utf-8"
    )

    assert '"127.0.0.1:${LALA_POSTGRES_PORT:-55432}:5432"' in compose
    assert "--require-offsite" in backup_script
    assert "secret_printing=false" in backup_script
    assert "DRILL_DOCKER_POSTGRES_RESTORE" in drill_script
    assert "PostgreSQL init process complete" in drill_script
    assert 'dsn_scheme="postgresql"' in drill_script
    assert 'DB_DSN="$dsn_scheme://' in drill_script
    assert 'echo "$DB_DSN"' not in drill_script
    assert "--webhook-env-name" in monitor_script
    assert "WEBHOOK_URL" in monitor_script
    assert "VERIFY_OFFSITE_BACKUP" in offsite_script
    assert "ALLOW_SAME_FILESYSTEM" in offsite_script
    assert "Offsite backup target must not be inside the repository." in offsite_script
    assert "TEST_ONPREM_ALERT_WEBHOOK" in webhook_script
    assert "WEBHOOK_URL" in webhook_script
    assert "webhook_configured" in webhook_script
    assert "APPLY_CLOUDFLARE_EDGE_CONTROLS" in cloudflare_script
    assert "CLOUDFLARE_API_TOKEN" in cloudflare_script
    assert "http_ratelimit" in cloudflare_script
    assert "cloudflare_token_configured" in cloudflare_script
    assert "cf.colo.id" in cloudflare_script
    assert "LALA_ONPREM_STANDBY_HOST" in standby_script
    assert "applies_changes=false" in standby_script
    assert "--timeout-graceful-shutdown" in start_script
    assert "ROTATE_ONPREM_LOGS" in rotation_script
    assert "secret_printing=false" in rotation_script


def test_naver_map_bridges_forward_camera_updates():
    web_bridge = (ROOT / "apps" / "flutter_app" / "lib" / "lala_map_view_web.dart").read_text(
        encoding="utf-8"
    )
    native_embed = (ROOT / "apps" / "flutter_app" / "web" / "naver-map-embed.html").read_text(
        encoding="utf-8"
    )

    assert "HtmlElementView" in web_bridge
    assert "naver-map-embed.html" in web_bridge
    assert "queryParameters: {'r': '$_revision'}" in web_bridge
    assert "postMessage(" in web_bridge
    assert "event.origin != html.window.location.origin" in web_bridge
    assert "event.source != _frame.contentWindow" not in web_bridge
    assert "decoded['bridgeId'] != _bridgeId" in web_bridge
    assert "lala-naver-map" in web_bridge
    assert "lala-flutter-map-config" in web_bridge

    assert "https://oapi.map.naver.com/openapi/v3/maps.js?ncpKeyId=" in native_embed
    assert 'if (value === "en" || value === "ja") return value' in native_embed
    assert 'startsWith("zh")' in native_embed
    assert '"&language=" + encodeURIComponent(config.language)' in native_embed
    assert "window.LalaMapEmbed" in native_embed
    assert "lala-flutter-map-config" in native_embed
    assert 'bridgeId: String(value.bridgeId || "").trim()' in native_embed
    assert "bridgeId: config.bridgeId" in native_embed
    assert "window.location.hash" not in native_embed
    assert "window.location.search" not in native_embed
    assert 'sendToFlutter({ type: "placeTap", placeId: placeId })' in native_embed
    assert "suppressIdleUntil" in native_embed
    assert 'naver.maps.Event.addListener(map, "idle"' in native_embed
    assert 'type: "cameraIdle"' in native_embed
    assert "map.getBounds()" in native_embed
    assert "bounds.getSW" in native_embed
    assert "bounds.getNE" in native_embed
    assert "naverZoomToAppLevel(map.getZoom())" in native_embed
    assert "logoControl: true" in native_embed
    assert "mapDataControl: true" in native_embed
    assert 'dataset.lalaMapProvider = "naver"' in native_embed
    assert "new naver.maps.Circle" not in native_embed

    combined = web_bridge + native_embed
    assert "NAVER_CLIENT_SECRET" not in combined
    assert "clientSecret" not in combined


def test_flutter_web_smoke_drives_location_flow_and_route_requests():
    unix_script = (ROOT / "scripts" / "unix" / "smoke_flutter_web.sh").read_text(encoding="utf-8")
    windows_script = (ROOT / "scripts" / "windows" / "smoke_flutter_web.ps1").read_text(
        encoding="utf-8"
    )

    for script in (unix_script, windows_script):
        assert "grantPermissions(['geolocation']" in script
        assert "setGeolocation" in script
        assert "page.reload" in script
        assert "page.mouse.click" not in script
        assert "37.5665" in script
        assert "126.978" in script
        assert "37.2636" in script
        assert "127.0286" in script
        assert "default location" in script
        assert "flutter-web-requests.txt" in script
        assert "=> [200]" in script or r"=> \[200\]" in script
        assert "/api/v1/places" in script
        assert "/api/v1/weather" in script
        assert "/api/v1/plans/intervention" in script
        assert "/api/v1/plans/daily" in script
        assert "/api/v1/docents/script" in script
    assert "--web-url" in unix_script
    assert "-WebUrl" in windows_script
    assert "CODEX_PWCLI" in unix_script
    assert "playwright_cli_npx_wrapper.sh" in unix_script
    assert "npx --yes --package @playwright/cli playwright-cli" in unix_script
    assert "flutter-web-api-responses.json" in unix_script
    assert "Flutter places response was not DB-backed." in unix_script
    assert "Flutter places response did not use PostGIS." in unix_script
    assert "Flutter weather response did not include AirKorea source." in unix_script
    assert "Flutter docent script did not include the live place name." in unix_script
    assert "Flutter docent response missed live grounding context." in unix_script
    assert "Flutter docent script exposed internal evidence labels." in unix_script
    assert "Flutter docent script exposed raw score values." in unix_script
    assert "Flutter docent script missed local spending context." in unix_script
    assert "Flutter docent script missed small merchant route context." in unix_script
    assert "Flutter docent script missed official data grounding." in unix_script
    assert "Flutter docent script missed route action context." in unix_script
    assert "Flutter docent script did not include the captured PM10 value." in unix_script
    assert "Flutter docent script did not include the captured PM2.5 value." in unix_script
    # The unix marker contract moved into a shared validator (iframe bridge,
    # pin-first clustering, live-count reconciliation); keep guarding it there.
    marker_contract = (
        ROOT / "scripts" / "unix" / "_flutter_web_marker_contract.py"
    ).read_text(encoding="utf-8")
    assert "_flutter_web_marker_contract.py" in unix_script
    assert 'FAIL_PREFIX = "Flutter location flow"' in marker_contract
    assert "rendered no real map pins or clusters." in marker_contract
    assert "marker rendering did not reconcile with the live place count" in marker_contract
    assert "clustered a sparse zoomed-in map before the far-zoom boundary" in marker_contract
    assert "rendered markers in both the map iframe and the top document." in marker_contract
    verify_repo_script = (ROOT / "scripts" / "unix" / "verify_repo.sh").read_text(encoding="utf-8")
    assert "test_flutter_web_marker_contract.sh" in verify_repo_script


def test_paid_smoke_requires_authenticated_api_key():
    script = (ROOT / "scripts" / "windows" / "smoke_api.ps1").read_text(encoding="utf-8")
    start_script = (ROOT / "scripts" / "windows" / "start_api.ps1").read_text(encoding="utf-8")
    db_schema_script = (ROOT / "scripts" / "windows" / "verify_db_schema.ps1").read_text(
        encoding="utf-8"
    )
    db_resources_script = (ROOT / "scripts" / "windows" / "verify_db_resources.ps1").read_text(
        encoding="utf-8"
    )
    db_rollout_plan_script = (ROOT / "scripts" / "windows" / "plan_db_rollout.ps1").read_text(
        encoding="utf-8"
    )
    observability_plan_script = (ROOT / "scripts" / "windows" / "plan_observability.ps1").read_text(
        encoding="utf-8"
    )
    key_vault_reuse_script = (ROOT / "scripts" / "windows" / "plan_key_vault_reuse.ps1").read_text(
        encoding="utf-8"
    )
    place_score_batch_script = (
        ROOT / "scripts" / "windows" / "plan_place_score_batch.ps1"
    ).read_text(encoding="utf-8")
    review_mention_ingest_script = (
        ROOT / "scripts" / "windows" / "plan_review_mention_ingest.ps1"
    ).read_text(encoding="utf-8")
    review_attribute_batch_script = (
        ROOT / "scripts" / "windows" / "plan_review_attribute_batch.ps1"
    ).read_text(encoding="utf-8")
    franchise_identity_batch_script = (
        ROOT / "scripts" / "windows" / "plan_franchise_identity_batch.ps1"
    ).read_text(encoding="utf-8")
    rag_index_unix_script = (ROOT / "scripts" / "unix" / "plan_rag_index.sh").read_text(
        encoding="utf-8"
    )
    place_ai_enrichment_script = (
        ROOT / "scripts" / "windows" / "plan_place_ai_enrichment.ps1"
    ).read_text(encoding="utf-8")
    place_local_enrichment_script = (
        ROOT / "scripts" / "windows" / "plan_place_local_enrichment.ps1"
    ).read_text(encoding="utf-8")
    tour_api_ingest_script = (ROOT / "scripts" / "windows" / "plan_tour_api_ingest.ps1").read_text(
        encoding="utf-8"
    )
    culture_info_ingest_script = (
        ROOT / "scripts" / "windows" / "plan_culture_info_ingest.ps1"
    ).read_text(encoding="utf-8")
    kopis_ingest_script = (ROOT / "scripts" / "windows" / "plan_kopis_ingest.ps1").read_text(
        encoding="utf-8"
    )
    card_spending_ingest_script = (
        ROOT / "scripts" / "windows" / "plan_card_spending_file_ingest.ps1"
    ).read_text(encoding="utf-8")
    access_log_inspect_script = (ROOT / "scripts" / "windows" / "inspect_access_log.ps1").read_text(
        encoding="utf-8"
    )
    apply_sql_script = (ROOT / "scripts" / "windows" / "apply_canonical_sql.ps1").read_text(
        encoding="utf-8"
    )
    flutter_client_script = (ROOT / "scripts" / "windows" / "verify_flutter_client.ps1").read_text(
        encoding="utf-8"
    )
    flutter_web_smoke_script = (ROOT / "scripts" / "windows" / "smoke_flutter_web.ps1").read_text(
        encoding="utf-8"
    )
    dev_reset_script = (ROOT / "scripts" / "windows" / "plan_dev_reset.ps1").read_text(
        encoding="utf-8"
    )
    worker_smoke_script = (ROOT / "scripts" / "windows" / "smoke_workers.ps1").read_text(
        encoding="utf-8"
    )
    oauth_smoke_script = (ROOT / "scripts" / "windows" / "smoke_oauth_jwt.ps1").read_text(
        encoding="utf-8"
    )
    worker_contracts = (ROOT / "apps" / "workers" / "app" / "contracts.py").read_text(
        encoding="utf-8"
    )
    oauth_smoke_tool = (ROOT / "apps" / "api" / "app" / "tools" / "smoke_oauth_jwt.py").read_text(
        encoding="utf-8"
    )
    apply_sql_tool = (ROOT / "apps" / "api" / "app" / "tools" / "apply_canonical_sql.py").read_text(
        encoding="utf-8"
    )

    assert "[string]$KeyVaultUrl" in script
    assert "[string]$CorsOrigin" in script
    assert "[string]$KeyVaultUrl" in start_script
    assert "[string]$AccessLogPath" in start_script
    assert ".vault.azure.net" in script
    assert ".vault.azure.net" in start_script
    assert "LALA_ALLOWED_KEY_VAULT_HOSTS" in script
    assert "LALA_ALLOWED_KEY_VAULT_HOSTS" in start_script
    assert 'Contains("onmu")' in script
    assert 'Contains("onmu")' in start_script
    assert "cors-allow-origins" in start_script
    assert "LALA_ACCESS_LOG_PATH" in start_script
    assert "if ($PaidDependency)" in script
    assert "Invoke-SmokeReadyz" in script
    assert "runtime_mode=" in script
    assert "identity=" in script
    assert "LALA_SMOKE_BEARER_TOKEN" in script
    assert "LALA_SMOKE_API_KEY" in script
    assert "Invoke-SmokeCorsPreflight" in script
    assert "Matching client auth is required for paid dependency smoke" in script
    assert "--no-access-log" in start_script
    assert "DB_DSN value is never printed by this script." in db_schema_script
    assert "Write-Host $env:DB_DSN" not in db_schema_script
    assert "$toolArgs" in db_schema_script
    assert "Secret values are never printed by this script." in db_resources_script
    assert "secret show" not in db_resources_script
    assert "db-dsn" in db_resources_script
    assert "does not create Azure resources" in db_rollout_plan_script
    assert "apps.api.app.tools.plan_db_rollout" in db_rollout_plan_script
    assert "secret show" not in db_rollout_plan_script
    assert "does not create dashboards" in observability_plan_script
    assert "apps.api.app.tools.plan_observability" in observability_plan_script
    assert "secret show" not in observability_plan_script
    assert "does not read or print secret values" in key_vault_reuse_script
    assert "apps.api.app.tools.plan_key_vault_reuse" in key_vault_reuse_script
    assert "secret show" not in key_vault_reuse_script
    assert "secret set" not in key_vault_reuse_script
    assert "apps.api.app.tools.run_place_score_batch" in place_score_batch_script
    assert "ALLOW_PLACE_SCORE_BATCH_APPLY=1" in place_score_batch_script
    assert "DB_DSN value is never printed by this script." in place_score_batch_script
    assert "secret show" not in place_score_batch_script
    assert "Write-Host $env:DB_DSN" not in place_score_batch_script
    assert "apps.api.app.tools.run_review_mention_ingest" in review_mention_ingest_script
    assert "ALLOW_REVIEW_MENTION_INGEST_APPLY=1" in review_mention_ingest_script
    assert "DB_DSN value is never printed by this script." in review_mention_ingest_script
    assert "secret show" not in review_mention_ingest_script
    assert "Write-Host $env:DB_DSN" not in review_mention_ingest_script
    assert "apps.api.app.tools.run_review_attribute_batch" in review_attribute_batch_script
    assert "ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1" in review_attribute_batch_script
    assert (
        "OPENAI_API_KEY and DB_DSN values are never printed by this script."
        in review_attribute_batch_script
    )
    assert "secret show" not in review_attribute_batch_script
    assert "Write-Host $env:DB_DSN" not in review_attribute_batch_script
    assert "Write-Host $env:OPENAI_API_KEY" not in review_attribute_batch_script
    assert "apps.api.app.tools.run_franchise_identity_batch" in franchise_identity_batch_script
    assert "ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY=1" in franchise_identity_batch_script
    assert "DB_DSN value is never printed by this script." in franchise_identity_batch_script
    assert "secret show" not in franchise_identity_batch_script
    assert "Write-Host $env:DB_DSN" not in franchise_identity_batch_script
    assert "apps.api.app.tools.run_rag_index" in rag_index_unix_script
    assert "ALLOW_RAG_INDEX_APPLY=1" in rag_index_unix_script
    assert (
        "DB_DSN and OPENAI_API_KEY values are never printed by this script."
        in rag_index_unix_script
    )
    assert "secret show" not in rag_index_unix_script
    assert 'echo "$DB_DSN"' not in rag_index_unix_script
    assert 'echo "$OPENAI_API_KEY"' not in rag_index_unix_script
    assert "apps.api.app.tools.enrich_place_ai_columns" in place_ai_enrichment_script
    assert "ALLOW_AI_PLACE_ENRICHMENT_APPLY=1" in place_ai_enrichment_script
    assert (
        "OPENAI_API_KEY and DB_DSN values are never printed by this script."
        in place_ai_enrichment_script
    )
    assert "secret show" not in place_ai_enrichment_script
    assert "Write-Host $env:DB_DSN" not in place_ai_enrichment_script
    assert "Write-Host $env:OPENAI_API_KEY" not in place_ai_enrichment_script
    assert "apps.api.app.tools.enrich_place_local_columns" in place_local_enrichment_script
    assert "ALLOW_LOCAL_PLACE_ENRICHMENT_APPLY=1" in place_local_enrichment_script
    assert "DB_DSN value is never printed by this script." in place_local_enrichment_script
    assert "secret show" not in place_local_enrichment_script
    assert "Write-Host $env:DB_DSN" not in place_local_enrichment_script
    assert "apps.api.app.tools.run_tour_api_ingest" in tour_api_ingest_script
    assert "ALLOW_TOUR_API_INGEST_APPLY=1" in tour_api_ingest_script
    assert (
        "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
        in tour_api_ingest_script
    )
    assert "secret show" not in tour_api_ingest_script
    assert "Write-Host $env:DB_DSN" not in tour_api_ingest_script
    assert "Write-Host $env:PUBLIC_DATA_SERVICE_KEY" not in tour_api_ingest_script
    assert "apps.api.app.tools.run_culture_info_ingest" in culture_info_ingest_script
    assert "ALLOW_CULTURE_INFO_INGEST_APPLY=1" in culture_info_ingest_script
    assert (
        "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
        in culture_info_ingest_script
    )
    assert "secret show" not in culture_info_ingest_script
    assert "Write-Host $env:DB_DSN" not in culture_info_ingest_script
    assert "Write-Host $env:PUBLIC_DATA_SERVICE_KEY" not in culture_info_ingest_script
    assert "apps.api.app.tools.run_kopis_ingest" in kopis_ingest_script
    assert "ALLOW_KOPIS_INGEST_APPLY=1" in kopis_ingest_script
    assert (
        "KOPIS_API_KEY and DB_DSN values are never printed by this script." in kopis_ingest_script
    )
    assert "secret show" not in kopis_ingest_script
    assert "Write-Host $env:DB_DSN" not in kopis_ingest_script
    assert "Write-Host $env:KOPIS_API_KEY" not in kopis_ingest_script
    assert "apps.api.app.tools.run_card_spending_file_ingest" in card_spending_ingest_script
    assert "ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1" in card_spending_ingest_script
    assert "DB_DSN value is never printed by this script." in card_spending_ingest_script
    assert "secret show" not in card_spending_ingest_script
    assert "Write-Host $env:DB_DSN" not in card_spending_ingest_script
    assert "read-only and prints only bounded access-log fields" in access_log_inspect_script
    assert "apps.api.app.tools.inspect_access_log" in access_log_inspect_script
    assert "secret show" not in access_log_inspect_script
    assert "Write-Host $env:DB_DSN" not in access_log_inspect_script
    assert "Default mode is dry-run plan only." in apply_sql_script
    assert "Write-Host $env:DB_DSN" not in apply_sql_script
    assert "ALLOW_DEV_RESET_APPLY=1" in dev_reset_script
    assert "DB_DSN value is never printed by this script." in dev_reset_script
    assert "apps.api.app.tools.plan_dev_reset" in dev_reset_script
    assert "Write-Host $env:DB_DSN" not in dev_reset_script
    assert "-m apps.workers.app.cli" in worker_smoke_script
    assert "--dry-run" in worker_smoke_script
    assert "preflight" in worker_smoke_script
    assert "Write-Host $env:DB_DSN" not in worker_smoke_script
    assert "apps.api.app.tools.smoke_oauth_jwt" in oauth_smoke_script
    assert "local JWKS server" in oauth_smoke_script
    assert "az " not in oauth_smoke_script
    assert "LALA_SMOKE_BEARER_TOKEN" in oauth_smoke_tool
    assert "API_BEARER_TOKEN" in oauth_smoke_tool
    assert "secret show" not in oauth_smoke_tool
    assert "playwright-cli" in flutter_web_smoke_script
    assert "--no-wasm-dry-run" in flutter_web_smoke_script
    assert 'KEY_VAULT_URL", ""' in flutter_web_smoke_script
    assert 'DB_DSN", ""' in flutter_web_smoke_script
    assert 'LALA_ENABLE_LIVE_AI", "false"' in flutter_web_smoke_script
    assert 'LALA_ENABLE_LIVE_SPEECH", "false"' in flutter_web_smoke_script
    assert "CORS_ALLOW_ORIGINS" in flutter_web_smoke_script
    assert "/api/v1/docents/script" in flutter_web_smoke_script
    assert "secret show" not in flutter_web_smoke_script
    assert "ALLOW_WORKER_MUTATION" in worker_contracts
    assert "ALLOW_CANONICAL_SQL_APPLY" in apply_sql_tool
    assert "APPLY_CANONICAL_SQL" in apply_sql_tool
    assert "Dart SDK is not available" in flutter_client_script
    assert "dart analyze" in flutter_client_script
    assert "dart test" in flutter_client_script


def test_unix_scripts_have_safe_operational_guards():
    unix_dir = ROOT / "scripts" / "unix"
    scripts = {path.name: path.read_text(encoding="utf-8") for path in unix_dir.glob("*.sh")}

    assert {
        "_common.sh",
        "apply_canonical_sql.sh",
        "bootstrap_local_mvp_db.sh",
        "export_openapi.sh",
        "export_public_mvp_snapshot.sh",
        "handoff_report.sh",
        "inspect_access_log.sh",
        "plan_db_rollout.sh",
        "plan_dev_reset.sh",
        "plan_identity_rollout.sh",
        "plan_key_vault_reuse.sh",
        "plan_observability.sh",
        "plan_franchise_reference_ingest.sh",
        "plan_place_ai_enrichment.sh",
        "plan_place_local_enrichment.sh",
        "plan_rag_index.sh",
        "plan_place_score_batch.sh",
        "plan_review_mention_ingest.sh",
        "plan_review_attribute_batch.sh",
        "plan_franchise_identity_batch.sh",
        "plan_card_spending_file_ingest.sh",
        "plan_culture_info_ingest.sh",
        "plan_kopis_ingest.sh",
        "plan_tour_api_ingest.sh",
        "plan_weather_observation_refresh.sh",
        "smoke_api.sh",
        "smoke_api_matrix.sh",
        "smoke_oauth_jwt.sh",
        "smoke_workers.sh",
        "start_api.sh",
        "verify_azure_resources.sh",
        "verify_db_resources.sh",
        "verify_db_schema.sh",
        "verify_flutter_client.sh",
        "verify_repo.sh",
    }.issubset(scripts)

    assert ".vault.azure.net" in scripts["_common.sh"]
    assert "LALA_ALLOWED_KEY_VAULT_HOSTS" in scripts["_common.sh"]
    assert "${!name+x}" in scripts["_common.sh"]
    assert '"$vault_name" == *onmu*' in scripts["_common.sh"]
    assert "Unsupported Key Vault URL for LALA-next" in scripts["_common.sh"]
    assert "Worker smoke uses dry-run only" in scripts["smoke_workers.sh"]
    assert "--dry-run" in scripts["smoke_workers.sh"]
    assert "preflight" in scripts["smoke_workers.sh"]
    assert "Live Azure checks are intentionally excluded" in scripts["verify_repo.sh"]
    assert "verify_flutter_client.sh" in scripts["verify_repo.sh"]
    assert "smoke_oauth_jwt.sh" in scripts["verify_repo.sh"]
    assert "local JWKS server" in scripts["smoke_oauth_jwt.sh"]
    assert "apps.api.app.tools.smoke_oauth_jwt" in scripts["smoke_oauth_jwt.sh"]
    assert "az " not in scripts["smoke_oauth_jwt.sh"]
    assert "Dart SDK is not available" in scripts["verify_flutter_client.sh"]
    assert "dart analyze" in scripts["verify_flutter_client.sh"]
    assert "dart test" in scripts["verify_flutter_client.sh"]
    assert "Risk Gates" in scripts["handoff_report.sh"]
    assert "OpenAPI Compatibility" in scripts["handoff_report.sh"]
    assert "check_openapi_compat" in scripts["handoff_report.sh"]
    assert "verify_db_resources.sh" in scripts["handoff_report.sh"]
    assert "secret show" not in scripts["handoff_report.sh"]
    assert "inspect_access_log" in scripts["inspect_access_log.sh"]
    assert "read-only and prints only bounded access-log fields" in scripts["inspect_access_log.sh"]
    assert "secret show" not in scripts["inspect_access_log.sh"]
    assert "plan_db_rollout" in scripts["plan_db_rollout.sh"]
    assert "does not create Azure resources" in scripts["plan_db_rollout.sh"]
    assert "plan_db_rollout.sh" in scripts["verify_repo.sh"]
    assert "bootstrap_local_mvp_db.sh" in scripts["verify_repo.sh"]
    assert "plan_observability" in scripts["plan_observability.sh"]
    assert "does not create dashboards" in scripts["plan_observability.sh"]
    assert "plan_observability.sh" in scripts["verify_repo.sh"]
    assert "plan_identity_rollout" in scripts["plan_identity_rollout.sh"]
    assert "does not create Entra apps" in scripts["plan_identity_rollout.sh"]
    assert "plan_identity_rollout.sh" in scripts["verify_repo.sh"]
    assert "plan_key_vault_reuse" in scripts["plan_key_vault_reuse.sh"]
    assert "does not read or print secret values" in scripts["plan_key_vault_reuse.sh"]
    assert "plan_key_vault_reuse.sh" in scripts["verify_repo.sh"]
    assert "secret show" not in scripts["plan_key_vault_reuse.sh"]
    assert "secret set" not in scripts["plan_key_vault_reuse.sh"]
    assert "run_place_score_batch" in scripts["plan_place_score_batch.sh"]
    assert "plan_place_score_batch.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_PLACE_SCORE_BATCH_APPLY=1" in scripts["plan_place_score_batch.sh"]
    assert "--confirm APPLY_PLACE_SCORE_BATCH" in scripts["plan_place_score_batch.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["plan_place_score_batch.sh"]
    assert "run_review_mention_ingest" in scripts["plan_review_mention_ingest.sh"]
    assert "plan_review_mention_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_REVIEW_MENTION_INGEST_APPLY=1" in scripts["plan_review_mention_ingest.sh"]
    assert "--confirm APPLY_REVIEW_MENTION_INGEST" in scripts["plan_review_mention_ingest.sh"]
    assert (
        "DB_DSN value is never printed by this script." in scripts["plan_review_mention_ingest.sh"]
    )
    assert "run_place_mention_attribute_repair" in scripts["repair_place_mention_attributes.sh"]
    assert "repair_place_mention_attributes.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_PLACE_MENTION_REPAIR_APPLY=1" in scripts["repair_place_mention_attributes.sh"]
    assert (
        "--confirm APPLY_PLACE_MENTION_ATTRIBUTE_REPAIR"
        in scripts["repair_place_mention_attributes.sh"]
    )
    assert (
        "DB_DSN value is never printed by this script."
        in scripts["repair_place_mention_attributes.sh"]
    )
    assert "run_review_attribute_batch" in scripts["plan_review_attribute_batch.sh"]
    assert "plan_review_attribute_batch.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1" in scripts["plan_review_attribute_batch.sh"]
    assert "--confirm APPLY_REVIEW_ATTRIBUTE_BATCH" in scripts["plan_review_attribute_batch.sh"]
    assert (
        "OPENAI_API_KEY and DB_DSN values are never printed by this script."
        in scripts["plan_review_attribute_batch.sh"]
    )
    assert "run_franchise_identity_batch" in scripts["plan_franchise_identity_batch.sh"]
    assert "plan_franchise_identity_batch.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY=1" in scripts["plan_franchise_identity_batch.sh"]
    assert "--confirm APPLY_FRANCHISE_IDENTITY_BATCH" in scripts["plan_franchise_identity_batch.sh"]
    assert (
        "DB_DSN value is never printed by this script."
        in scripts["plan_franchise_identity_batch.sh"]
    )
    assert "load_env_names_from_file" in scripts["plan_franchise_identity_batch.sh"]
    assert "load_lala_key_vault_secrets" in scripts["plan_franchise_identity_batch.sh"]
    assert "run_weather_observation_refresh" in scripts["plan_weather_observation_refresh.sh"]
    assert "plan_weather_observation_refresh.sh" in scripts["verify_repo.sh"]
    assert (
        "ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1"
        in scripts["plan_weather_observation_refresh.sh"]
    )
    assert (
        "--confirm APPLY_WEATHER_OBSERVATION_REFRESH"
        in scripts["plan_weather_observation_refresh.sh"]
    )
    assert (
        "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
        in scripts["plan_weather_observation_refresh.sh"]
    )
    assert "run_franchise_reference_ingest" in scripts["plan_franchise_reference_ingest.sh"]
    assert "plan_franchise_reference_ingest.sh" in scripts["verify_repo.sh"]
    assert (
        "ALLOW_FRANCHISE_REFERENCE_INGEST_APPLY=1" in scripts["plan_franchise_reference_ingest.sh"]
    )
    assert (
        "--confirm APPLY_FRANCHISE_REFERENCE_INGEST"
        in scripts["plan_franchise_reference_ingest.sh"]
    )
    assert (
        "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
        in scripts["plan_franchise_reference_ingest.sh"]
    )
    assert "load_env_names_from_file" in scripts["plan_franchise_reference_ingest.sh"]
    assert "load_lala_key_vault_secrets" in scripts["plan_franchise_reference_ingest.sh"]
    assert "run_rag_index" in scripts["plan_rag_index.sh"]
    assert "plan_rag_index.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_RAG_INDEX_APPLY=1" in scripts["plan_rag_index.sh"]
    assert "--confirm APPLY_RAG_INDEX" in scripts["plan_rag_index.sh"]
    assert (
        "DB_DSN and OPENAI_API_KEY values are never printed by this script."
        in scripts["plan_rag_index.sh"]
    )
    assert "enrich_place_ai_columns" in scripts["plan_place_ai_enrichment.sh"]
    assert "plan_place_ai_enrichment.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_AI_PLACE_ENRICHMENT_APPLY=1" in scripts["plan_place_ai_enrichment.sh"]
    assert "--confirm APPLY_AI_PLACE_ENRICHMENT" in scripts["plan_place_ai_enrichment.sh"]
    assert (
        "OPENAI_API_KEY and DB_DSN values are never printed by this script."
        in scripts["plan_place_ai_enrichment.sh"]
    )
    assert "enrich_place_local_columns" in scripts["plan_place_local_enrichment.sh"]
    assert "plan_place_local_enrichment.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_LOCAL_PLACE_ENRICHMENT_APPLY=1" in scripts["plan_place_local_enrichment.sh"]
    assert "--confirm APPLY_LOCAL_PLACE_ENRICHMENT" in scripts["plan_place_local_enrichment.sh"]
    assert (
        "DB_DSN value is never printed by this script." in scripts["plan_place_local_enrichment.sh"]
    )
    assert "export_public_mvp_snapshot" in scripts["export_public_mvp_snapshot.sh"]
    assert "export_public_mvp_snapshot.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE=1" in scripts["export_public_mvp_snapshot.sh"]
    assert "--confirm WRITE_PUBLIC_MVP_SNAPSHOT" in scripts["export_public_mvp_snapshot.sh"]
    assert (
        "DB_DSN value is never printed by this script." in scripts["export_public_mvp_snapshot.sh"]
    )
    assert "run_tour_api_ingest" in scripts["plan_tour_api_ingest.sh"]
    assert "plan_tour_api_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_TOUR_API_INGEST_APPLY=1" in scripts["plan_tour_api_ingest.sh"]
    assert "--confirm APPLY_TOUR_API_INGEST" in scripts["plan_tour_api_ingest.sh"]
    assert (
        "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
        in scripts["plan_tour_api_ingest.sh"]
    )
    assert "load_env_names_from_file" in scripts["plan_tour_api_ingest.sh"]
    assert "load_lala_key_vault_secrets" in scripts["plan_tour_api_ingest.sh"]
    assert "run_culture_info_ingest" in scripts["plan_culture_info_ingest.sh"]
    assert "plan_culture_info_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_CULTURE_INFO_INGEST_APPLY=1" in scripts["plan_culture_info_ingest.sh"]
    assert "--confirm APPLY_CULTURE_INFO_INGEST" in scripts["plan_culture_info_ingest.sh"]
    assert (
        "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
        in scripts["plan_culture_info_ingest.sh"]
    )
    assert "load_env_names_from_file" in scripts["plan_culture_info_ingest.sh"]
    assert "load_lala_key_vault_secrets" in scripts["plan_culture_info_ingest.sh"]
    assert "run_kopis_ingest" in scripts["plan_kopis_ingest.sh"]
    assert "plan_kopis_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_KOPIS_INGEST_APPLY=1" in scripts["plan_kopis_ingest.sh"]
    assert "--confirm APPLY_KOPIS_INGEST" in scripts["plan_kopis_ingest.sh"]
    assert (
        "KOPIS_API_KEY and DB_DSN values are never printed by this script."
        in scripts["plan_kopis_ingest.sh"]
    )
    assert "load_env_names_from_file" in scripts["plan_kopis_ingest.sh"]
    assert "load_lala_key_vault_secrets" in scripts["plan_kopis_ingest.sh"]
    assert "run_card_spending_file_ingest" in scripts["plan_card_spending_file_ingest.sh"]
    assert "plan_card_spending_file_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1" in scripts["plan_card_spending_file_ingest.sh"]
    assert (
        "--confirm APPLY_CARD_SPENDING_FILE_INGEST" in scripts["plan_card_spending_file_ingest.sh"]
    )
    assert (
        "DB_DSN value is never printed by this script."
        in scripts["plan_card_spending_file_ingest.sh"]
    )
    assert "load_env_names_from_file" in scripts["plan_card_spending_file_ingest.sh"]
    assert "load_lala_key_vault_secrets" in scripts["plan_card_spending_file_ingest.sh"]
    assert "--check-compat" in scripts["export_openapi.sh"]
    assert "plan_dev_reset" in scripts["plan_dev_reset.sh"]
    assert "plan_dev_reset.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_DEV_RESET_APPLY=1" in scripts["plan_dev_reset.sh"]
    assert "--confirm APPLY_DEV_RESET_SQL" in scripts["plan_dev_reset.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["plan_dev_reset.sh"]
    assert "load_env_names_from_file" in scripts["plan_dev_reset.sh"]
    assert "load_lala_key_vault_secrets" in scripts["plan_dev_reset.sh"]
    assert "secret list" in scripts["verify_db_resources.sh"]
    assert "secret show" not in scripts["verify_db_resources.sh"]
    assert "db-dsn" in scripts["verify_db_resources.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["verify_db_schema.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["apply_canonical_sql.sh"]
    assert "--confirm APPLY_CANONICAL_SQL" in scripts["apply_canonical_sql.sh"]
    assert "load_env_names_from_file" in scripts["apply_canonical_sql.sh"]
    assert "load_lala_key_vault_secrets" in scripts["apply_canonical_sql.sh"]
    assert "compose.local.yml" in scripts["bootstrap_local_mvp_db.sh"]
    assert "LALA_POSTGRES_PASSWORD is required" in scripts["bootstrap_local_mvp_db.sh"]
    assert (
        "DB_DSN and LALA_POSTGRES_PASSWORD values are never printed by this script."
        in scripts["bootstrap_local_mvp_db.sh"]
    )
    assert "ALLOW_CANONICAL_SQL_APPLY=1" in scripts["bootstrap_local_mvp_db.sh"]
    assert "ALLOW_DEV_RESET_APPLY=1" in scripts["bootstrap_local_mvp_db.sh"]
    assert "ALLOW_PLACE_SCORE_BATCH_APPLY=1" in scripts["bootstrap_local_mvp_db.sh"]
    assert "ALLOW_RAG_INDEX_APPLY=1" in scripts["bootstrap_local_mvp_db.sh"]
    assert "ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE=1" in scripts["bootstrap_local_mvp_db.sh"]
    assert "--paid-dependency" in scripts["smoke_api.sh"]
    assert "--cors-origin" in scripts["smoke_api.sh"]
    assert "smoke_cors_preflight" in scripts["smoke_api.sh"]
    assert "smoke_readyz" in scripts["smoke_api.sh"]
    assert "runtime_mode=" in scripts["smoke_api.sh"]
    assert "identity=" in scripts["smoke_api.sh"]
    assert "LALA_SMOKE_BEARER_TOKEN" in scripts["smoke_api.sh"]
    assert "LALA_SMOKE_API_KEY" in scripts["smoke_api.sh"]
    assert "Matching client auth is required for paid dependency smoke" in scripts["smoke_api.sh"]
    assert "write_auth_config" in scripts["smoke_api.sh"]
    assert 'CURL_AUTH_ARGS=(-K "$AUTH_CONFIG_FILE")' in scripts["smoke_api.sh"]
    assert "AUTH_HEADER=(-H" not in scripts["smoke_api.sh"]
    assert "apps.api.app.tools.smoke_api_matrix" in scripts["smoke_api_matrix.sh"]
    assert (
        "Runs a bounded deploy or wider live API matrix without printing client tokens"
        in scripts["smoke_api_matrix.sh"]
    )
    assert "load_lala_key_vault_secrets" in scripts["smoke_api_matrix.sh"]
    assert "LALA_SMOKE_BEARER_TOKEN" not in scripts["smoke_api_matrix.sh"]
    assert "LALA_SMOKE_API_KEY" not in scripts["smoke_api_matrix.sh"]
    assert "secret show" not in scripts["smoke_api_matrix.sh"]
    assert "--no-access-log" in scripts["start_api.sh"]
    assert "--access-log-path" in scripts["start_api.sh"]
    assert "LALA_ACCESS_LOG_PATH" in scripts["start_api.sh"]
    assert "env_status API_BEARER_TOKEN" in scripts["start_api.sh"]
    assert "env_status CORS_ALLOW_ORIGINS" in scripts["start_api.sh"]
    assert "cors-allow-origins" in scripts["_common.sh"]


def test_unix_scripts_parse_with_bash():
    scripts = sorted((ROOT / "scripts" / "unix").glob("*.sh"))
    result = subprocess.run(
        [usable_bash(), "-n", *[str(path) for path in scripts]],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_key_vault_url_is_lala_owned_and_allowlist_aware(monkeypatch):
    vault_url = "https://example-lala-vault.vault.azure.net/"
    assert is_allowed_key_vault_url(vault_url)
    assert key_vault_name_from_url(vault_url) == "example-lala-vault"

    monkeypatch.setenv("LALA_ALLOWED_KEY_VAULT_HOSTS", "example-lala-vault.vault.azure.net")
    assert is_allowed_key_vault_url(vault_url)
    assert not is_allowed_key_vault_url("https://other-lala-vault.vault.azure.net/")

    assert not is_allowed_key_vault_url("https://onmu-source-vault.vault.azure.net/")
    assert not is_allowed_key_vault_url("http://example-lala-vault.vault.azure.net/")
    assert key_vault_name_from_url("https://onmu-source-vault.vault.azure.net/") == ""
