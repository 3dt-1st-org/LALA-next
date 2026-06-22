# RAG Regeneration Strategy

Last updated: 2026-06-22 KST

This document defines how LALA regenerates `rag.knowledge_chunks` after source
data, review attributes, weather, culture events, and local-value scores change.

## Target State

RAG should be the trusted bridge between structured data and generated
explanations. A completed RAG pipeline must:

- provide at least one `place_profile` chunk for every active DB-backed place;
- include dynamic chunks for culture events, review/mention attributes, and
  weather context when those signals exist;
- store source table, source ID, metadata, embedding method, and content hash;
- regenerate after score, event, mention, or weather updates;
- use Azure OpenAI embeddings in shared dev/prod once configured, while keeping
  `local-hash` available for deterministic local verification;
- block live DB docent generation when neither RAG nor verified place profile
  grounding exists.

## Current Gaps

| Gap | Current Evidence | Risk |
|---|---|---|
| Place-profile chunks exist, but dynamic chunks need richer review attributes | RAG input includes `community.place_mentions_weekly`, but review attributes are not complete. | Docents may be grounded but less vivid than legacy LALA. |
| Regeneration is manual | `plan_rag_index.sh` exists and is guarded, but worker scheduling is still future work. | Scores and RAG can drift after data refreshes. |
| Embedding method needs environment-specific policy | Local hash is safe for reproducibility; Azure embeddings are needed for better retrieval quality. | Search quality can lag behind production expectations. |
| Freshness checks are incomplete | Smoke checks grounding exists, but not full source freshness by table. | Old chunks could survive after new score/review batches. |
| Manual QA loop is not formalized | Deployed smoke checks one live path; representative place QA is separate. | A green smoke can miss category-specific quality gaps. |

## Regeneration DAG

RAG must run after these upstream jobs, in this order:

```text
official place/culture ingest
  -> franchise identity batch
  -> card spending ingest
  -> review/mention preprocessing
  -> sentiment/attribute scoring
  -> place score batch
  -> RAG regeneration
  -> API/web smoke
  -> manual docent QA
```

For weather:

```text
weather refresh
  -> optional weather_fit_score refresh
  -> dynamic RAG regeneration for weather_context
```

## Source Coverage Contract

| Source Type | Source Tables | Required For 100% |
|---|---|---|
| `place_profile` | `travel.places`, `analytics.place_score_snapshots` | Every active place. |
| `culture_event` | `culture.events`, `travel.place_events` | Places or regions with active events. |
| `place_mention` | `community.place_mentions_weekly` | Places with organic mention/review evidence. |
| `community_post` | `community.posts` | Only when source rights and matching confidence are sufficient. |
| `weather_context` | `travel.weather_observations` | Current weather-sensitive places and regions. |

No chunk should be generated from mock rows, synthetic demo text, or unapproved
manual copy.

## Chunk Quality Rules

Each chunk body should:

- be short enough for prompt use, generally 1 to 4 sentences;
- include user-facing source labels, not internal codes like `tour_api`;
- avoid raw scores unless they are in metadata only;
- summarize review attributes without quoting long review text;
- include `content_sha256` so repeated regeneration is idempotent;
- include `metadata.prompt_version` or `formula_version` when AI or scoring was
  involved;
- include `metadata.source_freshness` when source rows have timestamps.

Example `place_mention` metadata:

```json
{
  "schema_version": "review-attributes-v1",
  "organic_review_count": 38,
  "sentiment_score": 0.42,
  "top_attributes": ["atmosphere", "cultural_story", "walking_comfort"],
  "ad_filter_version": "review-mention-preprocess-v1"
}
```

## Apply Strategy

Current tool:

```bash
scripts/unix/plan_rag_index.sh
scripts/unix/plan_rag_index.sh --preview --source all --limit 20 --python .venv/bin/python
```

Apply with local deterministic embeddings:

```bash
ALLOW_RAG_INDEX_APPLY=1 \
  scripts/unix/plan_rag_index.sh \
  --apply \
  --confirm APPLY_RAG_INDEX \
  --source all \
  --embedding-method local-hash \
  --limit 3000 \
  --python .venv/bin/python
```

Apply with Azure OpenAI embeddings after Key Vault/runtime readiness:

```bash
ALLOW_RAG_INDEX_APPLY=1 \
  scripts/unix/plan_rag_index.sh \
  --apply \
  --confirm APPLY_RAG_INDEX \
  --source all \
  --embedding-method azure-openai \
  --limit 3000 \
  --python .venv/bin/python
```

Read-only query smoke:

```bash
scripts/unix/plan_rag_index.sh \
  --query "비 오는 날 실내 문화공간과 주변 로컬 경험" \
  --source all \
  --top-k 5 \
  --python .venv/bin/python
```

## Freshness and Deletion Policy

RAG regeneration should be upsert-first, but stale chunks need a policy:

- Upsert rows by `source_type`, `source_id`, and content hash.
- If a source record disappears or is marked inactive, mark its chunk inactive
  or remove it in a guarded cleanup mode.
- Do not delete historical score snapshots; RAG should select latest score rows.
- For review/mention chunks, require the current `week_start` window or a
  configured rolling window, such as 4 to 8 weeks.
- For weather chunks, prefer recent observations and avoid stale weather claims
  in long-lived place profiles.

Proposed cleanup mode:

```bash
scripts/unix/plan_rag_index_cleanup.sh --preview --source dynamic
ALLOW_RAG_INDEX_CLEANUP_APPLY=1 \
  scripts/unix/plan_rag_index_cleanup.sh \
  --apply \
  --confirm APPLY_RAG_INDEX_CLEANUP
```

## Verification Matrix

| Check | Command or Evidence | Pass Criteria |
|---|---|---|
| Plan safety | `scripts/unix/plan_rag_index.sh` | No DB mutation and no secrets printed. |
| Preview coverage | `--preview --source all` | Candidate count matches active source rows. |
| Apply guard | `--apply` without env/confirm | Fails safely. |
| Place grounding | API docent tests and deployed smoke | `grounding_count > 0` for DB-backed places. |
| Retrieval | `--query` smoke | Top results include expected source types. |
| Public script safety | `smoke_api_matrix.sh` and web smoke | No internal labels, raw scores, demo/mock wording, or fallback source. |
| Freshness | SQL/reporting query | Chunks updated after latest score/review batch. |

## 100% Completion Definition

This area reaches 100% when:

- all active places have current `place_profile` chunks;
- eligible places have review/mention chunks after preprocessing and attribute
  scoring;
- active culture/event rows produce `culture_event` chunks;
- weather-sensitive regions have fresh `weather_context` chunks or the system
  intentionally avoids stale weather RAG;
- shared dev/prod use Azure OpenAI embeddings when configured, with local hash
  retained for local reproducibility;
- live DB docent generation never falls back to mock or generic text when
  grounding is missing;
- deployed API matrix smoke and deployed web smoke stay green after regeneration;
- representative manual docent QA passes with no blocker issues.
