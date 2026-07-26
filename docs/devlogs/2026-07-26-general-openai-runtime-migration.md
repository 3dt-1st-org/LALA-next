# 2026-07-26 General OpenAI Runtime Migration

## Decision

LALA AI model calls use the standard OpenAI API. Azure OpenAI is not a runtime
provider for docent generation, place enrichment, review processing, or RAG
embeddings. Azure Speech remains an independent optional TTS dependency.

## Runtime contract

- Required for live AI: `OPENAI_API_KEY` and `LALA_ENABLE_LIVE_AI=true`.
- Optional endpoint: `OPENAI_BASE_URL`, defaulting to `https://api.openai.com/v1`.
  Azure OpenAI hosts are rejected before a client is constructed.
- Bulk review extraction, ad classification, and mention normalization use
  `OPENAI_REVIEW_BATCH_MODEL`, default `gpt-5.4-nano`.
- Low-confidence review recheck, docent generation and QA, and place
  enrichment use `gpt-5.4-mini` by default through `OPENAI_REVIEW_RECHECK_MODEL`,
  `OPENAI_DOCENT_MODEL`, and `OPENAI_PLACE_ENRICHMENT_MODEL`.
- Embeddings use `OPENAI_EMBEDDING_MODEL`, default `text-embedding-3-small`.

## Changed paths

- `services/ai_service.py`: standard `OpenAI` client and `source: openai`.
- `tools/enrich_place_ai_columns.py`: standard `OpenAI` client and
  `travel.place_enrichments.source_method = openai`.
- `tools/run_docent_quality_qa.py`, `/readyz`, OpenAPI schemas, smoke scripts,
  and `.env.example`: reflect general OpenAI configuration.
- Startup scripts only preload LALA-owned `OPENAI_*` values. They never print
  secret values.

## Verification

```bash
uv run ruff check apps/api/app apps/api/tests
uv run ruff format --check apps/api/app apps/api/tests
uv run pytest apps/api/tests -q
uv run pre-commit run --all-files
```

The checks use fakes and do not make a paid OpenAI request. A separate,
explicitly approved device smoke may exercise live generation after the API
revision is deployed or started locally with the process environment injected.
