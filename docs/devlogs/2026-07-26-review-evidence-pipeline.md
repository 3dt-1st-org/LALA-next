# 2026-07-26 — Review-evidence pipeline clean-room slice

Branch: `geondongkim/review-evidence-pipeline` (Draft PR vs `main`). Built on the
merged `review_ingest_governance` foundation (PR #62 lineage). No live DB
migration/apply, no production deploy, no external API calls, no real review
collection, no mock/demo runtime data.

## Scope

Provenance-safe review-evidence ingestion + quality pipeline. Makes approved
review exports / API adapters safely ingestible later; does **not** scrape
Naver/Daangn or call external review APIs. Spec:
`docs/planning/review-evidence-pipeline-clean-room-implementation.md`.

## What existed (foundation, retained)
`review_ingest_governance.py` already implements the clean-room ingest boundary:
DB-authoritative source gate, receipt idempotency on
`(source_name, external_key, content_sha256)`, raw-text-forbidden boundary
(`enforce_no_raw_review_text`), typed quarantine, single-transaction orchestrator.
Tables `ingest.review_sources` / `ingest.review_ingest_receipts` /
`community.ingest_runs` / `community.ingest_quarantine` already exist
(`062_review_ingestion_governance.sql`). This slice closes the gaps around it.

## Decisions / changes (bounded, no SQL migration)

**A. Non-organic / advertising exclusion at the governed boundary.**
`ReviewSourceRecord` gains `is_organic` + bounded `non_organic_reason`; a
non-organic record is quarantined (`terms_violation_non_organic`, category
`terms_violation` — already in the CHECK) and never projected to an aggregate.
The boundary holds no raw text, so it enforces the adapter's declaration rather
than re-deriving it.

**B. Two-tier model policy, standard OpenAI (never Azure).**
Per durable AI-policy correction: LALA AI uses **standard OpenAI only** —
gpt-5.4-nano for bulk review processing, gpt-5.4-mini for low-confidence
selective recheck (and docent/QA, out of scope here). Migrated
`review_attribute_batch.py` off Azure onto `openai.OpenAI` (reusing the
`rag_index` OpenAI convention: `OPENAI_API_KEY` + `LALA_ENABLE_LIVE_AI` gate;
key never logged). Added `openai_review_batch_model` / `openai_review_recheck_model`
config (default gpt-5.4-nano / gpt-5.4-mini), `selected_review_recheck_model`,
`route_low_confidence_enrichments`, `RECHECK_CONFIDENCE_THRESHOLD=0.6`, and an
injectable-client `generate_ai_recheck` that re-asks only low-confidence rows on
the mini model (best-effort, non-fatal, tagged `source_method="openai_recheck"`).
The runner redacts both `azure_openai_key` and `openai_api_key` from errors.

**C. Governed RAG handoff + invalidation signal.**
New `review_rag_handoff.py` (kept outside governance to preserve its no-RAG-write
contract): `ApprovedReviewAggregate` → aggregate-only `place_mention`
`KnowledgeChunk` (counts/sentiment/attribute scores/category; no body/title/url;
metadata guarded by `enforce_no_raw_review_text`), with deterministic
`content_sha256` → replay-safe. `rebuild_signals` / `changed_signals` emit the
explicit rebuild/invalidation signal (changed sha ⇒ rebuild; exact replay ⇒
`changed=False`, no duplicate RAG work). The handoff performs no DB write; the
existing `upsert_knowledge_chunks` owns the write behind the apply-guard.

**D. Closed the `community_post` raw-body RAG leak.**
`rag_index._community_post_chunk` no longer embeds the raw `community.posts`
body/title/post_url into the user-facing `rag.knowledge_chunks.body_ko`; the
chunk is categorical only. Review evidence reaches RAG via the governed
aggregate handoff (C), not raw post bodies. Privacy tradeoff (less
discriminative community-post embeddings) is intentional.

Preserved unchanged: mention-level ad filter (`AD_MARKERS`) + food rule
(`_category_policy`); attribute category vocabularies; `review_quality_score`
formula/caps; docent-side `_is_noisy_attraction_review_context` food guard.

## Evidence (verification)
- `uv run ruff check . && uv run ruff format --check .` — clean on changed files.
- `uv run pytest apps/api/tests` — all green **except** one pre-existing
  environmental failure: `test_oauth_jwt_smoke_tool.py::…runs_without_secret_values`
  (requires Logto/OAuth env; fails identically on `origin/main`'s `config.py` —
  verified by stashing my `config.py` and re-running). Unrelated to this slice.
- Review/rag/docent/governance suites: **186 passed**, including 14 new
  contract tests (`test_review_evidence_pipeline.py`) covering non-organic
  quarantine, confidence routing, nano-bulk/mini-recheck model roles (fake
  client, no live AI), governed-handoff no-raw-text + replay idempotency, and
  the community_post raw-body exclusion. Existing Azure-asserting test migrated
  to OpenAI (`test_generate_ai_enrichments_uses_openai_review_batch_model`).
- `uv run pre-commit run --files <my files>` — all hooks pass (scoped per the
  user's instruction; the main clone carries unrelated uncommitted Flutter work
  that is intentionally not staged/touched). `git diff --check` clean.
- No live AI calls, no live DB apply. `OPENAI_API_KEY` never printed/inspected/
  committed (test fixtures use `""` or a `# pragma: allowlist secret` dummy).

## Follow-up — review findings (same PR #63)

**B (runtime wiring).** The selective mini recheck is no longer dead code: the
runner (`run_review_attribute_batch`) now runs bulk `gpt-5.4-nano`, then routes
low-confidence rows through `gpt-5.4-mini` via `generate_ai_recheck` for
`--dry-run-ai`/`--apply`. Preview stays deterministic and never invokes either
live lane. When no rows are low-confidence, `generate_ai_recheck` is not called.
Output is truthful: `bulk_model`, `recheck_model`, `recheck_routed_count`,
`recheck_upgraded_count` (model names only; no secrets). Per-enrichment
`source_method` is preserved through apply (`openai_recheck` / `openai` /
`deterministic`) — `_apply_row` lets the enrichment's lane win over the generic
runner-level string.

**B (OpenAI wording completion).** Replaced every remaining Azure string in the
review-batch runner: `--dry-run-ai`/`--apply` help text, plan payload env names
(`OPENAI_REVIEW_BATCH_MODEL` / `OPENAI_REVIEW_RECHECK_MODEL`), apply requirements
(`DB_DSN`, `OPENAI_API_KEY`, `LALA_ENABLE_LIVE_AI`, `ALLOW_REVIEW_ATTRIBUTE_BATCH_APPLY`),
and dropped the stale `azure_openai_key` exception-redaction reference (now
redacts `openai_api_key` only for this lane). `parse_ai_response` bulk tag fixed
`azure_openai` → `openai`. Azure Speech / unrelated compatibility settings are
untouched.

**A (input consistency).** A contradictory declaration is now rejected at the
governed boundary, never accepted: `is_organic=true` with a `non_organic_reason`
→ `schema_invalid_contradictory_organic`; `is_organic=false` without a bounded
reason → `schema_invalid_non_organic_reason_missing`. (No live adapters exist
yet, so requiring the bounded reason is safe.)

**Tests added:** 6 runner-flow CLI tests (preview never invokes a live lane;
dry-run/apply invoke recheck after bulk; no low-confidence ⇒ no recheck; apply
preserves per-row `openai_recheck`; recheck returning bulk preserves the result),
1 apply per-row-provenance test, and 2 governance consistency tests. No live AI,
no live DB.

## Residual external blockers / out of scope
- No external review source is wired or called; approved adapters/exports must
  still be built to feed the governed boundary. Legacy Azure review pipeline was
  read-only reference only (some of its tables have no DDL there — flagged).
- `plan_rag_index_cleanup` (stale-chunk cleanup) remains proposed-only.
- Docent-lane model routing unit test (gap #11) and exhaustive `review_quality`
  cap tests (gap #10) are noted but out of scope.
- The broader legacy mention/attribute lane is hardened only at the RAG boundary
  (D); full migration of that lane onto the governed contract is a future slice.
