# P1-0 Shared Contract Reconciliation

Date: 2026-08-05 KST
Phase: P1-0 — canonical migration ordering and shared contract reconciliation
Base: `origin/main` `18ef2426d2c2c1b4aacb532d6a614a7051ca0e39`

This document is a contract ledger for the independent P1-0 slice. It freezes
ownership and status without applying SQL, adding a future migration, running a
worker, or enabling an external provider.

## Status vocabulary

- `CURRENT`: merged on `main` and verified through the real DB/API path.
- `IMPLEMENTED_NOT_RUNTIME_VERIFIED`: code or schema is present and covered by
  offline tests, but the real runtime path has not been verified.
- `DRAFT_PR`: present only in an open Draft PR and not part of the merged base.
- `TARGET`: approved future contract or implementation.
- `BLOCKED_EXTERNAL`: requires an external owner, approval, credential, terms,
  data source, cost decision, or runtime operation.

This P1-0 session has no `CURRENT` promotion because migration apply and live
runtime verification are prohibited.

## Canonical migration baseline

The only canonical SQL files in `origin/main=18ef242` are the following, in
this exact order:

```text
000_extensions_and_schemas.sql
005_identity_users.sql
010_travel_core_tables.sql
020_travel_domain_tables.sql
030_community_core_tables.sql
035_data_pipeline_tables.sql
036_rag_knowledge_tables.sql
040_ops_core_tables.sql
050_views_and_indexes.sql
060_community_tables.sql
061_community_chat_tables.sql
062_review_ingestion_governance.sql
063_local_signals_contract.sql
```

`063_local_signals_contract.sql` is the latest merged baseline. A filename must
use a three-digit numeric prefix and no numeric prefix may occur twice. The
canonical runner rejects invalid prefixes, duplicate prefixes, and drift from
the merged baseline in the repository canonical directory.

`064` and later are not part of this baseline. In particular,
`sql/canonical/064_rag_knowledge_retrieval_metadata.sql` in the dirty root RAG
worktree is WIP only. P1-0 does not add, rename, apply, rebase, or assign
ownership to that file. A future migration requires a separate PR containing
its additive SQL, owner decision, ordered-list update, safety tests, and
reconciliation evidence.

## Shared contract ownership matrix

| Contract | SQL owner | API owner | Worker/data owner | Flutter/client owner | Test owner | Status | Next migration condition |
|---|---|---|---|---|---|---|---|
| Place identity, geo, region, category | `010_travel_core_tables.sql`; `travel.places` | `places_service.list_places`; `db_repository.fetch_places`; `region_catalog.py` | Official ingest services and `apps/workers/app/contracts.py` | `LalaApiBackend.getPlaces`; map/home place models | `test_v1_routes.py`; place service tests | `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; city/county region is `TARGET` | Additive region/catalog migration only after source authority, owner, and numbering are approved |
| Source registry/provenance | `062_review_ingestion_governance.sql`; `ingest.review_sources` | `review_ingest_governance.py` | Review acquisition/validation workers | No raw-source client surface | `test_review_ingest_governance.py` | `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; approved source terms are `BLOCKED_EXTERNAL` | No source table change without license, terms, retention, redaction, and owner decision |
| Official ingest receipt/coverage | `062_review_ingestion_governance.sql`; receipt/quarantine tables | Governance status only; no raw review endpoint | `tour_api_ingest.py`, `culture_info_ingest.py`, `kopis_ingest.py`, worker rollout contracts | Places consume only normalized public place fields | `test_tour_api_ingest.py`, `test_culture_info_ingest.py`, `test_kopis_ingest.py` | Existing source-specific code is `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; nationwide inventory/coverage is `TARGET` | Additive receipt/coverage fields require a source inventory, cursor/dedupe contract, and offline fixture |
| Feature flags and model roles | No new SQL; central runtime/config contract | `feature_flags.py::FEATURE_FLAG_REGISTRY`; `model_client.MODEL_ROLES` and `resolve` | Worker contracts must consume the same non-secret role/flag names | Client observes safe capability/error states only | `test_feature_flags.py`; `test_model_client.py` | `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; defaults remain current behavior | New flag or role requires registry entry, default-off/no-op semantics, owner, and contract tests |
| Review aggregate and raw-review prohibition | `030_community_core_tables.sql`, `035_data_pipeline_tables.sql`; `community.place_mentions_weekly` | Aggregate fields only through existing place/docent contracts | `review_mention_ingest.py`, `review_attribute_batch.py` | No raw review body, author, URL, or provider payload | review governance, mention, attribute, and safety tests | Aggregate path is `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; raw review persistence/exposure is prohibited | No schema/API expansion without accepted-only aggregate shape and retention decision |
| Franchise/small-merchant identity and score snapshot | `035_data_pipeline_tables.sql`; economy and analytics tables | `franchise_identity.py`, `recommendation_scoring.py`, place score services | `franchise_reference_ingest.py`, score batch contract | Place score/reason remains secondary and safe | `test_franchise_identity.py`, `test_place_score_batch.py`, scoring tests | `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; source refresh is `BLOCKED_EXTERNAL` until official data access is confirmed | Additive classification fields require official reference provenance, confidence rules, and fairness tests |
| RAG chunk, embedding generation, and citation | `036_rag_knowledge_tables.sql` current schema | `db_repository` retrieval context and docent service | `rag_index.py`/reindex tooling; future owner not fixed for WIP 064 | Docent client receives safe script/audio only | RAG index/retrieval/docent safety tests | Current chunk path is `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; metadata expansion and WIP 064 are `TARGET` with owner unresolved | No 064 migration or reindex until the owner, raw-body exclusion, metadata schema, and canonical number are approved |
| Docent script/audio | Current docent tables in `020_travel_domain_tables.sql`; no new P1 migration | `docent_service.py`; `/api/v1/docents/script` and `/audio` | Docent generation/QA role contracts | `LalaBackend.createDocentScript/createDocentAudio` | `test_docent_service.py`, API/OpenAPI tests | `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; live AI/TTS is `BLOCKED_EXTERNAL` | Additive cache/metadata migration requires model-role, provenance, language, and cost decisions |
| Plan slot, weather intervention, travel time | `020_travel_domain_tables.sql` current weather/place data | `planner_service.daily_plan`, intervention routes | `weather_observation_refresh.py`; future travel-time worker seam | `plan_page.dart`; generated `DailyPlanSlot` | `test_planner_service.py`, weather refresh tests | Current thin plan is `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; four slots/travel time are `TARGET` and provider is `BLOCKED_EXTERNAL` | New plan migration only after slot schema, opening-hours source, region precision, and provider decision |
| Local Signals canonical `category=all` lookup, translation, freshness | `063_local_signals_contract.sql`; first-party only | `LocalSignalRepository.list_public_signals`; public Local Signals schemas/routes | No translation or aggregate worker in P1-0 | `LalaApiBackend.getLocalSignals`; cross-category place action remains in PR #77 | Local Signals API/schema/safety tests; #77 Flutter tests remain Draft | Public read baseline is `IMPLEMENTED_NOT_RUNTIME_VERIFIED`; #77 action is `DRAFT_PR`; translation/freshness enrichment is `TARGET` | No migration change without preserving canonical place IDs, coarse region, locale exclusivity, and safe public projection |

## PR and branch dependencies

The following PRs have been merged and are now part of the `origin/main` baseline:

- [PR #76](https://github.com/3dt-1st-org/LALA-next/pull/76) (MERGED): AWS team
  handoff and local helper documentation.
- [PR #77](https://github.com/3dt-1st-org/LALA-next/pull/77) (MERGED): Flutter LS-4
  map/place/plan action boundary.
- [PR #78](https://github.com/3dt-1st-org/LALA-next/pull/78) (MERGED): P0 AWS runtime
  secret contract.

Current open Draft PRs that are not dependencies of this P1-0 slice:

- [PR #96](https://github.com/3dt-1st-org/LALA-next/pull/96), head
  `18ef242`: P0 runtime secret contract checkpoint.
- [PR #97](https://github.com/3dt-1st-org/LALA-next/pull/97): P2 official media
  probe contract.
- [PR #98](https://github.com/3dt-1st-org/LALA-next/pull/98): AWS deployment runtime
  contract.

P1-0 is based directly on `origin/main=18ef242` and does not import or modify
any of those PRs. P1-0 also does not consume the root checkout's RAG WIP
064 migration. P1-1 may start only as a new branch after this P1-0 contract
PR is reviewed and merged.

## P1-1 next slice

The next independent slice is **official data source inventory and coverage
dry-run contract**. It is limited to:

- source inventory and provenance metadata shape;
- cursor/pagination and deterministic dedupe contract;
- place identity, region, category, coordinate precision, image URL, and
  freshness normalization rules;
- synthetic/offline coverage and rejection fixtures;
- coverage/freshness report shape.

It does not include bulk ingestion, real official API calls, database writes,
seed/mock data in the normal path, migration apply, deployment, or external
collection.

## External blockers

- Official source terms, license, retention, and image URL permissions;
- AWS IAM role and logical secret inventory, region/prefix, and rotation policy;
- Database schema owner, apply window, backup/rollback, PostGIS/pgvector
  availability, and canonical migration number owner;
- Access to nationwide official data files and their provenance metadata;
- Model/API/TTS cost ceiling and provider quotas;
- Travel-time provider terms and opening-hours authority;
- Moderation SLA, deletion/retention, translation opt-out, and aggregate/RAG
  threshold policy.

No resource identifier, secret value, DSN, token, raw review body, or precise
user location is recorded here.
