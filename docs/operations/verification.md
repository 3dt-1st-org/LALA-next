# Verification

This repository keeps Wave 1 verification lightweight and repeatable. The checks
are intentionally local-first so controller, implementation, and verification
sessions can run the same commands without requiring live Azure or database
dependencies.

## Local Verification

From macOS/Linux:

```bash
scripts/unix/verify_repo.sh
```

The script runs `uv sync --extra dev` by default, then uses the Python
interpreter in the uv-managed `.venv`. Use `--python <path-to-python>` only when
you need to override that interpreter.

If uv dependencies are already synced and you only want to rerun checks:

```bash
scripts/unix/verify_repo.sh --skip-install
```

For a Mac handoff report that combines branch state, latest GitHub Actions run,
local verification, Azure resource verification, and DB rollout readiness:

```bash
scripts/unix/handoff_report.sh
```

Use `--skip-tests` or `--skip-azure` for a fast read-only status pass when the
full check was already run in the same session.
When `local-artifacts/openapi/lala-next-openapi.json` is present, the report also
checks OpenAPI compatibility against that USB handoff snapshot. Pass
`--openapi-baseline <path>` to compare against a different Flutter handoff
snapshot.

From `C:\Users\EL035\dataschool\LALA-next` on Windows:

```powershell
.\scripts\windows\verify_repo.ps1
```

The script runs `uv sync --extra dev` by default, then uses
`.venv\Scripts\python.exe`. Use `-Python <path-to-python.exe>` only when you
need to override that interpreter.

If dependencies are already installed:

```powershell
.\scripts\windows\verify_repo.ps1 -SkipInstall
```

## Local MVP DB Bootstrap

The local PostgreSQL container is defined in `compose.local.yml` and uses
PostGIS plus pgvector from `infra/local-postgres/Dockerfile`. Review the
bootstrap plan without starting Docker or touching a database:

```bash
scripts/unix/bootstrap_local_mvp_db.sh
```

Execution is explicit and localhost-only. Set `LALA_POSTGRES_PASSWORD` in the
process or `.env`; optional `LALA_POSTGRES_USER`, `LALA_POSTGRES_DB`, and
`LALA_POSTGRES_PORT` default to `lala`, `lala`, and `55432`.

```bash
scripts/unix/bootstrap_local_mvp_db.sh --start-compose
scripts/unix/bootstrap_local_mvp_db.sh --apply-canonical
scripts/unix/bootstrap_local_mvp_db.sh --apply-dev-reset
scripts/unix/bootstrap_local_mvp_db.sh --score-apply
scripts/unix/bootstrap_local_mvp_db.sh --snapshot-write
```

For a full local MVP data refresh:

```bash
scripts/unix/bootstrap_local_mvp_db.sh --all
```

The script builds a localhost `DB_DSN` inside the process, applies only existing
guarded wrappers, and never prints `DB_DSN` or `LALA_POSTGRES_PASSWORD`.

The script runs:

- FastAPI route tests.
- API-key and response-envelope contract tests.
- Request id, request duration, public metrics with readiness gauges, and
  secret-safe request logging tests, including optional JSONL access log output
  when `LALA_ACCESS_LOG_PATH` is configured.
- Canonical SQL plan/apply guard tests.
- Worker/batch dry-run contract tests and smoke.
- Non-mutating worker/batch live rollout gate plan generation.
- In-process OpenAPI export tests and local handoff export.
- Reference Flutter client contract check against the current OpenAPI route set.
- Optional Dart package format/analyze/test for the reference Flutter client
  when Dart is installed.
- Non-mutating DB rollout plan generation.
- Non-mutating observability alert/dashboard plan generation.
- Non-mutating OAuth/Entra identity rollout plan generation.
- Non-mutating TourAPI, KCISA culture-info, KOPIS, and card-spending ingestion plan generation.
- Non-mutating legacy Flask replacement/retirement plan generation.
- SQL and documentation secret-safety tests.
- PowerShell script parser checks.

## CI Verification

GitHub Actions runs the same test suite on every push to `main` and every pull
request. The Windows job verifies the shared-backend baseline:

- `uv sync --extra dev`
- `uv run pytest apps/api/tests`
- PowerShell parser checks for `scripts/windows/*.ps1`

The Ubuntu job verifies the Mac/Linux wrapper path:

- `uv sync --extra dev`
- `bash scripts/unix/verify_repo.sh --skip-install`

CI does not require live Key Vault, Azure OpenAI, Azure Speech, or PostgreSQL.
Those dependencies are represented as `configured`, `missing`, `degraded`, or
`skipped` in `/readyz` and are smoke-tested manually when credentials are
available.
`/readyz.data.mode` adds the operator-facing runtime summary:
`data=unavailable` when no DB or explicit snapshot fallback can serve read
data, `overall=db-backed` when the canonical DB probe is configured and no live
Azure dependency is in use, `overall=public-cache` when a limited offline
snapshot fallback is serving read-only data without a live DB,
`overall=live-azure` when opt-in AI or Speech live calls are configured, and
`overall=degraded` when a requested runtime dependency is unhealthy.

When `DB_DSN` is configured, `/readyz` connects to PostgreSQL and verifies the
canonical relations required by the API:

- `travel.public_places`
- `travel.place_events`
- `travel.weather_observations`
- `travel.docent_scripts`
- `analytics.place_score_snapshots`
- `rag.knowledge_chunks`

Without `DB_DSN`, DB readiness is `skipped`; DB-backed routes return empty or
`unavailable` contract-safe responses unless the limited static snapshot
fallback is explicitly enabled. If the connection works but those relations are
absent, DB readiness is `degraded` rather than `configured`. `/readyz` also
reports `postgis`: it is `configured` only when the PostGIS extension and the
`travel.idx_places_geog_expr` GiST expression index are present. The data mode is
`db-backed` only when both `db=configured` and `postgis=configured`, because
current-location recommendations rely on `ST_DWithin` and `ST_Distance` rather
than approximate client-side/mock distance sorting.
`/readyz` also verifies that the Wave 1 dry-run worker contract registry can be
loaded. This does not imply live Azure Functions/Event Hub freshness; live worker
mutation remains behind the worker rollout gate.

For an explicit read-only canonical schema check against the configured DB,
run:

```bash
scripts/unix/verify_db_schema.sh
```

```powershell
.\scripts\windows\verify_db_schema.ps1
```

The script reads `DB_DSN` from the process, `.env`, or the configured
LALA-next Key Vault. It checks required extensions, schemas, tables, and views
without applying migrations or printing the DSN. A missing `DB_DSN`, connection
failure, or missing canonical object returns a non-zero exit code so operators
can stop before handing the DB to Flutter/API smoke testers.
Use `-Json` when another tool needs machine-readable output; in that mode the
PowerShell wrapper suppresses human-readable preamble text.

## Deployed First-Open Regression Check

For the public contest path, a healthy `200` is not enough. Re-check the real
first-impression path on `https://lala-next.cloud/` and confirm the API no
longer shows a cold-start first-hit stall.

Recommended operator checks:

```bash
for i in 1 2 3; do
  curl -sS -o /dev/null -w "run$i %{http_code} %{time_total}s\n" \
    'https://api.lala-next.cloud/api/v1/places?lat=37.5665&lng=126.9780&radius_m=3000&category=all&include_scores=true'
done

scripts/unix/smoke_flutter_web.sh \
  --web-url 'https://lala-next.cloud/' \
  --require-browser \
  --fail-on-console-error
```

Treat a repeated first-hit multi-second spike plus a visibly stalled root page
as a production regression even when `/healthz` and `/readyz` are green.

To review the exact canonical SQL files before any DB rollout, run:

```bash
scripts/unix/apply_canonical_sql.sh
```

```powershell
.\scripts\windows\apply_canonical_sql.ps1
```

Default mode is dry-run plan only. It lists canonical files, statement counts,
and SHA-256 hashes without connecting to PostgreSQL. Applying the plan requires
all three explicit controls:

```bash
ALLOW_CANONICAL_SQL_APPLY=1 \
  scripts/unix/apply_canonical_sql.sh \
  --apply \
  --confirm APPLY_CANONICAL_SQL \
  --key-vault-url <KEY_VAULT_URL>
```

```powershell
$env:ALLOW_CANONICAL_SQL_APPLY = "1"
.\scripts\windows\apply_canonical_sql.ps1 `
  -Apply `
  -Confirm APPLY_CANONICAL_SQL `
  -KeyVaultUrl <KEY_VAULT_URL>
```

The apply path reads `DB_DSN` from the process, `.env`, or LALA-next Key Vault,
runs `sql/canonical/*.sql` in sorted order inside one transaction, and does not
print the DSN. Use it only for an approved dev/shared target after the plan has
been reviewed.

To verify worker and batch boundaries without external reads or writes, run:

```bash
scripts/unix/smoke_workers.sh
```

```powershell
.\scripts\windows\smoke_workers.ps1
```

This command lists worker contracts and dry-runs each job. It is safe without
`DB_DSN`, Key Vault access, Event Hub access, or live Azure Functions. It also
runs the read-only worker live preflight and expects it to remain blocked in
Wave 1.

To review worker/batch live rollout gates without creating resources, binding
queues, enabling mutation, or writing to the database:

```bash
scripts/unix/plan_worker_rollout.sh
```

```powershell
.\scripts\windows\plan_worker_rollout.ps1
```

The plan keeps all commands pointed at the LALA-next Key Vault, rejects ONMU
vault targets, and treats Azure Functions, Event Hub, idempotency, poison
handling, alerts, and rollback ownership as approval gates.

To review the local-value recommendation score batch without connecting to a
database:

```bash
scripts/unix/plan_place_score_batch.sh
```

```powershell
.\scripts\windows\plan_place_score_batch.ps1
```

Default mode is plan-only. It reports the `local-value-v2` formula, input
relations, and target table without printing `DB_DSN`. When a canonical DB has
`travel`, `economy`, `culture`, and `analytics` relations loaded, preview the
rows that would be written:

```bash
scripts/unix/plan_place_score_batch.sh --preview --limit 20
```

```powershell
.\scripts\windows\plan_place_score_batch.ps1 -Preview -Limit 20
```

Apply inserts new rows into `analytics.place_score_snapshots`, records the
`place-score-batch` run in `ops.job_runs`, and requires the exact confirm string
plus a process-local allow flag:

```bash
ALLOW_PLACE_SCORE_BATCH_APPLY=1 \
  scripts/unix/plan_place_score_batch.sh \
  --apply \
  --confirm APPLY_PLACE_SCORE_BATCH
```

```powershell
$env:ALLOW_PLACE_SCORE_BATCH_APPLY = "1"
.\scripts\windows\plan_place_score_batch.ps1 `
  -Apply `
  -Confirm APPLY_PLACE_SCORE_BATCH
```

To review approved review/mention preprocessing without connecting to a
database:

```bash
scripts/unix/plan_review_mention_ingest.sh
```

```powershell
.\scripts\windows\plan_review_mention_ingest.ps1
```

Default mode is plan-only. It reports the
`community.place_mentions_weekly` target, the `community.posts` and
`travel.places` inputs, and the `review-mention-preprocess-v1` prompt/schema
version without printing `DB_DSN`. When approved community/search/export rows
are loaded, preview the deterministic cleanup, ad filtering, category policy,
place matching, and aggregate rows:

```bash
scripts/unix/plan_review_mention_ingest.sh --preview --limit 50
```

```powershell
.\scripts\windows\plan_review_mention_ingest.ps1 -Preview -Limit 50
```

Apply upserts rows into `community.place_mentions_weekly`, records an
`ops.job_runs` row, and requires the exact confirm string plus a process-local
allow flag:

```bash
ALLOW_REVIEW_MENTION_INGEST_APPLY=1 \
  scripts/unix/plan_review_mention_ingest.sh \
  --apply \
  --confirm APPLY_REVIEW_MENTION_INGEST
```

```powershell
$env:ALLOW_REVIEW_MENTION_INGEST_APPLY = "1"
.\scripts\windows\plan_review_mention_ingest.ps1 `
  -Apply `
  -Confirm APPLY_REVIEW_MENTION_INGEST
Remove-Item Env:\ALLOW_REVIEW_MENTION_INGEST_APPLY
```

To review category-aware review attribute scoring without connecting to a
database:

```bash
scripts/unix/plan_review_attribute_batch.sh
```

```powershell
.\scripts\windows\plan_review_attribute_batch.ps1
```

Default mode is plan-only. It reports the
`community.place_mentions_weekly` target, the `community.posts` input, and the
`review-attributes-v1` schema without printing `DB_DSN` or
`AZURE_OPENAI_KEY`. The bulk review lane should prefer
`AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` (`gpt-5.4-nano` recommended) before the
generic deployment. Preview reads already-preprocessed organic mention rows and
computes deterministic attributes without mutation:

```bash
scripts/unix/plan_review_attribute_batch.sh --preview --limit 50
```

```powershell
.\scripts\windows\plan_review_attribute_batch.ps1 -Preview -Limit 50
```

Dry-run AI calls Azure OpenAI for JSON attribute extraction but does not write
rows:

```bash
scripts/unix/plan_review_attribute_batch.sh --dry-run-ai --limit 20
```

```powershell
.\scripts\windows\plan_review_attribute_batch.ps1 -DryRunAi -Limit 20
```

Apply writes `attributes.review_attributes`, `attributes.review_quality`, and
`sentiment_score`, records an `ops.job_runs` row, and requires the exact confirm
string plus a process-local allow flag:

```bash
ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY=1 \
  scripts/unix/plan_review_attribute_batch.sh \
  --apply \
  --confirm APPLY_REVIEW_ATTRIBUTE_BATCH
```

```powershell
$env:ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY = "1"
.\scripts\windows\plan_review_attribute_batch.ps1 `
  -Apply `
  -Confirm APPLY_REVIEW_ATTRIBUTE_BATCH
Remove-Item Env:\ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY
```

To review the franchise/small-merchant identity batch without connecting to a
database:

```bash
scripts/unix/plan_franchise_identity_batch.sh
```

```powershell
.\scripts\windows\plan_franchise_identity_batch.ps1
```

Default mode is plan-only. It reports the `analytics.place_business_identity`
target table, the `travel.places` and `economy.franchise_*` inputs, and the
matching rules without printing `DB_DSN`. When canonical places and Fair Trade
Commission franchise references are loaded, preview the rows that would be
upserted:

```bash
scripts/unix/plan_franchise_identity_batch.sh --preview --limit 20
```

```powershell
.\scripts\windows\plan_franchise_identity_batch.ps1 -Preview -Limit 20
```

Apply upserts rows into `analytics.place_business_identity` and requires the
exact confirm string plus a process-local allow flag:

```bash
ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY=1 \
  scripts/unix/plan_franchise_identity_batch.sh \
  --apply \
  --confirm APPLY_FRANCHISE_IDENTITY_BATCH
```

```powershell
$env:ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY = "1"
.\scripts\windows\plan_franchise_identity_batch.ps1 `
  -Apply `
  -Confirm APPLY_FRANCHISE_IDENTITY_BATCH
Remove-Item Env:\ALLOW_FRANCHISE_IDENTITY_BATCH_APPLY
```

To review the weather observation refresh without mutating the database:

```bash
scripts/unix/plan_weather_observation_refresh.sh
```

Default mode is plan-only. Preview reads canonical place regions from
PostgreSQL, calls the official KMA ultra-short nowcast and AirKorea realtime
air-quality APIs through the public-data service key, and shows the rows that
would feed `travel.weather_observations`:

```bash
scripts/unix/plan_weather_observation_refresh.sh \
  --preview \
  --limit 20 \
  --python .venv/bin/python
```

Apply inserts new observations into `travel.weather_observations`, records the
`weather-refresh` run in `ops.job_runs`, and requires the exact confirm string
plus a process-local allow flag:

```bash
ALLOW_WEATHER_OBSERVATION_REFRESH_APPLY=1 \
  scripts/unix/plan_weather_observation_refresh.sh \
  --apply \
  --confirm APPLY_WEATHER_OBSERVATION_REFRESH \
  --limit 20 \
  --python .venv/bin/python
```

After a successful weather refresh, regenerate local-value score snapshots and
dynamic RAG chunks so `weather_fit_score` and `weather_context` reflect the
latest official observations.

To review Fair Trade Commission franchise brand reference ingestion without
calling the public-data API or mutating the DB:

```bash
scripts/unix/plan_franchise_reference_ingest.sh
```

Default mode is plan-only. Preview calls the public-data API
`공정거래위원회_가맹정보_브랜드별 가맹점 현황 제공 서비스` and maps brand statistics
into `economy.franchise_brands`, but does not write to PostgreSQL:

```bash
scripts/unix/plan_franchise_reference_ingest.sh \
  --preview \
  --year 2025 \
  --rows 20
```

Apply upserts brand reference rows and requires the exact confirm string plus a
process-local allow flag:

```bash
ALLOW_FRANCHISE_REFERENCE_INGEST_APPLY=1 \
  scripts/unix/plan_franchise_reference_ingest.sh \
  --apply \
  --confirm APPLY_FRANCHISE_REFERENCE_INGEST \
  --year 2025 \
  --rows 0
```

The wrapper never prints `PUBLIC_DATA_SERVICE_KEY` or `DB_DSN`. After this
reference ingest succeeds, run the franchise identity batch, then regenerate
`local-value-v2` score snapshots and RAG chunks so the public API reflects the
new small-merchant signal.

To review Azure OpenAI place enrichment without connecting to a database or
calling AI:

```bash
scripts/unix/plan_place_ai_enrichment.sh
```

```powershell
.\scripts\windows\plan_place_ai_enrichment.ps1
```

Default mode is plan-only. It reports the `place-ai-enrichment-v1` prompt
contract, enriched columns, and target tables without printing `DB_DSN` or
`AZURE_OPENAI_KEY`. When canonical places are loaded and Azure OpenAI settings
are configured, dry-run AI previews generated values without updating rows:

```bash
scripts/unix/plan_place_ai_enrichment.sh --dry-run-ai --limit 20
```

```powershell
.\scripts\windows\plan_place_ai_enrichment.ps1 -DryRunAi -Limit 20
```

Apply updates missing `name_en`, `address_en`, `region_name_en`, and
`is_indoor` values in `travel.places`, records provenance in
`travel.place_enrichments`, and requires the exact confirm string plus a
process-local allow flag:

```bash
ALLOW_AI_PLACE_ENRICHMENT_APPLY=1 \
  scripts/unix/plan_place_ai_enrichment.sh \
  --apply \
  --confirm APPLY_AI_PLACE_ENRICHMENT
```

```powershell
$env:ALLOW_AI_PLACE_ENRICHMENT_APPLY = "1"
.\scripts\windows\plan_place_ai_enrichment.ps1 `
  -Apply `
  -Confirm APPLY_AI_PLACE_ENRICHMENT
```

To review the read-only snapshot fallback export without connecting to a database:

```bash
scripts/unix/export_public_mvp_snapshot.sh
```

Default mode is plan-only. It reports the output file and DB input relations
without printing `DB_DSN`. When `travel.public_places` and
`analytics.place_score_snapshots` are populated, preview the Vercel fallback
payload that would be bundled into the API package:

```bash
scripts/unix/export_public_mvp_snapshot.sh --preview --limit 20
```

Writing `apps/api/app/data/public_mvp_places.json` is a local file update, not a
DB mutation, and requires the exact confirm string plus a process-local allow
flag:

```bash
ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE=1 \
  scripts/unix/export_public_mvp_snapshot.sh \
  --write \
  --confirm WRITE_PUBLIC_MVP_SNAPSHOT
```

To review TourAPI place ingestion without calling the external API or writing to
the database:

```bash
scripts/unix/plan_tour_api_ingest.sh
```

```powershell
.\scripts\windows\plan_tour_api_ingest.ps1
```

Default mode is plan-only. The source is the public-data `한국관광공사_국문
관광정보 서비스_GW` service and the default target is `travel.places`.
Preview calls TourAPI with `PUBLIC_DATA_SERVICE_KEY` but does not mutate the DB.
When a place has no `firstimage`, the preview/apply path also checks the official
`detailImage2` image endpoint for that `contentId`; detail-image failures are
counted as `image_error_count` and do not drop the place:

```bash
scripts/unix/plan_tour_api_ingest.sh --preview --rows 20
```

```powershell
.\scripts\windows\plan_tour_api_ingest.ps1 -Preview -Rows 20
```

Apply upserts TourAPI rows into `travel.places` and records an ingest hash in
`ingest.source_files`. It requires the exact confirm string plus a process-local
allow flag:

```bash
ALLOW_TOUR_API_INGEST_APPLY=1 \
  scripts/unix/plan_tour_api_ingest.sh \
  --apply \
  --confirm APPLY_TOUR_API_INGEST \
  --rows 40
```

```powershell
$env:ALLOW_TOUR_API_INGEST_APPLY = "1"
.\scripts\windows\plan_tour_api_ingest.ps1 `
  -Apply `
  -Confirm APPLY_TOUR_API_INGEST `
  -Rows 40
```

The wrapper never prints `PUBLIC_DATA_SERVICE_KEY` or `DB_DSN`.

To review KCISA culture information ingestion without calling the external API
or writing to the database:

```bash
scripts/unix/plan_culture_info_ingest.sh
```

```powershell
.\scripts\windows\plan_culture_info_ingest.ps1
```

Default mode is plan-only. The source is the public-data
`한국문화정보원_한눈에보는문화정보조회서비스` service and the default target is
`culture.events`. Preview calls KCISA with `PUBLIC_DATA_SERVICE_KEY` but does not
mutate the DB:

```bash
scripts/unix/plan_culture_info_ingest.sh --preview --sido 경기 --sigungu 수원시 --rows 20
```

```powershell
.\scripts\windows\plan_culture_info_ingest.ps1 -Preview -Sido 경기 -Sigungu 수원시 -Rows 20
```

Apply upserts KCISA rows into `culture.events`, records an ingest hash in
`ingest.source_files`, records a `kcisa-culture-info-ingest` run in
`ops.job_runs`, and requires the exact confirm string plus a process-local
allow flag:

```bash
ALLOW_CULTURE_INFO_INGEST_APPLY=1 \
  scripts/unix/plan_culture_info_ingest.sh \
  --apply \
  --confirm APPLY_CULTURE_INFO_INGEST \
  --sido 경기 \
  --sigungu 수원시 \
  --rows 20
```

```powershell
$env:ALLOW_CULTURE_INFO_INGEST_APPLY = "1"
.\scripts\windows\plan_culture_info_ingest.ps1 `
  -Apply `
  -Confirm APPLY_CULTURE_INFO_INGEST `
  -Sido 경기 `
  -Sigungu 수원시 `
  -Rows 20
```

The wrapper never prints `PUBLIC_DATA_SERVICE_KEY` or `DB_DSN`.

To review KOPIS performance ingestion without calling the external API or
writing to the database:

```bash
scripts/unix/plan_kopis_ingest.sh
```

```powershell
.\scripts\windows\plan_kopis_ingest.ps1
```

Default mode is plan-only. The source is the KOPIS
`공연예술통합전산망 OPEN API 공연목록 조회 서비스` and the default target is
`culture.events`. The default region is `signgucode=41` for Gyeonggi-do, and
the default date window stays within the KOPIS 31-day list-query limit. Preview
calls KOPIS with `KOPIS_API_KEY` but does not mutate the DB:

```bash
scripts/unix/plan_kopis_ingest.sh --preview --rows 20
```

```powershell
.\scripts\windows\plan_kopis_ingest.ps1 -Preview -Rows 20
```

Apply upserts KOPIS rows into `culture.events`, records an ingest hash in
`ingest.source_files`, records a `kopis-ingest` run in `ops.job_runs`, and
requires the exact confirm string plus a process-local allow flag:

```bash
ALLOW_KOPIS_INGEST_APPLY=1 \
  scripts/unix/plan_kopis_ingest.sh \
  --apply \
  --confirm APPLY_KOPIS_INGEST \
  --rows 40
```

```powershell
$env:ALLOW_KOPIS_INGEST_APPLY = "1"
.\scripts\windows\plan_kopis_ingest.ps1 `
  -Apply `
  -Confirm APPLY_KOPIS_INGEST `
  -Rows 40
```

The wrapper never prints `KOPIS_API_KEY` or `DB_DSN`.

To review public card spending file ingestion without reading a source file or
writing to the database:

```bash
scripts/unix/plan_card_spending_file_ingest.sh
```

```powershell
.\scripts\windows\plan_card_spending_file_ingest.ps1
```

Default mode is plan-only. The supported sources are the public-data file
datasets `경기도_카드 소비 데이터` and `경기도_데이터분석 카드매출 시군구 성연령별 집계`.
Preview parses a downloaded CSV/XLSX file into the standard economy tables but
does not mutate the DB:

```bash
scripts/unix/plan_card_spending_file_ingest.sh \
  --preview \
  --file-path local-artifacts/source-data/card-spending.csv
```

```powershell
.\scripts\windows\plan_card_spending_file_ingest.ps1 `
  -Preview `
  -FilePath local-artifacts\source-data\card-spending.csv
```

Apply inserts rows into `economy.card_spending_area_monthly` and
`economy.card_spending_demographics`, records the source file in
`ingest.source_files`, records a `card-spending-file-ingest` run in
`ops.job_runs`, and requires the exact confirm string plus a process-local
allow flag:

```bash
ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1 \
  scripts/unix/plan_card_spending_file_ingest.sh \
  --apply \
  --confirm APPLY_CARD_SPENDING_FILE_INGEST \
  --file-path local-artifacts/source-data/card-spending.csv
```

```powershell
$env:ALLOW_CARD_SPENDING_FILE_INGEST_APPLY = "1"
.\scripts\windows\plan_card_spending_file_ingest.ps1 `
  -Apply `
  -Confirm APPLY_CARD_SPENDING_FILE_INGEST `
  -FilePath local-artifacts\source-data\card-spending.csv
```

The wrapper never prints `DB_DSN`. If the source file only has unmapped region
codes, pass `--region-map <path>` or `-RegionMap <path>` with a CSV/XLSX mapping
that contains code/name columns.

The parser also accepts ZIP archives that contain CSV/XLSX files. For the
Gyeonggi aggregate file `경기도_데이터분석 카드매출 시군구 성연령별 집계`, use
`--dataset-name "경기도_데이터분석 카드매출 시군구 성연령별 집계"`. When the first
rollout only needs the local-value score input, pass `--skip-demographics` to
load `economy.card_spending_area_monthly` without the much larger
`economy.card_spending_demographics` table:

```bash
ALLOW_CARD_SPENDING_FILE_INGEST_APPLY=1 \
  scripts/unix/plan_card_spending_file_ingest.sh \
  --apply \
  --confirm APPLY_CARD_SPENDING_FILE_INGEST \
  --skip-demographics \
  --dataset-name "경기도_데이터분석 카드매출 시군구 성연령별 집계" \
  --file-path artifacts/tmp/raw/gyeonggi-card/카드매출_시군구_성연령별_집계.zip
```

As of 2026-06-23 UTC, the shared dev database has both approved Gyeonggi card
sources applied. The aggregate source remains the 31-region baseline through
2025-01. The detailed `카드소비 데이터_202601-202603.zip` source then parsed
47,002,332 of 51,328,357 raw rows and inserted 3,650
`economy.card_spending_area_monthly` rows plus 57,832
`economy.card_spending_demographics` rows. Card area coverage is now 152,991
rows across 31 regions with a max month of 2026-03, and demographic coverage is
57,832 rows across 15 regions. The subsequent place-score batch inserted 2,636
`analytics.place_score_snapshots` and recorded a batch run in `ops.job_runs`;
1,294 latest scores have
`local_spending_score` sourced from actual card sales rows. Dynamic RAG then
upserted 821 chunks into `rag.knowledge_chunks` with the same guarded apply
contract. Regions without an approved
card-spending source, such as current Seoul coverage, must keep
`local_spending_score` null rather than infer or mock the signal.

To export the Flutter handoff schema without running a server, run:

```bash
scripts/unix/export_openapi.sh --in-process
```

```powershell
.\scripts\windows\export_openapi.ps1 -InProcess
```

The schema is written under `artifacts/openapi/`, which is a local handoff
artifact path and is ignored by git. Omit `-Python` locally unless you need to
override the interpreter; the wrapper prefers `.venv\Scripts\python.exe` when it
exists.

To compare the current schema against a previous Flutter handoff snapshot:

```bash
scripts/unix/export_openapi.sh --check-compat artifacts/openapi/lala-next-openapi.json
```

The check is non-destructive and treats additive metadata, such as new OpenAPI
security schemes, as compatible.

To verify the reference Flutter client with Dart SDK tooling:

```bash
scripts/unix/verify_flutter_client.sh --require-dart
```

```powershell
.\scripts\windows\verify_flutter_client.ps1 -RequireDart
```

Without the required flag, these wrappers skip cleanly when Dart is not
installed. `verify_repo` still runs the Python OpenAPI/client contract check in
all environments.

To verify the Flutter app in a real browser on macOS/Linux:

```bash
scripts/unix/smoke_flutter_web.sh --require-flutter --require-browser --port 8099
```

To include a temporary local API and authenticated route checks:

```bash
scripts/unix/smoke_flutter_web.sh \
  --require-flutter \
  --require-browser \
  --start-api \
  --fail-on-console-error \
  --port 8099 \
  --api-port 18080
```

```powershell
.\scripts\windows\smoke_flutter_web.ps1 `
  -RequireFlutter `
  -RequireBrowser `
  -StartApi `
  -FailOnConsoleError `
  -Port 8099 `
  -ApiPort 18080
```

This smoke requires `npx` plus either the local Codex Playwright CLI wrapper or
the script's npx-backed Playwright CLI fallback. Local bundle verification also
requires Flutter. The local mode builds the web bundle with `--no-wasm-dry-run`,
serves it on the selected loopback port, opens it in a named Playwright
session, validates the Flutter runtime entrypoint, and writes snapshot,
screenshot, console, and runtime-state artifacts under `output/playwright/`.
When no API is running, a refused `/healthz` console entry is expected and the
smoke still passes because it is a render check. Pass
`--api-base-url <url>` for a separately running backend, and add
`--fail-on-console-error` when the backend is expected to satisfy all public
browser requests. With `--api-base-url` or `--start-api`, the smoke grants a
fixed test browser geolocation, reloads into the first-run location request
flow, captures `flutter-web-requests.txt`, and verifies places, weather,
intervention, and daily plan requests with the granted latitude and longitude.
During browser investigation, the live Flutter bundle now also exposes
`window.__lalaAppState` fields such as `usingBundledStartupPlaces`,
`recommendationRecoveryPending`, and `recommendationRecoveryAttempt`, plus the
latest frontend recovery event under `window.__lalaAppEvent`.
When the smoke targets `--api-base-url` or the deployed `--web-url`, it also
verifies a live-context docent script from the same place/weather data. On
macOS/Linux, the same smoke captures or refetches API JSON responses in
`flutter-web-api-responses.json` and fails if the browser received non-DB
places, a non-PostGIS location engine, weather without AirKorea PM10/PM2.5
values, or a docent script that omits the live place name, grounding labels,
official-source wording, local-spending context, small-merchant route context,
route action context, or the captured PM10/PM2.5 context. It also rejects raw
score values and internal source labels in the user-facing docent copy. The
smoke records `flutter-web-marker-state.json` and fails when the map renders no
real place pins or only clusters without pins. Add
`--check-location-denial-fallback` to simulate a browser geolocation denial; the
smoke then fails unless the app exposes the location fallback notice, keeps
public map data loading from the default public-data coordinates, and exposes a
nationwide manual location selector with at least 200 choices. The
`--api-base-url` backend must allow the selected local web origin. Use
`--web-url https://lala-next.cloud/?qa=<label>` when verifying the deployed
contest site so Kakao Maps and API CORS run from the registered production
origin. Add `--expect-build-sha <sha> --wait-for-build-sha` when the check must
wait until the deployed Flutter bundle exposes the expected build SHA before
running the location, weather, marker, and docent assertions. With
`--start-api`, the wrapper also starts a local API with
process-local auth and CORS, avoids Key Vault, DB, OpenAI, and Speech, and
checks the API log for `/healthz`, `/readyz`, and the authenticated `/api/v1/*`
routes loaded by the app shell.

The deployed public site flow is part of CI through
`.github/workflows/deployed-web-smoke.yml`. On `dev` pushes that change Flutter,
API app code, or the browser smoke wrapper, the workflow opens
`https://lala-next.cloud`, grants a fixed test geolocation, and fails if the
browser receives snapshot/fallback places, non-PostGIS place ordering, missing
AirKorea PM10/PM2.5 values, a docent script without live place/local
value/official grounding and captured PM context, raw score leakage, or a map
state that renders only clusters without pins. If the pushed diff changes the
Flutter app bundle, the workflow first waits for the deployed Flutter smoke
state to expose the pushed commit SHA. Backend-only, workflow-only, and smoke
wrapper-only pushes reuse the currently deployed web bundle and verify the live
API/browser contract without waiting for a frontend redeploy. The first
deployed run also simulates a denied geolocation request and verifies that the
user can still continue through the nationwide manual location fallback instead
of seeing a generic request failure.

To review alert and dashboard candidates without creating observability
resources:

```bash
scripts/unix/plan_observability.sh
```

```powershell
.\scripts\windows\plan_observability.ps1
```

For the signal inventory and approval gate, see
`docs/operations/observability-plan.md`.

To review OAuth/Entra identity rollout candidates without creating app
registrations, Key Vault secrets, or token validators:

```bash
scripts/unix/plan_identity_rollout.sh
```

```powershell
.\scripts\windows\plan_identity_rollout.ps1
```

The plan keeps LALA-next pointed at `lala-key-vault`, rejects ONMU vault
targets, and treats static auth retirement as blocked until API JWT validation
and Flutter token acquisition are verified together. For details, see
`docs/operations/identity-rollout.md`.

To review whether any ONMU Key Vault values are safe to reuse without reading,
printing, copying, or setting secret values:

```bash
scripts/unix/plan_key_vault_reuse.sh
```

```powershell
.\scripts\windows\plan_key_vault_reuse.ps1
```

The current approved-shape candidate is ONMU `int-cors-origins` copied into the
LALA vault as `cors-allow-origins`. DB, OAuth/social-provider, storage, Redis,
API token, OpenAI, and Speech values remain rejected for LALA runtime wiring.
For details, see `docs/operations/key-vault-reuse.md`.

To review legacy Flask replacement or retirement candidates without deleting
routes or changing deployments:

```bash
scripts/unix/plan_legacy_retirement.sh
```

```powershell
.\scripts\windows\plan_legacy_retirement.ps1
```

The plan maps legacy `/api/*`, `/api/ios/v1/*`, and `/api/planner/*` mobile
surfaces to `/api/v1/*`, keeps web/dashboard/action-log surfaces behind explicit
owner inventory, and requires rollback approval before any route removal. For
details, see `docs/migration/legacy-flask-retirement.md`.

To review local-only dev seed/reset SQL without touching a database:

```bash
scripts/unix/plan_dev_reset.sh
```

```powershell
.\scripts\windows\plan_dev_reset.ps1
```

Default mode is dry-run plan only. It reports file order, statement counts, and
SHA-256 hashes without connecting to PostgreSQL or printing `DB_DSN`.

Local dev apply is intentionally narrower than canonical SQL apply. It refuses
any `DB_DSN` whose host is not explicitly `localhost`, `127.0.0.1`, or `::1`,
and it requires the exact confirm string plus a process-local allow flag:

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

Do not use `sql/dev_reset` against Azure, shared, or production-like
PostgreSQL. Live DB rollout still starts with `verify_db_resources` and the
canonical SQL review/apply path.

Before any live DB apply, verify Azure-side database readiness:

```bash
scripts/unix/plan_db_rollout.sh
```

```powershell
.\scripts\windows\plan_db_rollout.ps1
```

The rollout plan is non-mutating. It shows proposed Azure CLI commands,
canonical SQL hashes, and approval gates without creating resources, applying
SQL, or printing secret values.

```bash
scripts/unix/verify_db_resources.sh
```

```powershell
.\scripts\windows\verify_db_resources.ps1
```

The strict form uses `-RequireDatabase` and fails when the PostgreSQL Flexible
Server, database, required extension allowlist, or Key Vault `db-dsn` secret
name is missing.

`docents/script` reads non-expired rows from `travel.docent_scripts` before
calling Azure OpenAI. The docent generation and QA lane should prefer
`AZURE_OPENAI_DOCENT_DEPLOYMENT` (`gpt-5.4-mini` recommended) before the
generic deployment. Successful live Azure OpenAI scripts are written back to
that cache on a best-effort basis. A cache write failure emits a warning log
without logging the generated script body, but it does not fail the Wave 1 API
contract.

## Manual API Smoke

Start the API:

```powershell
.\scripts\windows\start_api.ps1 -Port 8080
```

When request correlation needs a local JSONL file:

```bash
scripts/unix/start_api.sh --port 8080 --access-log-path runtime/api-access.jsonl
```

```powershell
.\scripts\windows\start_api.ps1 -Port 8080 -AccessLogPath .\runtime\api-access.jsonl
```

To inspect that local JSONL file by the request ids shown in the Flutter app
shell, without printing query strings, auth headers, request bodies, generated
content, or untrusted extra fields:

```bash
scripts/unix/inspect_access_log.sh runtime/api-access.jsonl --request-id <request-id>
```

```powershell
.\scripts\windows\inspect_access_log.ps1 `
  -Path .\runtime\api-access.jsonl `
  -RequestId <request-id>
```

Smoke the public and authenticated routes:

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080
```

`smoke_api.ps1` can use `LALA_SMOKE_BEARER_TOKEN`,
`LALA_SMOKE_API_KEY`, `API_BEARER_TOKEN`, or `IOS_API_KEY`. Prefer
`LALA_SMOKE_BEARER_TOKEN` when validating an OAuth/Entra JWT so the client token
does not get confused with the server-side static `API_BEARER_TOKEN` setting.
When `KEY_VAULT_URL` is configured and Azure CLI is authenticated, the script
attempts to load the migration API key and then the optional static bearer token
from Key Vault. It never prints secret values.
Public smoke checks include `/healthz`, `/readyz`, `/metrics`, and
`/openapi.json`.
The smoke script validates `/readyz.data.mode`, `client_identity`, and
`jwt_validation`, then prints bounded `runtime_mode=...` and `identity=...`
summaries for the handoff log.
Without `-PaidDependency`, authenticated route checks are skipped when client
auth is not available.
When browser CORS should be verified, pass an allowed origin explicitly:

```bash
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080 --cors-origin http://localhost:3000
```

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080 -CorsOrigin http://localhost:3000
```

For a broader live API check after Azure deployment, run the Unix matrix smoke.
It validates category and language variants for `/api/v1/places`, multiple map
centers for weather/intervention/daily-plan routes, docent categories, and the
`audio/mpeg` docent audio response. It uses the same secret-safe auth selection
rules as `smoke_api.sh` and never prints client tokens or Key Vault secret
values.

```bash
scripts/unix/smoke_api_matrix.sh --base-url https://api.lala-next.cloud
```

To smoke an already-issued OAuth/Entra JWT against an API process that has
`OAUTH_ISSUER`, `OAUTH_AUDIENCE`, `OAUTH_JWKS_URL`, and
`OAUTH_REQUIRED_SCOPES` configured:

```bash
export LALA_SMOKE_BEARER_TOKEN="<do-not-commit-or-print>"
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080
unset LALA_SMOKE_BEARER_TOKEN
```

```powershell
$env:LALA_SMOKE_BEARER_TOKEN = "<do-not-commit-or-print>"
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080
Remove-Item Env:\LALA_SMOKE_BEARER_TOKEN
```

To prove the JWT verifier locally without real Entra, Key Vault, or Azure
network access, run the local OAuth/JWT smoke. It creates an ephemeral RSA key,
local JWKS server, temporary API process, valid JWT, and wrong-scope JWT, then
cleans them up:

```bash
scripts/unix/smoke_oauth_jwt.sh
```

```powershell
.\scripts\windows\smoke_oauth_jwt.ps1
```

The `/metrics` response includes process-local request counters plus readiness
and dependency gauges. It also exports `lala_next_runtime_mode` for the same
`/readyz.data.mode` labels. If `DB_DSN` is configured, scraping `/metrics` can
perform the same short DB readiness probe as `/readyz`.

## Azure Resource Verification

When the question is whether this repository is using the new LALA-next Azure
resources rather than the existing ONMU vault, run:

```bash
scripts/unix/verify_azure_resources.sh
```

```powershell
.\scripts\windows\verify_azure_resources.ps1
```

This check is intentionally separate from local and CI verification because it
requires Azure CLI login and live Azure read access. It prints resource names,
deployment metadata, and secret names only; it does not print secret values.

## On-Premises Verification

Use the on-premises verification path only after the target host has process
environment values for `DB_DSN` and required public-data/API keys. Keep
`KEY_VAULT_URL` empty unless Azure Key Vault is intentionally retained as a
temporary secret source.

Database schema verification:

```bash
scripts/unix/verify_db_schema.sh --json --connect-timeout 30 --python .venv/bin/python
```

```powershell
.\scripts\windows\verify_db_schema.ps1 `
  -EnvFile C:\services\lala-secrets\api.env `
  -ConnectTimeout 30
```

API smoke after starting the on-premises API:

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/readyz
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080
scripts/unix/smoke_api_matrix.sh --base-url http://127.0.0.1:8080
```

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080
```

Cutover rehearsal is not ready unless `/readyz` reports DB-backed operation with
`db=configured` and `postgis=configured`. The same smoke commands must pass
against the reverse-proxy or public rehearsal URL before any DNS change. The
full documentation path starts at
[onprem-migration-overview.md](onprem-migration-overview.md).

The smoke matrix assumes the restored database has representative place,
weather, score, and docent/RAG data. If the rehearsal target was rebuilt from
canonical SQL only, complete the approved ingest and refresh jobs before
treating a matrix failure as an API regression.

## Paid Dependency Checks

Live Azure OpenAI and Azure Speech checks are kept opt-in. Use them only when a
small paid smoke request is acceptable:

```bash
scripts/unix/start_api.sh --port 8080 --key-vault-url <KEY_VAULT_URL> --enable-live-ai --enable-live-speech
```

```powershell
.\scripts\windows\start_api.ps1 -Port 8080 -KeyVaultUrl <KEY_VAULT_URL> -EnableLiveAI -EnableLiveSpeech
```

In another terminal:

```bash
scripts/unix/smoke_api.sh --base-url http://127.0.0.1:8080 --key-vault-url <KEY_VAULT_URL> --paid-dependency
```

```powershell
.\scripts\windows\smoke_api.ps1 -BaseUrl http://127.0.0.1:8080 -KeyVaultUrl <KEY_VAULT_URL> -PaidDependency
```

The paid smoke checks verify that `docents/script` is backed by Azure OpenAI and
that `docents/audio` returns `audio/mpeg` bytes. They do not print secret values
or generated audio content. With `-PaidDependency`, missing client auth is a
failure rather than a skipped check.

When live Speech is disabled, the normal smoke expects
`POST /api/v1/docents/audio` to return a `SPEECH_NOT_CONFIGURED` JSON envelope
instead of synthesized-looking fallback bytes. Do not reintroduce local ID3 or
text-byte audio fallbacks; the frontend hides audio controls unless `/readyz`
reports live Speech.

The latest controller-session live smoke evidence is recorded in
[live-azure-smoke-2026-06-11.md](live-azure-smoke-2026-06-11.md).
