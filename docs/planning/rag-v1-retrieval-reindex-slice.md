# RAG V1 — Retrieval + Reindex Lifecycle Foundation (implementation slice)

Branch: `geondongkim/rag-v1-retrieval-reindex` (off `origin/main`).
Spec: `docs/planning/cleanroom-rag-docent-reimplementation-plan.md` §5–§7.
Scope: a **coherent, additive, testable vertical slice** of the RAG V1 retrieval and
reindex lifecycle — **not** a production rollout. No live OpenAI call, no DB migration
apply, no crawl, no UI work, no model-role router, no online rerank.

## Implementation checklist

1. **Embedding method/generation contract** (`config.py`, `rag_index.py`)
   - New config: `rag_embedding_method` (default `local-hash`, dev/test safe),
     `rag_embedding_generation` (default `1`), `rag_retrieval_mode` (default `legacy`
     → no-op deploy), `docent_script_ttl_sec` (default `604800`), reindex caps.
   - `resolve_serving_embedding_method(settings)` + `assert_semantic_embedding_when_live(settings)`:
     when `enable_live_ai=true`, the serving method may **not** be `local-hash` unless an
     explicit escape hatch is set — no silent semantic fallback. `local-hash` is documented
     as dev/test only. General OpenAI naming only in the new contract.
   - **Runtime wiring (P0 remediation, R1):** the guard is evaluated, not just unit-tested.
     `apps/api/app/main.py: create_app()` calls `assert_semantic_embedding_when_live(settings)`
     at boot when `rag_retrieval_mode == "hybrid"`, so a live-AI + non-semantic-method
     misconfiguration fails app startup with a clear `RuntimeError` instead of degrading per
     request. `apps/api/app/tools/run_rag_index.py: _apply_guard_error()` evaluates the same
     guard (shared by `--apply` and `--reindex --apply`) before the confirm/env-gated call
     opens a DB connection, rejecting with `{"ok": false, "error": ...}` + exit 2. The legacy
     default (`rag_retrieval_mode=legacy`) never triggers either check — zero behavior change.

2. **Additive canonical SQL (unapplied)** — `sql/canonical/064_rag_knowledge_retrieval_metadata.sql`
   - `ALTER TABLE rag.knowledge_chunks ADD COLUMN IF NOT EXISTS embedding_generation int NOT NULL DEFAULT 0`.
   - Stale-selection index on `embedding_generation`; GIN index on `metadata` for hybrid filters.
   - Non-destructive, `IF NOT EXISTS`, **documented as unapplied** (awaits a separate
     `ALLOW_CANONICAL_SQL_APPLY=1` rollout). Exact-list canonical test updated (12 → 13 files,
     ending in `064_rag_knowledge_retrieval_metadata.sql`).
   - **Merge-order follow-up (unmerged Draft PR #64, `geondongkim/official-data-ingest-reliability`):**
     that branch adds `sql/canonical/063_official_source_provenance.sql` and also sets the
     `test_canonical_sql.py` exact-list to 13 files. After PR #64 merges to `main`, this
     branch (or its merge) must be reconciled so the exact-list contains **both** `063_*` and
     `064_*` and `file_count == 14`. Do **not** weaken the exact-list assertion (no sorted/
     partial-match relaxation) to work around this — reconcile the literal list instead.

3. **Idempotent stale-chunk selection + reindex** (`rag_index.py`, `run_rag_index.py`)
   - Pure stale predicate: `content_sha256` changed **or** `embedding_generation < serving`.
   - `select_stale_chunks` (read-only SELECT), `reindex_stale_chunks` (idempotent
     `ON CONFLICT`/`UPDATE`, batched, per-run chunk cap, resumable — stale predicate
     re-evaluated each run). `--reindex` plan/preview/apply with the existing
     `--confirm APPLY_RAG_INDEX` + `ALLOW_RAG_INDEX_APPLY=1` gate. No external call in tests.

4. **Hybrid retrieval + deterministic RRF seam** (`rag_retrieval.py`, `db_repository.py`)
   - Pure `reciprocal_rank_fusion` (k=60, deterministic tie-break), `RetrievalFilters`
     (place/category/region/language/is_indoor), `fetch_hybrid_candidates` (ANN leg ∪
     keyword `ILIKE` leg ∪ metadata filters → RRF).
   - `fetch_docent_knowledge_context_hybrid` returns the **same shape** as the legacy
     grounding so docent consumes either. Legacy path preserved as `rag_retrieval_mode=legacy`
     rollback. **No online mini rerank** (RRF-only; `reranker="rrf"`).
   - **No silent config fallback (P0 remediation, R5):** the `try/except` around
     `fetch_hybrid_candidates` catches only `psycopg2.Error` (DB connection/query faults),
     which safely degrades to `[]` so the caller falls back to legacy/profile grounding.
     Config errors — an unsupported embedding method or missing live-AI credentials, raised
     as `RuntimeError`/`ValueError` — are **not** caught here; they propagate so a
     misconfiguration surfaces loudly instead of silently degrading to legacy grounding.

5. **Docent integration behind `rag_retrieval_mode`** (`docent_service.py`)
   - `generate_script` uses hybrid grounding only when `rag_retrieval_mode="hybrid"`, else the
     existing SQL-by-`place_id` path (safe rollback).
   - `script_identity` includes `embedding_generation` (+ retrieval mode) so a reindex
     invalidates stale cached scripts. TTL from config. Fallback stays grounded in the
     retrieved chunks — **never** a mock/placeholder.

6. **Opt-in provenance-safe citations (backward compatible)** (`docent_service.py`)
   - `build_citations` emits citation **pointers** (source_type/source_id/title/language_avail/
     similarity_band/ref) — no raw review/body content. Added as nullable `citations` +
     `retrieval` meta **only in hybrid mode**; absent in legacy mode. Response is a plain dict
     (no strict response model), so the wire stays backward compatible.

7. **RAG serving state on `/readyz` (P0 remediation, R2)** (`core/readiness.py`)
   - `build_readiness` adds `rag_retrieval_mode`, `rag_embedding_method`, and
     `rag_embedding_generation` to `checks` as **report-only** fields, so an operator can see
     from `/readyz` alone whether docent grounding is legacy or hybrid, and whether a
     dev-only `local-hash` method is serving. `mode.overall` and the existing
     `_overall_readiness_status` degraded logic are unchanged.

## Known follow-ups from independent P0 review (controller, 2026-07-26)

- **R3 — merge-order reconciliation (see item 2 above):** after Draft PR #64 merges, update
  the `test_canonical_sql.py` exact-list to include both `063_official_source_provenance.sql`
  and `064_rag_knowledge_retrieval_metadata.sql` (`file_count == 14`). Not done in this PR —
  PR #64's branch/files are out of scope here.
- R1, R2, R4, R5 above are addressed in this PR.

## Explicitly NOT in this slice

Online mini rerank · live embedding backfill (run by an operator later, not here) ·
untranslated-English generation · external review collection · full UI work · actual DB
migration apply · model-role router · audio cache · reason endpoint.

## Test plan (focused, no live calls)

- Embedding guard: live AI + `local-hash` → guard raises; live AI + `openai` → ok; default → ok.
- Stale/reindex gating: predicate logic, `--reindex --apply` requires confirm+env, caps honored,
  resumable (second run → 0 stale after first updates generation).
- RRF: ordering, dedup by `(source_type, source_id)`, metadata-filter narrowing.
- Retrieval-mode rollback: `legacy` calls legacy repo fn; `hybrid` calls hybrid fn.
- Cache invalidation: `script_identity` changes when `embedding_generation` bumps.
- No secret/raw-review leakage: citation objects carry no `body_*`; redaction paths unchanged.
- **Boot guard wiring:** `create_app()` raises for `hybrid` + live AI + `local-hash` (no
  escape hatch); passes for `hybrid` + live AI + `openai`; passes for the `legacy` default
  (no behavior change).
- **Apply-gate wiring:** `run_rag_index.py --apply` and `--reindex --apply` reject (exit 2,
  `{"ok": false, "error": ...}`) on a guard violation even with confirm/env satisfied, before
  any DB-connecting function is called.
- **`/readyz` RAG fields:** response `checks` includes `rag_retrieval_mode`,
  `rag_embedding_method`, `rag_embedding_generation`; `mode.overall` is unchanged.
- **Hybrid grounding error split:** `fetch_docent_knowledge_context_hybrid` returns `[]` on a
  `psycopg2.Error` (infra) and propagates `RuntimeError`/`ValueError` (config) instead of
  swallowing it.
