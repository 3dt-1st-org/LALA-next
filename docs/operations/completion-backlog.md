# LALA Completion Backlog

Last updated: 2026-06-22 KST

This backlog tracks remaining work found during the Azure migration and
franchise/local-value implementation pass. It is intentionally secret-safe:
do not add live resource names, Key Vault URLs, database DSNs, tokens, or
subscription identifiers here.

Current baseline evidence:

- Shared dev deploys from the `dev` branch through Azure Dev Deploy.
- Latest dev workflow runs are green, including deployed API smoke and the
  extended matrix smoke.
- The deployed API matrix smoke checks 37 route variants across places,
  weather intervention, daily planning, docent scripts, and docent audio.
- Deployed web smoke now opens `lala-next.cloud`, grants a fixed browser
  geolocation, and verifies DB/PostGIS places, AirKorea PM10/PM2.5, PM-grounded
  docent scripts with live place/local value/official grounding, and real map
  pins instead of cluster-only rendering.
- Docent audio no longer has a local fake-byte fallback: live Speech returns
  `audio/mpeg`, while disabled Speech returns `SPEECH_NOT_CONFIGURED` and the
  Flutter UI hides audio controls.
- Non-mutating official-data previews pass for TourAPI, KCISA culture info,
  KOPIS, and Fair Trade franchise references with the currently configured
  local keys.
- The shared dev DB has TourAPI Gyeonggi and Seoul places, franchise brand
  references, restaurant business identity rows, `local-value-v2` score
  snapshots, and place-profile RAG chunks.

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
| Preserve deployed web location smoke in CI | `.github/workflows/deployed-web-smoke.yml` runs `smoke_flutter_web.sh --web-url https://lala-next.cloud/... --fail-on-console-error --check-location-denial-fallback` for the primary deployed run, then repeats the live-location smoke from Suwon coordinates. | The public browser path still proves DB/PostGIS places, AirKorea dust values, live place/local value/official-grounded docent scripts without raw score leakage, real map pins, and a nationwide manual-location fallback when geolocation is denied. |
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
| Apply KCISA culture information ingestion | Tooling and guarded wrappers exist; live preview returned Suwon culture rows and normalized official `culture.go.kr` thumbnails to HTTPS. Azure status still says Culture Info needs to be added to shared dev. | Apply with guarded env, then recompute scores and RAG. | `culture.events` contains KCISA rows and `culture_relevance_score` changes are visible in latest `local-value-v2` snapshots. |
| Apply KOPIS performance ingestion | Tooling and guarded wrappers exist; live preview returned Gyeonggi performance rows and normalized official `kopis.or.kr` poster URLs to HTTPS. KOPIS is still listed in open rollout work. | Apply with guarded env for the target region/window, then recompute scores and RAG. | `culture.events` contains KOPIS rows and RAG has current `culture_event` chunks. |
| Apply card-spending source files | Parser plan supports detailed and aggregate CSV/XLSX files, but no local card-spending source file was confirmed during the latest check. Shared dev rollout still lists card-spending files as open. | Download or provide approved source files, ingest them, verify hash de-duplication, then rerun score batch. | `economy.card_spending_area_monthly` and `economy.card_spending_demographics` have source-file-backed rows; `local_spending_score` is based on real file rows. |
| Persist weather observations | Runtime can fall back to public-data nowcast, but scheduled persistence is still worker/batch work. | Add or schedule a weather refresh job that writes `travel.weather_observations`. | `/api/v1/weather` returns fresh DB-backed or live-nowcast-backed data, and `weather_fit_score` has recent observation input. |
| Add review attribute scoring | `review_quality_score` is documented as `pending_review_attribute_analysis`. | Build ad-filtered review attribute/sentiment batch for taste, service, and selected local-experience attributes. | Latest score snapshots contain non-null `review_quality_score` with source metadata and tests for ad-filtering rules. |
| Expand franchise evidence to branch locations | Brand-level Fair Trade Commission references are loaded; `economy.franchise_locations` is intentionally empty. | Add a suitable official branch-level source only if it provides address or coordinate evidence. | Restaurant identity matching can use branch-level address/coordinate evidence, not only brand-name statistics. |

## P1: Production Readiness

| Item | Current evidence | Next action | Done evidence |
|---|---|---|---|
| Replace contest public access with durable auth | Shared dev uses `LALA_PUBLIC_CONTEST_ACCESS=true` during the contest window so reviewers can use the app without login or a bundled static API token. | Choose OAuth/Entra token acquisition or a backend-for-frontend proxy for browser clients, then disable public contest access. | Flutter web remains usable without exposing static credentials, and API access is mediated by signed tokens or BFF session credentials. |
| Remove temporary DB firewall allowance | Azure migration status notes operator firewall cleanup is blocked by a delete lock. | During an approved maintenance window, remove or scope the lock and delete the temporary operator rule. | Firewall rules contain only approved runtime/network entries. |
| Add production networking and identity boundaries | Dev uses a shared lane; docs say production needs private networking and stronger identity. | Split staging/prod resources, review backup/restore, private access, managed identity, and DNS cutover. | Production checklist passes without relying on dev resource assumptions. |
| Persist observability beyond in-process metrics | Planning docs exist, but durable dashboards and log retention are still open. | Create approved dashboards, alerts, retention policy, and owner routing. | Operators can diagnose `/readyz`, latency, 5xx, and worker failures without local shell access. |

## P2: Maintainability and Cost

| Item | Current evidence | Next action | Done evidence |
|---|---|---|---|
| Avoid docs-only Azure redeploys | Azure Dev Deploy has path filters for API runtime, workers, Azure infra, SQL, smoke scripts, and dependency files. | Keep the filter list aligned when a new runtime entrypoint or deployment script is added. | Markdown-only changes do not rebuild/push the API image or update Container Apps. |
| Score snapshot retention | Historical `local-value-v1` and older `local-value-v2` rows remain for audit. | Decide archive/delete/partition policy. | A documented retention job or query policy exists and current reads still select the latest score. |
| Live worker/batch execution | Worker contracts and plans exist; live producer wiring is still a later rollout. | Implement approved worker runtime for weather, culture refresh, card ingest, score/RAG jobs. | Worker runs are observable in `ops.job_runs` and failure paths do not break API serving. |
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
