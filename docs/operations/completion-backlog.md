# LALA Completion Backlog

Last updated: 2026-06-25 KST

This backlog tracks remaining work found during the Azure migration and
franchise/local-value implementation pass. It is intentionally secret-safe:
do not add live resource names, Key Vault URLs, database DSNs, tokens, or
subscription identifiers here.

For dated execution history, use
[work-log.md](/Users/geondongkim/LALA-next/docs/operations/work-log.md).
This backlog is the current-state view, not the full narrative log.

Current baseline evidence:

- Shared dev deploys from the `dev` branch through Azure Dev Deploy.
- Latest dev workflow runs are green, including deployed API smoke and the
  extended matrix smoke.
- The deployed API matrix smoke checks 37 route variants across places,
  weather intervention, daily planning, docent scripts, and docent audio.
- Deployed web smoke now opens `lala-next.cloud`, waits for the expected Flutter
  build SHA, grants a fixed browser geolocation, and verifies DB/PostGIS places,
  AirKorea PM10/PM2.5, PM-grounded docent scripts with live place/local
  value/official grounding, and real map pins instead of cluster-only rendering.
- The Flutter web frontend now separates bundled startup fallback from real
  recommendation-load failures, retries every `getPlaces` refresh once, and
  schedules bounded background recovery attempts with smoke-visible browser
  telemetry for the latest frontend recovery state.
- The production API no longer scales all the way to zero for the public
  contest path. The live first-hit `places` latency regression was traced to
  Container Apps cold start and the current scale floor keeps one warm replica
  so `lala-next.cloud` can render normally on first open.
- Docent audio no longer has a local fake-byte fallback: live Speech returns
  `audio/mpeg`, while disabled Speech returns `SPEECH_NOT_CONFIGURED` and the
  Flutter UI hides audio controls.
- Official-data ingest now has applied shared-dev evidence for TourAPI, KCISA
  culture info, KOPIS, and Fair Trade franchise references with the currently
  configured local keys.
- The shared dev DB has TourAPI Gyeonggi and Seoul places, franchise brand
  references, restaurant business identity rows, `local-value-v2` score
  snapshots, and place-profile RAG chunks.
- KCISA and KOPIS culture data were refreshed on 2026-06-23 UTC. The shared dev
  DB has 185 KCISA rows and 280 KOPIS rows in `culture.events`; the latest
  `local-value-v2` pass wrote 2,636 score rows with non-null
  `culture_relevance_score`, and dynamic RAG has 465 `culture_event` chunks.
- Weather refresh now has a guarded public-data batch path. On 2026-06-23 UTC,
  it inserted fresh KMA/AirKorea-backed observations, recorded a succeeded
  `weather-refresh` row in `ops.job_runs`, regenerated `local-value-v2` score
  snapshots, and refreshed dynamic RAG chunks.
- Nationwide expansion is now documented as an active rollout lane rather than
  a future-only idea. The repo now has a dedicated nationwide rollout plan, a
  card-spending source inventory, and a fallback score plan for regions without
  approved card coverage.
- Review quality scoring is now connected to
  `community.place_mentions_weekly.attributes.review_quality.score`; the latest
  shared-dev scoring pass produced non-null `review_quality_score` for 4
  sufficient-evidence places and kept low-evidence places null.
- Docent QA tooling can now generate representative local-only scripts. The
  latest shared-dev write run selected 50 DB-backed records with category
  coverage of 13 attractions, 13 restaurants, 11 events, and 13 culture venues,
  generated 50 scripts without mutating `travel.docent_scripts`, and produced
  pending generation 0, generation errors 0, blocker count 0, and average auto
  precheck 96.04. Manual reviewer scoring and legacy parity review remain open.

## Not Current Blockers

These items should not be treated as active request failures while the above
baseline stays green.

| Area | Current status | Why it is not a blocker |
|---|---|---|
| Static snapshot fallback | Disabled for shared dev. Kept only as DB-outage or isolated local fallback. | Normal path is PostgreSQL plus Key Vault plus ingest/scoring/RAG jobs. |
| Offline fallback labels | Limited offline/local safety labels exist only for recovery paths. | They are explicitly kept out of the shared dev happy path, whose normal route is DB-backed. |
| Score explanation visibility | API returns score details; Flutter hides heavy score/reason detail unless the user opens it, and docent scripts avoid raw score/index narration. | This is a UX decision, not a data-path failure. |
| Official image gaps | Some TourAPI rows have no official image. | The app collapses the image slot rather than inventing mock images. |

## P0: Keep Gates Green

| Item | Current evidence | Done evidence |
|---|---|---|
| Preserve deployed API matrix smoke in CI | `.github/workflows/azure-dev-deploy.yml` runs `smoke_api.sh` and `smoke_api_matrix.sh` after revision update. | Every `dev` push that changes backend/runtime still passes Azure Dev Deploy and the matrix smoke. |
| Preserve deployed web location smoke in CI | `.github/workflows/deployed-web-smoke.yml` runs `smoke_flutter_web.sh --web-url https://lala-next.cloud/... --fail-on-console-error --check-location-denial-fallback` for the primary deployed run, then repeats the live-location smoke from Suwon coordinates. It waits for `--expect-build-sha "$GITHUB_SHA"` only when the pushed diff changes the Flutter app bundle. | The public browser path still proves the expected Flutter bundle when frontend changes, and otherwise proves the deployed web/API contract with DB/PostGIS places, AirKorea dust values, live place/local value/official-grounded docent scripts without raw score leakage, real map pins, and a nationwide manual-location fallback when geolocation is denied. |
| Keep worktree and dev branch clean | `dev` is aligned with `origin/dev` after the latest commits. | `git status --short --branch` is clean before handoff. |
| Keep secret-safe docs | Operations docs refer to GitHub/Azure stores, not live secret values. | `rg` finds no committed DSN, token, Key Vault URL, subscription ID, or generated resource name in public docs. |

## P1: Data and Scoring Completion

The following strategy docs define the 100% target for the remaining review,
RAG, and docent-quality gaps:

- [Review and Mention Preprocessing Strategy](review-mention-preprocessing-strategy.md)
- [Sentiment and Attribute Scoring Strategy](sentiment-attribute-scoring-strategy.md)
- [RAG Regeneration Strategy](rag-regeneration-strategy.md)
- [Docent Quality Manual QA Strategy](docent-quality-manual-qa-strategy.md)

| Item | Current evidence | Next action | Done evidence |
|---|---|---|---|
| Maintain KCISA culture information ingestion | KCISA was applied to shared dev on 2026-06-23 UTC. `culture.events` now has 185 KCISA rows, latest score rows all have culture relevance values, and RAG has current `culture_event` chunks. The guarded apply path now records `kcisa-culture-info-ingest` in `ops.job_runs`. | Repeat the guarded ingest before judge/demo windows and widen regions only when row quality is reviewed. | KCISA refresh has a current `ingest.source_files` record, a `kcisa-culture-info-ingest` job run, score batch has been rerun, and RAG reflects the latest rows. |
| Maintain KOPIS performance ingestion | KOPIS was applied to shared dev on 2026-06-23 UTC. `culture.events` now has 280 KOPIS rows across Gyeonggi and Seoul refreshes, with HTTPS-normalized official poster URLs flowing into RAG. The guarded apply path now records `kopis-ingest` in `ops.job_runs`. | Repeat the guarded ingest for the target date window before judge/demo windows. | KOPIS refresh has a current `ingest.source_files` record, a `kopis-ingest` job run, score batch has been rerun, and RAG reflects the latest rows. |
| Maintain card-spending source files | Both approved Gyeonggi card sources are applied to shared dev. The aggregate source covers 31 regions through 2025-01, and the detailed 2026-01 to 2026-03 source added 3,650 area rows plus 57,832 demographic rows for 15 regions on 2026-06-23 UTC. The guarded file-ingest apply path now records `card-spending-file-ingest` in `ops.job_runs`, and the follow-up score batch inserted 2,636 `local-value-v2` rows while dynamic RAG upserted 821 chunks. | Refresh the files when a newer approved public release is downloaded, and keep Seoul or non-Gyeonggi regions null until an approved card-spending source exists. | `economy.card_spending_area_monthly` and `economy.card_spending_demographics` have source-file-backed rows, `ops.job_runs` has a `card-spending-file-ingest` run, and `local_spending_score` is based on real file rows rather than inferred or mock consumption. |
| Persist weather observations | Guarded `plan_weather_observation_refresh.sh` tooling exists, is connected to repo verification, and has been applied once against shared dev. The latest check showed 40 weather rows, 20 rows from the last 6 hours, 35 rows with temperature, 40 PM10 rows, 40 PM2.5 rows, a succeeded `weather-refresh` job run, and fresh score/RAG refreshes. Score, RAG, KCISA, KOPIS, and card-spending guarded apply paths now also record `place-score-batch`, `rag-index`, `kcisa-culture-info-ingest`, `kopis-ingest`, and `card-spending-file-ingest` rows in `ops.job_runs`. | Schedule or manually repeat the approved refreshes before judging/demo windows and keep the producer cadence documented. | `/api/v1/weather` returns fresh DB-backed or live-nowcast-backed data, `ops.job_runs` has current weather, score, RAG, culture, and card-ingest runs, and `weather_fit_score` has recent observation input. |
| Add review attribute scoring | `run_place_score_batch` reads versioned review quality from `community.place_mentions_weekly`; `run_review_mention_ingest` provides guarded preprocessing; and `run_review_attribute_batch` now provides plan, deterministic preview, dry-run AI, and guarded apply paths for category-aware `review_attributes`/`review_quality`. The 2026-06-23 shared-dev run has 168 `review-mention-preprocess-v1` rows, 132 deterministic `review_attributes` rows, 10 `review_quality` rows, 168 `place_mention` RAG chunks, and the latest 2,636 score snapshots include 4 non-null `review_quality_score` rows. The new attribute batch preview found 4 sufficient-evidence candidates; live AI dry-run reached provider `429 Too Many Requests`, so apply should be retried when capacity is available. The bulk review lane is now explicitly routed to `AZURE_OPENAI_REVIEW_BATCH_DEPLOYMENT` first (`gpt-5.4-nano` recommended). | Expand approved review/mention source coverage, retry AI dry-run/apply before judging windows, rerun score/RAG, and review resulting docent QA rows. | Latest score snapshots contain non-null `review_quality_score` for eligible places with source metadata, tests cover ad filtering plus category-specific review retention rules, and AI-generated attribute rows are recorded with `review-attribute-batch` in `ops.job_runs`. |
| Complete docent QA scoring | `plan_docent_quality_qa.sh --write --generate-scripts --limit 50` now writes balanced local-only QA records with generated scripts and automated precheck summaries. The latest shared-dev run scored 50/50, had zero generation errors, zero blockers, and average auto precheck 96.04. The docent generation and QA lane is now explicitly routed to `AZURE_OPENAI_DOCENT_DEPLOYMENT` first (`gpt-5.4-mini` recommended). | Fill manual reviewer scores, notes, issue tags, fix owners, and `legacy_parity` for the frozen representative set. | 30-50 representative scripts have zero blockers, average manual score >= 90, every category average >= 85, and local-only QA evidence is available for team review. |
| Expand franchise evidence to branch locations | Brand-level Fair Trade Commission references are loaded; `economy.franchise_locations` is intentionally empty. | Add a suitable official branch-level source only if it provides address or coordinate evidence. | Restaurant identity matching can use branch-level address/coordinate evidence, not only brand-name statistics. |

## P1: Production Readiness

| Item | Current evidence | Next action | Done evidence |
|---|---|---|---|
| Replace contest public access with durable auth | Shared dev uses `LALA_PUBLIC_CONTEST_ACCESS=true` during the contest window so reviewers can use the app without login or a bundled static API token. | Choose OAuth/Entra token acquisition or a backend-for-frontend proxy for browser clients, then disable public contest access. | Flutter web remains usable without exposing static credentials, and API access is mediated by signed tokens or BFF session credentials. |
| Remove temporary DB firewall allowance | Azure migration status notes operator firewall cleanup is blocked by a delete lock. | During an approved maintenance window, remove or scope the lock and delete the temporary operator rule. | Firewall rules contain only approved runtime/network entries. |
| Add production networking and identity boundaries | Dev uses a shared lane; docs say production needs private networking and stronger identity. | Split staging/prod resources, review backup/restore, private access, managed identity, and DNS cutover. | Production checklist passes without relying on dev resource assumptions. |
| Persist observability beyond in-process metrics | Planning docs exist, and the frontend now emits browser-visible recovery telemetry, but durable dashboards, alerting, and root-to-docent request correlation are still open. The latest live smoke still showed some intermediate `docents/script` request aborts before a later successful response. | Create approved dashboards, alerts, retention policy, and owner routing, then add explicit monitoring for recovery exhaustion and repeated docent abort churn. | Operators can diagnose `/readyz`, first-hit latency, frontend-red/backend-green states, and worker/docent failures without local shell access. |

## P2: Maintainability and Cost

| Item | Current evidence | Next action | Done evidence |
|---|---|---|---|
| Avoid docs-only Azure redeploys | Azure Dev Deploy has path filters for API runtime, workers, Azure infra, SQL, smoke scripts, and dependency files. | Keep the filter list aligned when a new runtime entrypoint or deployment script is added. | Markdown-only changes do not rebuild/push the API image or update Container Apps. |
| Score snapshot retention | Historical `local-value-v1` and older `local-value-v2` rows remain for audit. | Decide archive/delete/partition policy. | A documented retention job or query policy exists and current reads still select the latest score. |
| Live worker/batch execution | Worker contracts and plans exist; weather refresh, score, RAG, KCISA, KOPIS, and card file ingest guarded apply paths now record `ops.job_runs`. | Schedule the approved producers, then extend the same pattern to any remaining public-data ingest jobs such as franchise reference refreshes. | Worker runs are observable in `ops.job_runs` and failure paths do not break API serving. |
| Legacy Flask retirement | A non-mutating plan exists; actual removal waits for consumer inventory. | Inventory remaining legacy route users and define rollback. | Legacy routes are either rebuilt, owner-approved as retained, or removed after a monitored deprecation window. |
| Flutter release hardening | Web app is deployed; production token storage, packaging, and platform distribution remain outside this backend wave. | Add platform-specific release checks after auth direction is final. | Web/mobile builds pass release-mode QA without exposing static credentials. |

## Verification Commands

Use these before claiming the backlog has moved:

```bash
scripts/unix/verify_repo.sh --skip-install --python .venv/bin/python
scripts/unix/smoke_api_matrix.sh --base-url https://api.lala-next.cloud --timeout 25
gh run list --branch dev --limit 5 --json databaseId,headSha,workflowName,status,conclusion,url
git status --short --branch --untracked-files=all
```
