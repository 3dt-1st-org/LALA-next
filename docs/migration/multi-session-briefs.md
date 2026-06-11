# Multi-Session Implementation Briefs

These briefs are for visible Codex sessions that continue work after the Wave 1 skeleton is committed. After `0183639`, Wave 1 includes the FastAPI edge, `/api/v1/*` contract routes, deterministic skeleton fallbacks, opt-in Azure OpenAI/Speech checks, canonical SQL files, Windows start/smoke/verification scripts, and LALA-next-only Key Vault handoff.

## Controller

Owns branch state, merge order, verification, commit, and push.

## Session A - API Skeleton

Maintain FastAPI app structure, health/readiness, auth dependency, request ID handling, and response envelope behavior. Keep `/healthz` and `/readyz` unauthenticated and `/api/v1/*` behind `X-API-Key`.

## Session B - V1 Routes

Expand `/api/v1/*` route behavior only when the Flutter contract requires it. Preserve current language normalization, JSON envelope behavior, and the audio success exception returning `audio/mpeg`.

## Session C - Service Import

Port pure service logic from the legacy LALA repo without Flask, Jinja, or request/session coupling. Current places, weather, planner, and docent-cache services have read-only PostgreSQL hooks behind `DB_DSN` plus skeleton fallback; Azure OpenAI and Azure Speech are live-capable behind explicit opt-in flags.

## Session D - SQL Canonical

Deepen canonical SQL mapping and convert legacy SQL into safe shared migration order. Keep canonical SQL non-destructive and place destructive reset/seed helpers under `sql/dev_reset`.

## Session E - Windows Ops

Harden PowerShell start/smoke scripts and LAN backend handoff docs. Keep `.venv\Scripts\python.exe` auto-selection, `-Python` overrides, and `-KeyVaultUrl` live-smoke handoff documented for start, smoke, and verification flows.

## Session F - Docs/Contract

Keep API contract, OpenAPI usage, migration docs, and Flutter handoff synchronized.

## Session G - Verification

Run tests, secret scans, SQL safety checks, and report residual risks.
