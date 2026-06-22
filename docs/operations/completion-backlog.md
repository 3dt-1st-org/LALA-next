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
- Official-data ingestion has been applied to shared Azure dev for TourAPI,
  KCISA culture info, KOPIS, Fair Trade franchise references, card-spending
  area-month aggregates, and representative public weather observations.
- The shared dev DB has TourAPI Gyeonggi and Seoul places, franchise brand
  references, restaurant business identity rows, KCISA/KOPIS culture events,
  card-spending aggregates, public-weather observations, refreshed
  `local-value-v2` score snapshots, and place/culture-event RAG chunks.

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
| Preserve deployed web location smoke in CI | `.github/workflows/deployed-web-smoke.yml` runs `smoke_flutter_web.sh --web-url https://lala-next.cloud/... --fail-on-console-error` for relevant `dev` pushes. | The public browser path still proves DB/PostGIS places, AirKorea dust values, live place/local value/official-grounded docent scripts without raw score leakage, and real map pins. |
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
| Keep KCISA/KOPIS culture ingestion current | Shared dev now has 383 `culture.events` rows: 183 KCISA and 200 KOPIS, followed by score and RAG regeneration. | Turn the guarded operator commands into a scheduled worker job after the batch runtime is approved. | Culture-event counts refresh on schedule and failures are visible in `ops.job_runs` or equivalent worker telemetry. |
| Keep card-spending source files current | Shared dev has 149,341 `economy.card_spending_area_monthly` rows. Demographic detail is intentionally not part of the current scoring path. | Add an incremental file-ingest runbook for new approved CSV/XLSX drops and decide whether demographics are needed for later personalization. | New source files are hash-deduplicated and latest score snapshots show non-null `local_spending_score` where regional/industry rows match. |
| Persist weather observations on schedule | Shared dev now has 20 representative `travel.weather_observations` rows, and runtime weather still has live KMA/AirKorea fallback for uncovered coordinates. | Schedule smaller incremental refreshes instead of one large all-region call. | Recent observations exist for the active regions and `/api/v1/weather` remains healthy when one provider is slow. |
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
| Avoid docs-only Azure redeploys | Azure Dev Deploy currently runs on every `dev` push, including docs-only updates. | Add path filters or split docs CI from runtime deploy once team workflow stabilizes. | Markdown-only changes do not rebuild/push the API image or update Container Apps. |
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
