# LALA Nationwide Expansion Plan

Last updated: 2026-06-24 KST

This plan describes how to expand the current Seoul and Gyeonggi-focused
testbed into a nationwide data and ranking pipeline without breaking the
existing shared-dev baseline. Keep this document secret-safe: do not add live
Key Vault URLs, DSNs, subscription ids, tokens, or generated resource names.

## Goal

Expand LALA from the current 수도권 중심 testbed into a nationwide public-data
pipeline for places, culture events, ranking inputs, and RAG context while
preserving these rules:

- Keep region scope in columns such as `province_code`, `city_code`, and
  `region_name_ko`, not in table names.
- Preserve the current guarded apply contract for all live ingests.
- Do not infer or fabricate region-specific score inputs when an approved source
  does not exist.
- Keep the existing shared-dev happy path green while nationwide ingestion is
  rolled out incrementally.

## Current Baseline

The current repository already uses nationwide-capable schema names:

- `travel.places`
- `culture.events`
- `economy.card_spending_area_monthly`
- `economy.card_spending_demographics`

The main remaining limitation is not schema shape. It is source coverage and
region-specific default behavior in ingest and enrichment code.

Current region-scoped defaults in code:

- TourAPI defaults to `areaCode=31` in
  `apps/api/app/services/tour_api_ingest.py` and
  `apps/api/app/tools/run_tour_api_ingest.py`.
- KCISA defaults to `sido=경기`, `sigungu=수원시` in
  `apps/api/app/services/culture_info_ingest.py` and
  `apps/api/app/tools/run_culture_info_ingest.py`.
- KOPIS defaults to `signgucode=41` in
  `apps/api/app/services/kopis_ingest.py` and
  `apps/api/app/tools/run_kopis_ingest.py`.
- Local region-name enrichment still has explicit 수도권 prefixes in
  `apps/api/app/services/local_place_enrichment.py`.
- Weather fallback has nationwide-ish bounding boxes in
  `apps/api/app/services/weather_service.py`, but it still relies on heuristic
  coordinate-to-sido mapping rather than a canonical region catalog.

Current product baseline:

- Shared dev already contains Gyeonggi and Seoul place coverage.
- The Flutter manual location sheet is already nationwide in
  `apps/flutter_app/lib/manual_location_options.dart`.
- Card spending remains Gyeonggi-only by approved source. Non-Gyeonggi
  `local_spending_score` must stay null until a real approved nationwide source
  exists.

## Non-Negotiable Constraints

- Nationwide expansion must not require table renames or schema redesign.
- Card-spending coverage must remain source-faithful. Do not backfill Seoul or
  other provinces with inferred, copied, or mocked values.
- Existing guarded apply tools must remain the only mutation path for shared
  environments.
- Region normalization logic must move toward a reusable catalog rather than
  adding more one-off if/else blocks.

## Target End State

The intended end state is:

- TourAPI ingest can sweep all supported `areaCode` values.
- KCISA ingest can sweep all supported `sido` values and optional `sigungu`
  partitions.
- KOPIS ingest can sweep all supported `signgucode` values and preserve the
  API's 31-day query-window limit.
- Region normalization, English labels, and weather fallback all read from a
  shared nationwide region catalog.
- Place score, RAG, and downstream API responses work nationwide for places and
  culture signals.
- Card-spending remains region-null where no approved source exists.

## Workstreams

### 1. Build a Shared Nationwide Region Catalog

Create a single source of truth for Korean administrative region metadata and
use it across ingest, normalization, and UI-adjacent helpers.

Suggested contents:

- province-level ids and labels
- areaCode mappings for TourAPI
- signgucode mappings for KOPIS
- normalized `sido` labels for KCISA
- optional `sigungu` code and label mappings
- English labels for `province_name_en` and `region_name_en`
- aliases for common variants such as `서울시`, `서울특별시`, `제주`, `제주특별자치도`

Suggested implementation shape:

- add a small Python module such as `apps/api/app/services/region_catalog.py`
- keep it dependency-light and deterministic
- optionally generate Flutter manual-location data from the same raw source in a
  later phase, but do not block backend nationwide rollout on that generator

This catalog should replace:

- `DEFAULT_SIGNGUCODE = "41"` style assumptions
- hard-coded Gyeonggi-only alias maps
- 수도권-only region prefix sets
- heuristic fallback labels that are hard to audit

### 2. Expand TourAPI Place Ingestion Nationwide

TourAPI is the easiest source to scale first because the schema is already
nationwide and the tool already accepts `--area-code`.

Current state:

- `apps/api/app/services/tour_api_ingest.py` defaults to `DEFAULT_AREA_CODE = "31"`
- `scripts/unix/plan_tour_api_ingest.sh` defaults to `AREA_CODE="31"`

Required changes:

- keep the current single-area tool intact for preview and targeted re-runs
- add a higher-level nationwide runner that loops over all area codes from the
  shared region catalog
- dedupe by `place_id` exactly as today
- keep official-image follow-up behavior intact
- record one source-file or job-run identity per area or per rollout batch,
  whichever is easier to audit

Suggested scope split:

- phase 1: province-level sweep only
- phase 2: add selective `sigungu` follow-up only if source gaps require it

### 3. Expand KCISA Culture Event Ingestion Nationwide

KCISA is currently hard-coded for `경기 / 수원시`.

Current state:

- `apps/api/app/services/culture_info_ingest.py`
- `apps/api/app/tools/run_culture_info_ingest.py`
- `scripts/unix/plan_culture_info_ingest.sh`

Required changes:

- make current defaults explicit testbed defaults rather than implied product
  scope
- add a nationwide batch runner that loops through supported `sido` values from
  the region catalog
- decide whether the first nationwide pass should query province-level only or
  province plus selected `sigungu` partitions
- preserve `region_name_ko = sigungu or area`
- add normalization for province labels so `경기` and `경기도` converge

Recommended rollout:

- first sweep by province only
- inspect row quality and duplication patterns
- then decide whether any province needs `sigungu` expansion

### 4. Expand KOPIS Performance Ingestion Nationwide

KOPIS needs more care because the current region inference is strongly
Gyeonggi-shaped.

Current state:

- `apps/api/app/services/kopis_ingest.py` uses `DEFAULT_SIGNGUCODE = "41"`
- `infer_region_name_ko` relies on `GYEONGGI_REGION_ALIASES`
- date windows are capped by `MAX_DATE_RANGE_DAYS = 31`

Required changes:

- replace `GYEONGGI_REGION_ALIASES` with a nationwide alias table derived from
  the shared region catalog
- add a nationwide batch runner that iterates all supported `signgucode` values
- preserve the 31-day window rule by splitting long refreshes into fixed date
  windows
- keep poster URL normalization and duplicate handling unchanged

Important note:

- KOPIS region inference should prefer canonical city/district labels from the
  catalog rather than free-text title parsing wherever possible

### 5. Generalize Region and English Enrichment

Some helper logic still assumes a small set of province names.

Current hotspots:

- `apps/api/app/services/local_place_enrichment.py`
- `apps/api/app/services/public_mvp_snapshot.py`
- `apps/api/app/services/tour_api_ingest.py`

Required changes:

- replace `_REGION_PREFIXES` and narrow address token maps with catalog-backed
  normalization
- allow English province and district names for all supported nationwide labels
- keep local romanization as fallback only, not as a hidden canonical source

Expected result:

- `region_name_ko` normalization becomes consistent across TourAPI, KCISA,
  KOPIS, and any later region-based source
- `region_name_en` can be generated consistently for all provinces and districts

### 6. Make Weather Fallback Region Mapping Catalog-Aware

`apps/api/app/services/weather_service.py` already covers many provinces with
bounding boxes, but this should be upgraded from heuristic-only mapping.

Required changes:

- keep current coordinate fallback behavior as a safe baseline
- move province label selection toward the shared nationwide region catalog
- add tests for coordinates across all provinces, not just Seoul and Gyeonggi

This work is important because nationwide recommendation quality depends on
consistent weather-region assignment even when DB-backed observations are sparse.

### 7. Preserve Ranking and RAG Rules

Nationwide place and culture expansion must not silently change score semantics.

What should stay the same:

- `culture_relevance_score` can expand nationwide as KCISA and KOPIS coverage
  expands
- `local_spending_score` must remain null where no approved card source exists
- score and RAG regeneration should run only after each approved ingest batch

Operational rule:

- run nationwide place and culture ingests first
- then rerun score batch
- then rerun RAG regeneration
- then validate API and web behavior

## Card-Spending Constraint

Card spending is the main source that cannot be made nationwide by code alone.

Current state from repo docs:

- approved source files are Gyeonggi-specific
- shared dev has real Gyeonggi card coverage
- non-Gyeonggi regions must not receive inferred spending rows

Therefore:

- nationwide rollout may proceed for places, weather-backed ranking, and culture
  signals
- `local_spending_score` remains intentionally partial until a new approved
  public-data source is onboarded
- documentation and API behavior should make this absence safe rather than hide
  it

## Suggested Execution Order

1. Add the shared nationwide region catalog.
2. Refactor TourAPI to support a province sweep runner.
3. Refactor KCISA to support a province sweep runner.
4. Refactor KOPIS to support a province sweep runner plus nationwide alias
   normalization.
5. Replace narrow region-normalization helpers with catalog-backed logic.
6. Rerun place score and RAG after each approved nationwide data batch.
7. Expand verification coverage and only then widen shared-dev apply scope.

## Verification Plan

Add or update tests for:

- nationwide region alias normalization
- TourAPI multi-area batching
- KCISA multi-sido batching
- KOPIS multi-signgucode batching
- weather fallback mapping across all provinces
- null-preserving score behavior when card-spending data is absent

Required verification surfaces:

- focused pytest for ingest and normalization services
- repo verification through `scripts/unix/verify_repo.sh`
- guarded preview runs before any apply
- post-apply checks for `ops.job_runs`, `ingest.source_files`, and row coverage
- browser and API smoke confirming nationwide manual-location behavior still
  aligns with backend outputs

## Out of Scope for the First Nationwide Pass

- changing DB schema names
- inventing nationwide card-spending coverage
- full production auth/networking redesign
- replacing the Flutter manual-location sheet, which is already nationwide-capable
- solving every English naming quality issue before nationwide ingest starts

## Definition of Done

Nationwide expansion for the first pass is done when:

- TourAPI, KCISA, and KOPIS can ingest by nationwide region partitions
- region normalization is catalog-backed rather than Gyeonggi-specific
- nationwide places and culture rows can flow through scoring and RAG safely
- regions without approved card-spending source remain null for local spending
- repo tests and guarded verification remain green

