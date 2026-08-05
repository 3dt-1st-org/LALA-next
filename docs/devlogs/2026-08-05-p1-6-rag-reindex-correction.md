# 2026-08-05 P1-6 RAG Reindex Correction

## Summary
Production-safe correction of the `--embedding-method` CLI option default behavior in RAG reindex operations. The CLI now resolves the embedding method from `settings.rag_embedding_method` when the operator omits the option, instead of hardcoding "local-hash".

## Changes

### apps/api/app/tools/run_rag_index.py
- Changed `--embedding-method` argument `default` from `"local-hash"` to `None`
- Added `_resolve_embedding_method()` helper to resolve from settings when CLI arg is omitted
- Applied resolved method consistently across all modes: plan, preview, apply, query, reindex
- Exception redaction already uses standard `settings.openai_api_key` field (no legacy Azure fields)

### apps/api/tests/test_rag_index.py
Added comprehensive offline tests for P1-6 contract:
- `test_rag_index_plan_resolves_embedding_method_from_settings_when_omitted` - verifies CLI omission resolution
- `test_rag_index_plan_honors_explicit_embedding_method` - explicit args override settings
- `test_rag_index_reindex_plan_resolves_embedding_method_from_settings` - reindex plan resolution
- `test_rag_index_apply_resolves_embedding_method_and_reports` - apply mode reports resolved method
- `test_rag_index_reindex_apply_resolves_embedding_method_and_reports` - reindex apply resolution
- `test_rag_index_resolved_method_still_enforces_live_ai_guard` - guard not bypassed by resolved method
- `test_rag_index_explicit_method_still_enforces_live_ai_guard` - guard enforced for explicit overrides
- `test_rag_index_openai_redaction_uses_standard_api_key_field` - standard OpenAI redaction verified
- `test_rag_index_reindex_openai_redaction_uses_standard_api_key_field` - reindex redaction verified

## Verification
```bash
# Run focused tests (offline with fake DB seams)
pytest apps/api/tests/test_rag_index.py::test_rag_index_plan_resolves_embedding_method_from_settings_when_omitted -xvs
pytest apps/api/tests/test_rag_index.py::test_rag_index_plan_honors_explicit_embedding_method -xvs
pytest apps/api/tests/test_rag_index.py::test_rag_index_apply_resolves_embedding_method_and_reports -xvs
pytest apps/api/tests/test_rag_index.py::test_rag_index_openai_redaction_uses_standard_api_key_field -xvs
```

## Remaining Operator Gates
1. **Migration**: `sql/operator-pending/064_rag_knowledge_retrieval_metadata.sql` must be approved and applied separately
2. **Environment**: `LALA_RAG_EMBEDDING_METHOD` must be configured for production semantic embedding
3. **Apply safety**: `--apply` still requires `ALLOW_RAG_INDEX_APPLY=1` and `--confirm APPLY_RAG_INDEX`
4. **Live AI guard**: Existing `LALA_ENABLE_LIVE_AI=true` guard rejects `local-hash` without `LALA_RAG_ALLOW_LOCAL_HASH_LIVE=1`
5. **Manual backfill**: Existing chunks need reindexing when changing embedding generations

## Impact
- **No breaking changes**: Existing scripts with explicit `--embedding-method` continue unchanged
- **Production safety**: Resolved method goes through existing guards before any DB operation
- **Security**: Exception redaction verified to use standard OpenAI API key field, not legacy Azure secrets
- **Test coverage**: All tests remain offline with fake DB seams, no live provider/cloud/DB operations
