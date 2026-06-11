# Multi-Session Implementation Briefs

These briefs are for visible Codex sessions that continue work after the Wave 1 skeleton is committed. Current Wave 1 includes the FastAPI edge, `/api/v1/*` contract routes, deterministic skeleton fallbacks, opt-in Azure OpenAI/Speech checks, DB-backed read/cache hooks, docent-cache write-back, canonical SQL compatibility views, Windows start/smoke/verification scripts, and LALA-next-only Key Vault handoff.

## Controller

Owns branch state, merge order, verification, commit, and push.

## Session A - API Skeleton

Maintain FastAPI app structure, health/readiness, auth dependency, request ID handling, and response envelope behavior. Keep `/healthz` and `/readyz` unauthenticated and `/api/v1/*` behind `X-API-Key`.

## Session B - V1 Routes

Expand `/api/v1/*` route behavior only when the Flutter contract requires it. Preserve current language normalization, JSON envelope behavior, and the audio success exception returning `audio/mpeg`.

## Session C - Service Import

Port pure service logic from the legacy LALA repo without Flask, Jinja, or request/session coupling. Current places, weather, planner, and docent-cache services have PostgreSQL hooks behind `DB_DSN` plus skeleton fallback. Places are radius-ranked, weather prefers a nearest-region match, docent-cache hits expose remaining TTL, and live Azure OpenAI scripts are written back on a best-effort basis.

## Session D - SQL Canonical

Deepen canonical SQL mapping and convert legacy SQL into safe shared migration order. Keep canonical SQL non-destructive, preserve `v_legacy_*_api` compatibility view naming, and place destructive reset/seed helpers under `sql/dev_reset`.

## Session E - Windows Ops

Harden PowerShell start/smoke scripts and LAN backend handoff docs. Keep `.venv\Scripts\python.exe` auto-selection, `-Python` overrides, and `-KeyVaultUrl` live-smoke handoff documented for start, smoke, and verification flows.

## Session F - Docs/Contract

Keep API contract, OpenAPI usage, migration docs, and Flutter handoff synchronized.

## Session G - Verification

Run tests, secret scans, SQL safety checks, and report residual risks.
