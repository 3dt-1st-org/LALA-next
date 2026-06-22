from __future__ import annotations

import re
import subprocess
from pathlib import Path

from apps.api.tests._bash import usable_bash

from apps.api.app.core.key_vault import is_allowed_key_vault_url, key_vault_name_from_url

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


def test_repo_docs_and_scripts_do_not_contain_secret_literals():
    patterns = [
        re.compile(r"postgresql://[^\s<>]+:[^\s<>]+@"),
        re.compile(r"https://[a-z0-9-]+\.vault\.azure\.net/?", re.IGNORECASE),
        re.compile(r"^IOS_API_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^API_BEARER_TOKEN[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^POSTGRES_PASSWORD[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^AZURE_OPENAI_API_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
        re.compile(r"^AZURE_OPENAI_KEY[ \t]*=[ \t]*[^#\r\n]+", re.MULTILINE),
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
    workflow = (ROOT / ".github" / "workflows" / "azure-dev-deploy.yml").read_text(
        encoding="utf-8"
    )

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
    assert "SMOKE_BASE_URL=\"https://${API_FQDN}\"" in workflow
    assert 'scripts/unix/smoke_api.sh --base-url "$SMOKE_BASE_URL"' in workflow
    assert 'scripts/unix/smoke_api_matrix.sh --base-url "$SMOKE_BASE_URL" --timeout 25 --profile deploy' in workflow


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
    assert "--web-url \"https://lala-next.cloud/?qa=deployed-web-smoke-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}\"" in workflow
    assert "--require-browser" in workflow
    assert "--fail-on-console-error" in workflow
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


def test_kakao_map_bridges_forward_zoom_camera_updates():
    web_bridge = (ROOT / "apps" / "flutter_app" / "lib" / "kakao_map_view_web.dart").read_text(
        encoding="utf-8"
    )
    native_embed = (ROOT / "apps" / "flutter_app" / "web" / "kakao-map-embed.html").read_text(
        encoding="utf-8"
    )

    assert 'kakao.maps.event.addListener(map, "dragend"' in web_bridge
    assert 'kakao.maps.event.addListener(map, "zoom_changed"' in web_bridge
    assert '"lala-map-camera-idle"' in web_bridge
    assert 'level: map.getLevel()' in web_bridge

    assert 'kakao.maps.event.addListener(map, "dragend"' in native_embed
    assert 'kakao.maps.event.addListener(map, "zoom_changed"' in native_embed
    assert 'type: "cameraIdle"' in native_embed
    assert 'level: map.getLevel()' in native_embed


def test_flutter_web_smoke_drives_location_flow_and_route_requests():
    unix_script = (ROOT / "scripts" / "unix" / "smoke_flutter_web.sh").read_text(
        encoding="utf-8"
    )
    windows_script = (
        ROOT / "scripts" / "windows" / "smoke_flutter_web.ps1"
    ).read_text(encoding="utf-8")

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
    assert "Flutter location flow rendered no real map pins." in unix_script
    assert "Flutter location flow rendered only clusters without place pins." in unix_script
    assert "Flutter initial location map clustered places before the user zoomed out." in unix_script


def test_paid_smoke_requires_authenticated_api_key():
    script = (ROOT / "scripts" / "windows" / "smoke_api.ps1").read_text(encoding="utf-8")
    start_script = (ROOT / "scripts" / "windows" / "start_api.ps1").read_text(encoding="utf-8")
    db_schema_script = (ROOT / "scripts" / "windows" / "verify_db_schema.ps1").read_text(
        encoding="utf-8"
    )
    db_resources_script = (
        ROOT / "scripts" / "windows" / "verify_db_resources.ps1"
    ).read_text(encoding="utf-8")
    db_rollout_plan_script = (
        ROOT / "scripts" / "windows" / "plan_db_rollout.ps1"
    ).read_text(encoding="utf-8")
    observability_plan_script = (
        ROOT / "scripts" / "windows" / "plan_observability.ps1"
    ).read_text(encoding="utf-8")
    key_vault_reuse_script = (
        ROOT / "scripts" / "windows" / "plan_key_vault_reuse.ps1"
    ).read_text(encoding="utf-8")
    place_score_batch_script = (
        ROOT / "scripts" / "windows" / "plan_place_score_batch.ps1"
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
    docent_qa_script = (
        ROOT / "scripts" / "windows" / "plan_docent_qa.ps1"
    ).read_text(encoding="utf-8")
    tour_api_ingest_script = (
        ROOT / "scripts" / "windows" / "plan_tour_api_ingest.ps1"
    ).read_text(encoding="utf-8")
    culture_info_ingest_script = (
        ROOT / "scripts" / "windows" / "plan_culture_info_ingest.ps1"
    ).read_text(encoding="utf-8")
    kopis_ingest_script = (ROOT / "scripts" / "windows" / "plan_kopis_ingest.ps1").read_text(
        encoding="utf-8"
    )
    weather_refresh_script = (
        ROOT / "scripts" / "windows" / "plan_weather_observation_refresh.ps1"
    ).read_text(encoding="utf-8")
    review_mention_ingest_script = (
        ROOT / "scripts" / "windows" / "plan_review_mention_ingest.ps1"
    ).read_text(encoding="utf-8")
    review_attribute_batch_script = (
        ROOT / "scripts" / "windows" / "plan_review_attribute_batch.ps1"
    ).read_text(encoding="utf-8")
    card_spending_ingest_script = (
        ROOT / "scripts" / "windows" / "plan_card_spending_file_ingest.ps1"
    ).read_text(encoding="utf-8")
    access_log_inspect_script = (
        ROOT / "scripts" / "windows" / "inspect_access_log.ps1"
    ).read_text(encoding="utf-8")
    apply_sql_script = (ROOT / "scripts" / "windows" / "apply_canonical_sql.ps1").read_text(
        encoding="utf-8"
    )
    flutter_client_script = (
        ROOT / "scripts" / "windows" / "verify_flutter_client.ps1"
    ).read_text(encoding="utf-8")
    flutter_web_smoke_script = (
        ROOT / "scripts" / "windows" / "smoke_flutter_web.ps1"
    ).read_text(encoding="utf-8")
    dev_reset_script = (ROOT / "scripts" / "windows" / "plan_dev_reset.ps1").read_text(
        encoding="utf-8"
    )
    worker_smoke_script = (
        ROOT / "scripts" / "windows" / "smoke_workers.ps1"
    ).read_text(encoding="utf-8")
    oauth_smoke_script = (
        ROOT / "scripts" / "windows" / "smoke_oauth_jwt.ps1"
    ).read_text(encoding="utf-8")
    worker_contracts = (
        ROOT / "apps" / "workers" / "app" / "contracts.py"
    ).read_text(encoding="utf-8")
    oauth_smoke_tool = (
        ROOT / "apps" / "api" / "app" / "tools" / "smoke_oauth_jwt.py"
    ).read_text(encoding="utf-8")
    apply_sql_tool = (
        ROOT / "apps" / "api" / "app" / "tools" / "apply_canonical_sql.py"
    ).read_text(encoding="utf-8")

    assert "[string]$KeyVaultUrl" in script
    assert "[string]$CorsOrigin" in script
    assert "[string]$KeyVaultUrl" in start_script
    assert "[string]$AccessLogPath" in start_script
    assert ".vault.azure.net" in script
    assert ".vault.azure.net" in start_script
    assert "LALA_ALLOWED_KEY_VAULT_HOSTS" in script
    assert "LALA_ALLOWED_KEY_VAULT_HOSTS" in start_script
    assert "Contains(\"onmu\")" in script
    assert "Contains(\"onmu\")" in start_script
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
    assert "apps.api.app.tools.run_franchise_identity_batch" in franchise_identity_batch_script
    assert "ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY=1" in franchise_identity_batch_script
    assert "DB_DSN value is never printed by this script." in franchise_identity_batch_script
    assert "secret show" not in franchise_identity_batch_script
    assert "Write-Host $env:DB_DSN" not in franchise_identity_batch_script
    assert "apps.api.app.tools.run_rag_index" in rag_index_unix_script
    assert "ALLOW_RAG_INDEX_APPLY=1" in rag_index_unix_script
    assert "DB_DSN and AZURE_OPENAI_KEY values are never printed by this script." in rag_index_unix_script
    assert "secret show" not in rag_index_unix_script
    assert "echo \"$DB_DSN\"" not in rag_index_unix_script
    assert "echo \"$AZURE_OPENAI_KEY\"" not in rag_index_unix_script
    assert "apps.api.app.tools.enrich_place_ai_columns" in place_ai_enrichment_script
    assert "ALLOW_AI_PLACE_ENRICHMENT_APPLY=1" in place_ai_enrichment_script
    assert "AZURE_OPENAI_KEY and DB_DSN values are never printed by this script." in place_ai_enrichment_script
    assert "secret show" not in place_ai_enrichment_script
    assert "Write-Host $env:DB_DSN" not in place_ai_enrichment_script
    assert "Write-Host $env:AZURE_OPENAI_KEY" not in place_ai_enrichment_script
    assert "apps.api.app.tools.enrich_place_local_columns" in place_local_enrichment_script
    assert "ALLOW_LOCAL_PLACE_ENRICHMENT_APPLY=1" in place_local_enrichment_script
    assert "DB_DSN value is never printed by this script." in place_local_enrichment_script
    assert "secret show" not in place_local_enrichment_script
    assert "Write-Host $env:DB_DSN" not in place_local_enrichment_script
    assert "apps.api.app.tools.plan_docent_qa" in docent_qa_script
    assert "DB_DSN value is never printed by this script." in docent_qa_script
    assert "secret show" not in docent_qa_script
    assert "Write-Host $env:DB_DSN" not in docent_qa_script
    assert "apps.api.app.tools.run_tour_api_ingest" in tour_api_ingest_script
    assert "ALLOW_TOUR_API_INGEST_APPLY=1" in tour_api_ingest_script
    assert "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script." in tour_api_ingest_script
    assert "secret show" not in tour_api_ingest_script
    assert "Write-Host $env:DB_DSN" not in tour_api_ingest_script
    assert "Write-Host $env:PUBLIC_DATA_SERVICE_KEY" not in tour_api_ingest_script
    assert "apps.api.app.tools.run_culture_info_ingest" in culture_info_ingest_script
    assert "ALLOW_CULTURE_INFO_INGEST_APPLY=1" in culture_info_ingest_script
    assert "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script." in culture_info_ingest_script
    assert "secret show" not in culture_info_ingest_script
    assert "Write-Host $env:DB_DSN" not in culture_info_ingest_script
    assert "Write-Host $env:PUBLIC_DATA_SERVICE_KEY" not in culture_info_ingest_script
    assert "apps.api.app.tools.run_kopis_ingest" in kopis_ingest_script
    assert "ALLOW_KOPIS_INGEST_APPLY=1" in kopis_ingest_script
    assert "KOPIS_API_KEY and DB_DSN values are never printed by this script." in kopis_ingest_script
    assert "secret show" not in kopis_ingest_script
    assert "Write-Host $env:DB_DSN" not in kopis_ingest_script
    assert "Write-Host $env:KOPIS_API_KEY" not in kopis_ingest_script
    assert "apps.api.app.tools.run_weather_observation_refresh" in weather_refresh_script
    assert "ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1" in weather_refresh_script
    assert "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script." in weather_refresh_script
    assert "secret show" not in weather_refresh_script
    assert "Write-Host $env:DB_DSN" not in weather_refresh_script
    assert "Write-Host $env:PUBLIC_DATA_SERVICE_KEY" not in weather_refresh_script
    assert "apps.api.app.tools.run_review_mention_ingest" in review_mention_ingest_script
    assert "ALLOW_REVIEW_MENTION_INGEST_APPLY=1" in review_mention_ingest_script
    assert "DB_DSN, NAVER_CLIENT_ID, and NAVER_CLIENT_SECRET values are never printed by this script." in review_mention_ingest_script
    assert "secret show" not in review_mention_ingest_script
    assert "Write-Host $env:DB_DSN" not in review_mention_ingest_script
    assert "Write-Host $env:NAVER_CLIENT_ID" not in review_mention_ingest_script
    assert "Write-Host $env:NAVER_CLIENT_SECRET" not in review_mention_ingest_script
    assert "apps.api.app.tools.run_review_attribute_batch" in review_attribute_batch_script
    assert "ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1" in review_attribute_batch_script
    assert "DB_DSN value is never printed by this script." in review_attribute_batch_script
    assert "secret show" not in review_attribute_batch_script
    assert "Write-Host $env:DB_DSN" not in review_attribute_batch_script
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
    assert "KEY_VAULT_URL\", \"\"" in flutter_web_smoke_script
    assert "DB_DSN\", \"\"" in flutter_web_smoke_script
    assert "LALA_ENABLE_LIVE_AI\", \"false\"" in flutter_web_smoke_script
    assert "LALA_ENABLE_LIVE_SPEECH\", \"false\"" in flutter_web_smoke_script
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
        "plan_docent_qa.sh",
        "plan_place_ai_enrichment.sh",
        "plan_place_local_enrichment.sh",
        "plan_rag_index.sh",
        "plan_place_score_batch.sh",
        "plan_franchise_identity_batch.sh",
        "plan_card_spending_file_ingest.sh",
        "plan_culture_info_ingest.sh",
        "plan_kopis_ingest.sh",
        "plan_weather_observation_refresh.sh",
        "plan_review_mention_ingest.sh",
        "plan_review_attribute_batch.sh",
        "plan_tour_api_ingest.sh",
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
    assert '${!name+x}' in scripts["_common.sh"]
    assert '"$vault_name" == *onmu*' in scripts["_common.sh"]
    assert "Unsupported Key Vault URL for LALA-next" in scripts["_common.sh"]
    assert "Worker smoke uses dry-run only" in scripts["smoke_workers.sh"]
    assert "--dry-run" in scripts["smoke_workers.sh"]
    assert "preflight" in scripts["smoke_workers.sh"]
    assert "Live Azure checks are intentionally excluded" in scripts["verify_repo.sh"]
    assert "check_flutter_client_contract" in scripts["verify_repo.sh"]
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
    assert "run_franchise_identity_batch" in scripts["plan_franchise_identity_batch.sh"]
    assert "plan_franchise_identity_batch.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY=1" in scripts["plan_franchise_identity_batch.sh"]
    assert "--confirm APPLY_FRANCHISE_IDENTITY_BATCH" in scripts["plan_franchise_identity_batch.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["plan_franchise_identity_batch.sh"]
    assert "run_franchise_reference_ingest" in scripts["plan_franchise_reference_ingest.sh"]
    assert "plan_franchise_reference_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_FRANCHISE_REFERENCE_INGEST_APPLY=1" in scripts["plan_franchise_reference_ingest.sh"]
    assert "--confirm APPLY_FRANCHISE_REFERENCE_INGEST" in scripts["plan_franchise_reference_ingest.sh"]
    assert (
        "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script."
        in scripts["plan_franchise_reference_ingest.sh"]
    )
    assert "run_rag_index" in scripts["plan_rag_index.sh"]
    assert "plan_rag_index.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_RAG_INDEX_APPLY=1" in scripts["plan_rag_index.sh"]
    assert "--confirm APPLY_RAG_INDEX" in scripts["plan_rag_index.sh"]
    assert "DB_DSN and AZURE_OPENAI_KEY values are never printed by this script." in scripts["plan_rag_index.sh"]
    assert "plan_docent_qa" in scripts["plan_docent_qa.sh"]
    assert "plan_docent_qa.sh" in scripts["verify_repo.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["plan_docent_qa.sh"]
    assert "enrich_place_ai_columns" in scripts["plan_place_ai_enrichment.sh"]
    assert "plan_place_ai_enrichment.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_AI_PLACE_ENRICHMENT_APPLY=1" in scripts["plan_place_ai_enrichment.sh"]
    assert "--confirm APPLY_AI_PLACE_ENRICHMENT" in scripts["plan_place_ai_enrichment.sh"]
    assert "AZURE_OPENAI_KEY and DB_DSN values are never printed by this script." in scripts["plan_place_ai_enrichment.sh"]
    assert "enrich_place_local_columns" in scripts["plan_place_local_enrichment.sh"]
    assert "plan_place_local_enrichment.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_LOCAL_PLACE_ENRICHMENT_APPLY=1" in scripts["plan_place_local_enrichment.sh"]
    assert "--confirm APPLY_LOCAL_PLACE_ENRICHMENT" in scripts["plan_place_local_enrichment.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["plan_place_local_enrichment.sh"]
    assert "export_public_mvp_snapshot" in scripts["export_public_mvp_snapshot.sh"]
    assert "export_public_mvp_snapshot.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE=1" in scripts["export_public_mvp_snapshot.sh"]
    assert "--confirm WRITE_PUBLIC_MVP_SNAPSHOT" in scripts["export_public_mvp_snapshot.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["export_public_mvp_snapshot.sh"]
    assert "run_tour_api_ingest" in scripts["plan_tour_api_ingest.sh"]
    assert "plan_tour_api_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_TOUR_API_INGEST_APPLY=1" in scripts["plan_tour_api_ingest.sh"]
    assert "--confirm APPLY_TOUR_API_INGEST" in scripts["plan_tour_api_ingest.sh"]
    assert "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script." in scripts["plan_tour_api_ingest.sh"]
    assert "run_culture_info_ingest" in scripts["plan_culture_info_ingest.sh"]
    assert "plan_culture_info_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_CULTURE_INFO_INGEST_APPLY=1" in scripts["plan_culture_info_ingest.sh"]
    assert "--confirm APPLY_CULTURE_INFO_INGEST" in scripts["plan_culture_info_ingest.sh"]
    assert "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script." in scripts["plan_culture_info_ingest.sh"]
    assert "run_kopis_ingest" in scripts["plan_kopis_ingest.sh"]
    assert "plan_kopis_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_KOPIS_INGEST_APPLY=1" in scripts["plan_kopis_ingest.sh"]
    assert "--confirm APPLY_KOPIS_INGEST" in scripts["plan_kopis_ingest.sh"]
    assert "KOPIS_API_KEY and DB_DSN values are never printed by this script." in scripts["plan_kopis_ingest.sh"]
    assert "run_weather_observation_refresh" in scripts["plan_weather_observation_refresh.sh"]
    assert "plan_weather_observation_refresh.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1" in scripts["plan_weather_observation_refresh.sh"]
    assert "--confirm APPLY_WEATHER_OBSERVATION_REFRESH" in scripts["plan_weather_observation_refresh.sh"]
    assert "PUBLIC_DATA_SERVICE_KEY and DB_DSN values are never printed by this script." in scripts["plan_weather_observation_refresh.sh"]
    assert "run_review_mention_ingest" in scripts["plan_review_mention_ingest.sh"]
    assert "plan_review_mention_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_REVIEW_MENTION_INGEST_APPLY=1" in scripts["plan_review_mention_ingest.sh"]
    assert "--confirm APPLY_REVIEW_MENTION_INGEST" in scripts["plan_review_mention_ingest.sh"]
    assert "DB_DSN, NAVER_CLIENT_ID, and NAVER_CLIENT_SECRET values are never printed by this script." in scripts["plan_review_mention_ingest.sh"]
    assert "run_review_attribute_batch" in scripts["plan_review_attribute_batch.sh"]
    assert "plan_review_attribute_batch.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1" in scripts["plan_review_attribute_batch.sh"]
    assert "--confirm APPLY_REVIEW_ATTRIBUTE_BATCH" in scripts["plan_review_attribute_batch.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["plan_review_attribute_batch.sh"]
    assert "run_card_spending_file_ingest" in scripts["plan_card_spending_file_ingest.sh"]
    assert "plan_card_spending_file_ingest.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1" in scripts["plan_card_spending_file_ingest.sh"]
    assert "--confirm APPLY_CARD_SPENDING_FILE_INGEST" in scripts["plan_card_spending_file_ingest.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["plan_card_spending_file_ingest.sh"]
    assert "--check-compat" in scripts["export_openapi.sh"]
    assert "plan_dev_reset" in scripts["plan_dev_reset.sh"]
    assert "plan_dev_reset.sh" in scripts["verify_repo.sh"]
    assert "ALLOW_DEV_RESET_APPLY=1" in scripts["plan_dev_reset.sh"]
    assert "--confirm APPLY_DEV_RESET_SQL" in scripts["plan_dev_reset.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["plan_dev_reset.sh"]
    assert "secret list" in scripts["verify_db_resources.sh"]
    assert "secret show" not in scripts["verify_db_resources.sh"]
    assert "db-dsn" in scripts["verify_db_resources.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["verify_db_schema.sh"]
    assert "DB_DSN value is never printed by this script." in scripts["apply_canonical_sql.sh"]
    assert "--confirm APPLY_CANONICAL_SQL" in scripts["apply_canonical_sql.sh"]
    assert "compose.local.yml" in scripts["bootstrap_local_mvp_db.sh"]
    assert "LALA_POSTGRES_PASSWORD is required" in scripts["bootstrap_local_mvp_db.sh"]
    assert "DB_DSN and LALA_POSTGRES_PASSWORD values are never printed by this script." in scripts["bootstrap_local_mvp_db.sh"]
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
    assert "Runs a bounded deploy or wider live API matrix without printing client tokens" in scripts["smoke_api_matrix.sh"]
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
