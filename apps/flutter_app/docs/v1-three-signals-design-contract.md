# V1 Three-Signals Design Contract — combining S1/S2/S3 into the normal-path recommendation reason

> **Slice within V1 phase PR #133.** This is a foundation design contract on the canonical branch
> `geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133; head `613ec84`). It ships as a
> **doc-only foundation slice** — **no separate branch or PR is created for it.** Binding work is
> deferred to a later per-phase implementation lane (one branch + one Draft PR each, per the V1
> delivery policy). Retargeting PR #133's base is integrator-owned, not here.

**Canonical branch:** `geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133; head `613ec84`).
**Scope:** the **normal-path list/rail/search/dock recommendation `reason`** — the single line that
combines the three public-value signals for a user who has **not** opted into evidence. **NO new
external / AI / mock / snapshot / live-provider call.** **Status:** foundation doc — all design
decisions approved by the controller (§7); no product code in this slice.

This contract is a **claim about the real code at `613ec84`**. Every file path / line number below
was verified against the working tree this session. The controller and the independent verifier will
cross-check it.

> **Where this sits relative to RC3.** RC3 (`v1-rc3-design-contract.md`) is **already implemented**
> at this head — `publicWeatherSummary` exists (`weather_helpers.dart:44`), the dock weather line and
> the detail weather/source chips are bound. RC3 bound the **selected-place** (dock + detail) weather
> / PM / source. **This contract does NOT touch the selected surfaces.** It is concerned only with the
> **list / rail / search-tile / dock `reason` line** — the *unselected*, per-card recommendation
> reason — and how the three signals combine **there**, honestly, without exposing the internal score
> (playbook §4.1) and without raw/PII (§4.2).

> **Token source (same correction as RC2/RC3).** There is no `docs/STYLEGUIDE.md` / `main.css` in the
> LALA worktree. The canonical token SSOT is `apps/flutter_app/lib/app/lala_visual_tokens.dart` plus
> the existing in-code `Color(0xFF…)` literals. **This contract introduces no new color/size/shadow**
> — and in fact proposes **no Flutter presentation change at all** (§1a, D5): the reason already
> renders through the existing `PlaceReasonLine` SSOT widget.

---

## The three signals (playbook §1.1, op-plan V1 §2.2.3)

- **S1 — 공식 문화·관광 데이터** (official culture/tourism): 한국관광공사 TourAPI (`tour_api`),
  문화정보원 (`kcisa`), 공연예술통합전산망 (`kopis`). Carried on the normal payload as
  `upstream_source` (`db_repository.py:371`).
- **S2 — 집계형 로컬 신호** (aggregate local): domestic card-spend **aggregates** at region level
  — `region_spend_amount` / `region_transaction_count` — stored in the score snapshot's `features`
  jsonb. **No raw transactions, no PII** (§4.2).
- **S3 — 실시간 날씨·행사** (real-time weather + air-quality + events): DB-cached region weather
  (`fetch_latest_weather`) + linked events (`travel.place_events`).

---

## 0. Current state (audit, not guess) — normal-path vs evidence today

The three signals are combined **only** in the opt-in evidence panel today. The normal card reason
is shallow: it composes operating status + a binary weather-indoor flag + proximity + a generic
"공식 데이터" stamp. Audit:

| Claim | Verified at | Verdict |
|---|---|---|
| The normal `reason` is built by **one** function, `_derive_place_reason` | `places_service.py:170-216`; called at `:71` (DB path) and `:116` (snapshot fallback) | ✅ |
| Reason composes: operating status → binary weather-indoor flag → proximity → generic "공식 데이터" | `places_service.py:185-214` (`영업중` :190; `실내활동 적합` :197-202; `근접` :204-208; `공식 데이터` :210-214) | ✅ |
| `reason` is a plain server string; it flows to **all four** list/rail/search/dock surfaces unchanged | `reason` set at `places_service.py:78`; client `LalaPlace.reason` (`lala_api_client.dart:1055`, `:1097`); rendered by `PlaceReasonLine` (`place_reason_freshness.dart:12-63`) in rail (`map_rail_place_card.dart:160`), list (`recommended_place_card.dart:89`), search tile (`search_page.dart:873`) | ✅ |
| **S2 is honest-empty on the normal path.** `include_scores` defaults `False` (`places_service.py:26`, passed `:46`); `fetch_places` sets `score = … if include_scores else None` | `db_repository.py:372`; `_place_score_projection(False)` NULLs all components `:392-403` and `features` `:402`; `_place_score_from_row` returns `None` unless `final_score` `:406-407` | ✅ |
| **S2 in evidence only.** `local_spending_score` (component) + `region_spend_amount`/`region_transaction_count` (features) surface only when `include_scores=True` | client `LalaPlaceScoreComponents.localSpendingScore` (`lala_api_client.dart:1135,1144,1154`); `SignalGrid` bars (`signal_grid.dart:23,37-41`); detail facts `placeContextFacts` spend/txn **evidence-gated** (`home_view_helpers.dart:391-413`) | ✅ |
| **S1 normal = generic stamp.** Reason emits `"공식 데이터"` for any non-empty, non-`canonical` `upstream_source` | `places_service.py:210-214`; per-source label map (`tour_api`→한국관광공사 …) lives in `externalSourceLabel` (`home_view_helpers.dart:436-463`), **evidence-only** | ✅ |
| `upstream_source` IS already on the normal payload | `db_repository.py:371` (`row.get("source") or "canonical"`); client `LalaPlace.upstreamSource` (`lala_api_client.dart:1057,1087`) | ✅ |
| **S3 normal = one bit.** Reason uses only `outdoor_status=='bad'` → `실내활동 적합`, only for indoor-pref categories (`restaurant`,`culture_venue`) | `places_service.py:197-202`; `_INDOOR_PREFERRED_CATEGORIES` (`:16`); region weather fetched once via `fetch_latest_weather … or {}` (`:64`, no live provider — comment `:61-63`) | ✅ |
| **Events are `category='event'`-gated.** `event_start_date`/`event_end_date`/`event_url`/`is_ongoing` populate only when `category='event'` | `db_repository.py:252-271` (each `CASE WHEN ranked_places.category = 'event' AND linked_event.place_id IS NOT NULL`); exposed in place dict `:363-366` | ✅ |
| … yet the event data is **already joined for every place**: the `LATERAL` join fetches the latest event per `place_id` regardless of category | `db_repository.py:286-299` (`WHERE place_id = ranked_places.place_id`, no category filter) | ✅ — gating hides already-fetched rows |
| Detail "장소 연계 행사 N건" uses `place_event_count`/`culture_event_count` from `features` → **also null on normal path** | `home_view_helpers.dart:369-389`; features null when `include_scores=False` (`db_repository.py:402`) | ✅ |
| `fetch_latest_weather` returns temp + dust(pm10/pm25) + `outdoor_status` + `source='db'`, region-level, DB-cached only | `db_repository.py:497-605` (`outdoor_status` :576-588; `source:'db'` :604) | ✅ |

**Net:** on the normal card, S1 is a generic stamp, S2 is absent, S3 is one indoor-fit bit, and
linked events are invisible for non-event places. The combination the user sees is shallow; the real
combination lives behind the "점수/근거" toggle.

### Honest helpers / SSOT already in place — REUSE, do not reinvent

| Helper | File:line | Role (existing, unchanged by this contract) |
|---|---|---|
| `placeReasonText(place)` | `place_helpers.dart:192` | **SSOT** for the reason text on every surface (null/empty → null). The enriched reason rides this unchanged. |
| `PlaceReasonLine(place, …)` | `place_reason_freshness.dart:12` | **SSOT widget**: `Row>Expanded>Text(maxLines:1, ellipsis)` (:39-50). All four surfaces already use it. |
| `placeCardSemanticsLabel(place, lang)` | `place_helpers.dart:212` | joins name/category/distance/region/**reason** into one a11y label — enriching `reason` enriches a11y automatically. |
| `publicWeatherSummary(weather, lang)` | `weather_helpers.dart:44` | RC3 **selected-surface** weather SSOT (numbers: `outdoor · temp · dust` + source). **Not reused here** — list uses a *band*, not these numbers (D3). |
| `externalSourceLabel(value, lang)` | `home_view_helpers.dart:436` | per-source KO label map (`tour_api`→한국관광공사 …). Evidence-only today; **its map is the reference for the server-side S1 phrase** (D2). |
| `sourceLabel` / `weatherSourceLabel` | `source_label.dart:24` / `:46` | recommendation/weather source labels (selected surfaces). Not on the list reason. |

---

## 1. Data flow + single source of truth

The reason is **composed server-side, once**, and **no surface recomputes or rewords it**. Today the
composer reads only `place` + `current_weather` + `slot_time`. This contract widens the **inputs**
the composer is allowed to read (S1/S2/S3/D4) and the **phrases** it may emit — but the *shape* of
the flow (server string → `reason` field → one SSOT widget) is unchanged.

```
fetch_places (db_repository.py:184)                      ← [+contract] projects internal inputs
   SELECT …
     latest_scores.local_activity_band                   ← [+D1] min-sample-gated band (SQL expr over features)
     linked_event.* (LATERAL join, already all-category) ← [+D4] expose has_linked_event for all categories
   place dict { …, upstream_source, event_*, _local_activity_band, _has_linked_event }
        │
list_places (places_service.py:19)                       ← current_weather already fetched once (:64)
   for place: _derive_place_reason(place, current_weather, slot_time)   ← [+contract] single composer
        inputs: upstream_source (S1), _local_activity_band (S2), current_weather (S3),
                _has_linked_event (D4), category, distance_m
        output: ONE ' · '-joined KO string, canonical segment order (§3)
   strip internal keys (_local_activity_band, _has_linked_event)        ← [+contract] never serialized
   enriched_place["reason"] = reason
        │  (API /places → success_envelope, v1.py:85-109; reason is a plain string)
LalaPlace.reason (lala_api_client.dart:1097)
        │
placeReasonText (place_helpers.dart:192) ── SSOT ──→ PlaceReasonLine (place_reason_freshness.dart:12)
        ├── MapRailPlaceCard        (map_rail_place_card.dart:160)   148×114 photo-centric
        ├── RecommendedPlaceCard    (recommended_place_card.dart:89) ~270dp list card
        ├── _SearchPlaceTile        (search_page.dart:873)           search list
        └── MapBottomDock           (reason line)                    selected dock (unchanged by RC3)
```

**Single source of truth for the reason text:** `_derive_place_reason` (`places_service.py:170`) —
the **only** place any normal-path reason segment is assembled. The four new phrase helpers (§4) are
its private collaborators. **No client recomputes, rewords, or selects reason segments** — the
client only renders `place.reason`. This is the invariant that lets one server change enrich all four
surfaces identically.

### 1a. Normal-path vs evidence — the separation this contract enforces

| Signal | Normal path (`include_scores=False`, this contract) | Evidence path (`include_scores=True` / `showEvidence=true`, unchanged) |
|---|---|---|
| **S1 source** | **[+contract]** specific KO phrase in `reason` (한국관광공사 데이터 …) via server composer | `externalSourceLabel` provenance in `PublicDataProofRow` (`home_view_helpers.dart:436`) |
| **S2 activity** | **[+contract]** coarse binary phrase in `reason` (로컬 소비 활발); **NO number** | `local_spending_score` bar (`signal_grid.dart:37`) + spend/txn facts (`home_view_helpers.dart:391-413`) |
| **S3 weather** | **[+contract]** coarse band in `reason` (선선한 날씨 / 실내활동 적합); **NO per-card number** | `publicWeatherSummary` precise chip on **selected** surface (RC3, dock+detail) |
| **D4 event** | **[+contract]** phrase in `reason` (진행 중인 행사) for any category | `place_event_count` fact (`home_view_helpers.dart:371`) + event fields |
| Internal score (number/formula/components) | **hidden** (playbook §4.1) | shown (`SignalGrid`, `PublicDataProofRow`) |

**Invariant (playbook §4.1/§4.2):** the normal `reason` carries **phrases only** — never the score
number, never the formula, never a component value, never raw transactions. Toggling evidence **adds**
the numeric/proof depth; it never removes the normal-path phrases. Aggregates are surfaced only as a
min-sample-gated binary hint (§4.2).

---

## 2. ASCII wireframes (normal path)

Legend: `[+]` = a segment newly composed by this contract. Existing segments shown unmarked. The
reason line is **one** `PlaceReasonLine` (1-line ellipsis) on every surface — only its contents grow.

### 2a. Rail card — `MapRailPlaceCard` (148×114, photo-centric — `map_rail_place_card.dart:62-63`)
```
┌──────────────────────────────┐
│ ●(cat dot)        [ photo ]  │
│                              │
│  경복궁                       │  name (white, 12px, w800)
│  문화 · 종로 · 도보 300m      │  category · region · distance (1 line ellipsis)
│  영업중 · 선선한 날씨 · 근접  │  reason line — [+] S3 band woven in; tail ellipsizes
│  5분 전                       │  freshness (honest-omit if null)
└──────────────────────────────┘
   reason null/empty → the line is omitted entirely (PlaceReasonLine → SizedBox.shrink).
   On a 148dp card only ~2–3 short segments fit; canonical order (§3) keeps the head decision-useful.
```

### 2b. List card — `RecommendedPlaceCard` (~270dp — `recommended_place_card.dart`)
```
┌────────────────────────────────────────────────────┐
│ [CategoryBadge] 300m 5분 전            [ thumb ]   │
│                                                    │
│ 경복궁                                              │  name (2 lines)
│ 종로구 사직로                       [ image ]       │  subtitle (2 lines)
│ 영업중 · 선선한 날씨 · 로컬 소비 활발 · 진행 중인 행사 · 한국관광공사 데이터 │  reason (1 line ellipsis)
└────────────────────────────────────────────────────┘
   Roomier than the rail → more of the tail survives before ellipsis; still one line.
```

> The search tile (`_SearchPlaceTile`, `search_page.dart:775`) and the dock reason line share the
> **same** `place.reason` string and the same `PlaceReasonLine` widget — they are not redrawn here.

---

## 3. Binding matrix — signal → reason segment, per honest state

The reason string is `' · '.join(segments)` in a **fixed canonical order** (head = most
decision-useful; tail = first to ellipsize on narrow surfaces):

```
[operating] · [weather(S3)] · [activity(S2)] · [event(D4)] · [proximity] · [source(S1)]
```

| Segment | Composer helper (§4) | PRESENT → rendered (KO) | NULL / below-gate → | Data-truth state |
|---|---|---|---|---|
| operating | (existing, `:185-195`) | `영업중` | omit (closed/unknown) | real-data-bound |
| **weather (S3)** | `_weather_band_phrase` (D3) | `선선한 날씨` / `더운 날씨` … (band); indoor-pref ∧ bad → `실내활동 적합` (existing bit retained) | omit (no cached weather) | **BLOCKED_EXTERNAL** — depends on `travel.latest_weather` ingest; list path is DB-cached only, **no live provider trigger** (`places_service.py:61-63`) |
| **activity (S2)** | `_local_activity_reason_phrase` (D1) | `로컬 소비 활발` (single binary phrase; **no number**) | omit (below min-sample / no features) | **BLOCKED_EXTERNAL** — depends on `analytics.place_score_snapshots.features` being populated at scale by the scoring pipeline |
| **event (D4)** | `_linked_event_reason_phrase` (D4) | `진행 중인 행사` (ongoing) / `행사 연계` (linked) | omit (no linked event) | **BLOCKED_EXTERNAL** — depends on `travel.place_events` ingest coverage for non-event `place_id`s |
| proximity | (existing, `:204-208`) | `근접` (≤500m) | omit (>500m) | real-data-bound |
| **source (S1)** | `_upstream_source_reason_phrase` (D2) | `한국관광공사 데이터` / `문화정보원 데이터` / `공연예숤통합전산망 데이터` | omit (canonical / empty / unknown) | real-data-bound (code already on payload) |

**Honest-state rules (never fabricate — playbook §4.1/§4.2):**
- Every segment is independently null-gated; the composer appends only non-empty phrases. An
  all-null place yields `""` (honest empty — `placeReasonText` → null → `PlaceReasonLine` renders
  nothing). Never "이유 없음", never a fabricated number/grade/source.
- **S2 number/formula never appears.** The activity phrase is a single binary hint derived from the
  `features` **aggregate** (`region_transaction_count`), min-sample gated — not from `final_score`
  or any component score. Acceptance: the phrase is unreachable from the score number.
- **S3 list ≠ S3 selected.** The list band is a coarse phrase; the selected surface (RC3) shows the
  precise `publicWeatherSummary` numbers. They are different granularities of the same region weather
  and never co-render, so they cannot diverge (see D3).
- **BLOCKED_EXTERNAL rows:** the *code* (SQL projection / composer) is necessary but **not
  sufficient**. At runtime the band/phrase is NULL across the board until the relevant ingest
  populates the table — that is an operational gate, **not** a code bug and **not** something this
  contract can verify at runtime/device.

---

## 4. Shared SSOT — new server-side composition helpers (signatures only, no implementation)

All helpers are **private** to `apps/api/app/services/places_service.py` and are called only by
`_derive_place_reason`. They take the already-available inputs (no new fetch, no external call).

```python
# D2 — S1 per-source provenance phrase. Mirrors the KO branch of externalSourceLabel
# (home_view_helpers.dart:436-463). canonical/empty/unknown → None (honest omit, no generic stamp).
def _upstream_source_reason_phrase(upstream_source: str) -> str | None: ...

# D1 — S2 aggregate-activity phrase. Binary: above min-sample gate → '로컬 소비 활발', else None.
# Derives ONLY from the features aggregate (region_transaction_count), NEVER from final_score /
# component scores. band is the SQL-projected min-sample flag (§Lane 1), not a number.
def _local_activity_reason_phrase(local_activity_band: str | None) -> str | None: ...

# D3 — S3 coarse weather band for the LIST reason. Distinct granularity from publicWeatherSummary
# (band, not numbers). indoor-pref category ∧ outdoor_status=='bad' → '실내활동 적합' (existing bit
# retained as a special band); else a single comfort phrase from temp/outdoor_status. No cached
# weather → None.
def _weather_band_phrase(current_weather: dict, *, category: str) -> str | None: ...

# D4 — linked/ongoing event phrase for ANY category. has_linked_event (SQL-projected from the
# already-joined LATERAL) → '진행 중인 행사' / '행사 연계'; else None.
def _linked_event_reason_phrase(has_linked_event: bool | None, *, is_ongoing: bool | None) -> str | None: ...
```

**Canonical band spec (proposed values — controller may tune; the SHAPE is locked: band, not number):**

- **S2 min-sample gate (D1):** `region_transaction_count >= MIN_SAMPLE` (proposed `MIN_SAMPLE = 50`,
  controller-tunable). Meets → `'로컬 소비 활발'`. The gate runs **in SQL** so the raw aggregate
  never leaves the DB layer (only the boolean band ships internally).
- **S3 weather band (D3):** from `current_weather['outdoor_status']` + parsed `temp`:
  - `outdoor_status == 'bad'` ∧ category ∈ {restaurant, culture_venue} → `'실내활동 적합'` (unchanged);
  - `outdoor_status == 'bad'` ∧ other category → omit (a bare "bad weather" stamp on an outdoor
    attraction is not a useful recommendation; honest silence);
  - else (good) → temp comfort band: `temp < 5`→`추운 날씨`, `5..18`→`선선한 날씨`,
    `18..27`→`따뜻한 날씨`, `>= 27`→`더운 날씨` (proposed thresholds); temp unparseable → omit.

> The list band and RC3's `publicWeatherSummary` are **anchored to the same underlying fields**
> (`outdoor_status`, `temp`, dust) but render **different granularities** (coarse phrase vs exact
> `outdoor · temp°C · PM10 N 보통`). Because they never share a surface and never share a
> representation, there is no text to diverge. The band *definition* lives here (§4); the precise
> *text* lives in `publicWeatherSummary` (Dart). Both are SSOTs for their own surface.

---

## 5. Accessibility (a11y)

- The reason rides the existing `Text` node inside `PlaceReasonLine` → already in the a11y tree.
- `placeCardSemanticsLabel` (`place_helpers.dart:212-223`) already joins `reason` into the merged
  card label, so the enriched reason is announced on rail/list/search **with no extra wiring**.
- The reason line is non-interactive → **no new touch target** (44dp-min does not apply).
- **KO-only** copy on the normal path; no emoji / ✨ / AI decoration; no KO+EN mix (the server emits
  one language per request via the existing `language` param).

---

## 6. Responsive — no overflow at narrow viewport (follow #124 / RC2 §6 / RC3 §6)

- The reason line is `Row>Expanded>Text(maxLines:1, overflow:ellipsis)` by construction
  (`place_reason_freshness.dart:39-50`) — **the same shape already proven at 360/393dp** with a
  deliberately long reason fixture (`narrow_viewport_no_overflow_test.dart:159,181,200,432`).
- Enriching the reason only makes the string **longer**; ellipsis truncates the tail. **No new
  widget, no Wrap, no second row** (D5) → no new overflow vector.
- **Verification gate (future lane):** extend `narrow_viewport_no_overflow_test.dart` with a fixture
  whose `reason` mirrors the real enriched multi-segment string (all six segments present) at
  360/393dp on `MapRailPlaceCard` + `RecommendedPlaceCard`; assert `tester.takeException()` is null.

---

## 7. Decisions D1–D5 — approved by controller (locked)

All five decisions are **approved**; the recommended option is locked in. Rejected alternatives are
retained for the record.

- **D1 — APPROVED: lift S2 as a server-composed reason phrase only (option b); ship NO new field.**
  The composer appends `'로컬 소비 활발'` when a min-sample-gated band (SQL-projected from the
  `features` aggregate) is set; the **number/formula never appears** and **no new API/OpenAPI/client
  field is introduced** (the phrase folds into the existing `reason` string). DB impact: one derived
  SQL column `local_activity_band` in `_place_score_projection` (`db_repository.py:378`), computed for
  **both** `include_scores` true/false, **additive & re-runnable — NO migration, NO apply** (it is a
  SQL expression over the existing `features` jsonb, not a stored column). The band is an **internal**
  key (`_local_activity_band`), consumed by the composer and **stripped before serialization**. OpenAPI
  impact: **none** (no schema field added). Flutter-client impact: **none** (`LalaPlace.reason` already
  exists; `lala_api_client.dart` unchanged). *(Rejected, option a: a new structured `local_activity`
  public projection {band, sample-count, freshness} → more API/client surface, divergence risk, and a
  band+count edges toward leaking the internal ranking — violates the spirit of §4.1.)*

- **D2 — APPROVED: per-source provenance phrase server-side from `upstream_source`.** Replace the
  generic `'공식 데이터'` stamp (`places_service.py:210-214`) with a specific KO phrase
  (`한국관광공사 데이터` / `문화정보원 데이터` / `공연예술통합전산망 데이터`) via
  `_upstream_source_reason_phrase`, mirroring the KO branch of `externalSourceLabel`
  (`home_view_helpers.dart:453-462`). `canonical`/empty/unknown → **omit** (honest; a generic stamp
  without a real source is less honest than silence). *(Rejected: keep the generic stamp — strictly
  less honest. Rejected: compose per-source on the client — would split reason phrasing across
  server/client and break the single-composer SSOT.)* Known accepted cost: the ~4-entry source→label
  map now exists in both Python (reason) and Dart (evidence); a consistency test must assert they
  agree (§8).

- **D3 — APPROVED: coarse weather band in the reason, composed server-side, distinct granularity
  from RC3.** `_weather_band_phrase` emits one short phrase (or the retained `실내활동 적합` bit);
  list-level weather text is composed **only** in `_derive_place_reason` (`places_service.py`). It is
  a **band**, never the `publicWeatherSummary` numbers, so it cannot diverge from RC3's
  selected-surface line (different surface, different granularity — §4). Honest-omit when no cached
  weather. *(Rejected: reuse `publicWeatherSummary` text per list card — would show precise per-card
  numbers that are only region-true, risk divergence, and crowd the tight rail line.)*

- **D4 — APPROVED: surface a linked/ongoing event for any category via a composer-only internal
  projection, NOT by widening the shared event fields.** Add one internal column
  `has_linked_event` (from the **already-joined** `LATERAL linked_event`, `db_repository.py:286-299`)
  projected for **all** categories; the composer emits `진행 중인 행사` / `행사 연계`. Honest-omit
  when no linked event. The **existing** `event_start_date`/`event_url`/`is_ongoing` fields
  (`db_repository.py:252-271`) **stay `category='event'`-gated** → **zero Flutter blast radius**
  (detail/evidence consumers unchanged). *(Rejected: widen the existing `CASE WHEN … category =
  'event'` guards — blast radius into every Flutter consumer of `event_start_date`/`is_ongoing`;
  rejected to keep the change scoped to the list reason.)* Runtime effect is gated on
  `travel.place_events` ingest coverage for non-event `place_id`s (BLOCKED_EXTERNAL).

- **D5 — APPROVED: render the combination as the SINGLE existing reason line — no signals strip.**
  All three signals (+ D4) fold into the one `' · '`-joined, 1-line-ellipsized `PlaceReasonLine`
  already shared by rail/list/search/dock. Stays photo-centric (rail is 148×114), KO-only,
  decoration-free, score-hidden, and within the existing overflow gate (§6). *(Rejected: a compact
  signals strip / second chip row — eats the photo, adds a Wrap/height overflow vector on the tight
  rail card, duplicates the evidence panel's role, and breaks the photo-centric contract. The
  selected detail (RC3) already owns the rich chips; the list/rail stays one honest line.)*

---

## 8. Acceptance matrix (what must be true to PASS)

Honesty:
- [ ] The normal `reason` contains **phrases only** — grep-assert no score number, no `final_score`,
      no component name, no raw transaction count appears in any `reason` string.
- [ ] S2 phrase is **unreachable** from `final_score`/component scores — it derives only from the
      `features` aggregate via the SQL band.
- [ ] Each segment is independently null-gated; an all-null place → `reason == ""` (rendered as
      nothing). No "이유 없음", no fabricated source/weather/event.
- [ ] `canonical`/empty/unknown `upstream_source` → **no** source segment (no generic stamp).
- [ ] No cached weather → **no** weather segment; indoor-fit bit retained only for indoor-pref ∧ bad.

Score-stays-opt-in (playbook §4.1 — must not regress):
- [ ] `include_scores=False` (the default) → `score` still `None` (`db_repository.py:372`);
      `SignalGrid` + `PublicDataProofRow` still hidden on the normal path.
- [ ] `include_scores=True` → numeric/proof depth still rendered; normal-path phrases still present.

No raw / PII (§4.2):
- [ ] No raw transaction rows, no merchant/PII; only the min-sample-gated binary band leaves the DB.

Single SSOT:
- [ ] `_derive_place_reason` is the **only** normal-path reason composer (grep: reason text assembled
      only there; no client recomputes/rewords segments).
- [ ] S1 source→label map agrees between server (`_upstream_source_reason_phrase`) and client
      (`externalSourceLabel`) — consistency test over {tour_api, kcisa, kopis, canonical, ''}.
- [ ] List weather band ≠ RC3 `publicWeatherSummary` text (band vs numbers; never same surface).

Payload surface:
- [ ] Serialized `/places` response has **no** `_local_activity_band` / `_has_linked_event` key
      (internal inputs stripped). **No new top-level field.** OpenAPI unchanged. `LalaPlace` model
      unchanged.

Presentation:
- [ ] KO-only; no emoji/AI decoration; no KO+EN mix per request.
- [ ] Rail/list/search/dock all render the **same** `reason` via `PlaceReasonLine` (no per-surface
      rewording).
- [ ] `MapRailPlaceCard` + `RecommendedPlaceCard` with a full six-segment reason at 360/393dp →
      `tester.takeException()` null (extended `narrow_viewport_no_overflow_test.dart`).

Tests (future lane — only after approval):
- [ ] `places_service` unit tests: each helper present/absent; canonical→omit; min-sample boundary;
      no-weather→omit; reason is the `' · '`-join in canonical order; internal keys stripped from the
      serialized payload.
- [ ] Keep green with **zero assertion changes**: existing reason/freshness tests
      (`v1_rc2_reason_freshness_test.dart`, `search_page_states_test.dart`,
      `narrow_viewport_no_overflow_test.dart`) — the existing `reason` fixtures stay valid; new
      segments are additive and null-gated.
- [ ] Reason is a static server string over already-fetched inputs → **no frozen wall-clock / no
      live call** needed in API tests.

---

## 9. Out of scope (frozen / explicit non-goals)

- The **selected** surfaces (dock weather line, detail `PlaceContextCard` chips, `SignalGrid`,
  `PublicDataProofRow`) — owned by RC3 (implemented). This contract changes **only** the list/rail/
  search/dock `reason` line.
- Exposing the score **number/formula/components** on the normal path (playbook §4.1 — permanently
  opt-in). S2 is a binary phrase, never the number.
- Any new client model field, OpenAPI field, or API endpoint (D1 option b deliberately avoids all
  three). Any DB **migration** (the band is a derived SQL expression; additive/re-runnable, no apply).
- Any new fetch / external / AI / mock / snapshot / **live weather-provider** call. The list path
  stays DB-cached (`places_service.py:61-63`).
- Widening the shared `event_*` fields (D4 rejected alternative) and any consequent Flutter
  detail/evidence change.
- At-scale **ingest population** of `place_score_snapshots.features`, `travel.latest_weather`, and
  `travel.place_events` — these are **operational gates** (BLOCKED_EXTERNAL), not code in this
  contract. The contract does not promise runtime/device verification of populated data.
- Mutation of `613ec84`, PR #133, `main`, `integration/lala-vision-v3`, or any closed branch.
- main merge, deploy, production DB write/migration-apply, crawl, DNS/auth mutation, paid AI/Speech,
  live provider call, secret output.

---

## 10. Implementation plan (future per-phase lanes — NOT this foundation slice)

This foundation slice ships the contract **doc only** — one commit on the canonical branch
(`geondongkim/lala-v1-rc2-rail-reason-freshness`, PR #133), approved as contract-only. The binding
work happens in **later per-phase implementation lanes** (each its own branch + Draft PR per the V1
delivery policy), with **disjoint file ownership** and a common base of `613ec84`. Lanes are ordered
by data contract; Lane 2 is blocked-by Lane 1, Lane 3 is blocked-by Lane 2.

| Lane | Exclusive files | Changes | Data-integrity dependency? |
|---|---|---|---|
| **Lane 1 — DB projection + event join** | `apps/api/app/services/db_repository.py` ONLY | (a) `_place_score_projection` (`:378`): add derived `local_activity_band` SQL expr (min-sample gate over `features`), computed for **both** `include_scores` true/false; surface in final SELECT (`:274-283`) and place dict (`:350-373`) as internal `_local_activity_band`. (b) Add internal `has_linked_event` (from the existing `LATERAL`, `:286-299`) for **all** categories — do **not** widen the `:252-271` `event_*` CASE WHEN. | **YES** — reads `analytics.place_score_snapshots.features` + `travel.place_events`; both must exist (table checks at `:43-46`). Additive SQL only — **no migration**. |
| **Lane 2 — reason composer** | `apps/api/app/services/places_service.py` ONLY | (a) Add the four helpers (§4). (b) Rewrite `_derive_place_reason` (`:170`) to compose all segments in canonical order (§3) from `upstream_source`, `_local_activity_band`, `current_weather`, `_has_linked_event`, `category`, `distance_m`. (c) In `list_places`, **strip** `_local_activity_band`/`_has_linked_event` from the serialized place dict (both DB path `:68-80` and snapshot path `:112-125`). | **YES** — consumes Lane 1's internal keys; **blocked-by Lane 1** (key contract). Honesty invariants (§8) enforced here. |
| **Lane 3 — Flutter overflow gate (test-only)** | `apps/flutter_app/test/features/map/narrow_viewport_no_overflow_test.dart` ONLY | Extend the reason fixture to the real enriched six-segment string on `MapRailPlaceCard` + `RecommendedPlaceCard` at 360/393dp; assert no overflow. | **NO** — pure presentation test; **blocked-by Lane 2** (needs final reason shape). **No Flutter product code** changes (`PlaceReasonLine`/`LalaPlace` untouched). |

**Non-lane (explicit):** there is **no Flutter product-code lane** and **no client-model/OpenAPI
lane** — D1 option b and D5 (single existing reason line) make both unnecessary. `LalaPlace`
(`clients/flutter/lib/lala_api_client.dart`) is unchanged.

Each lane: incremental commits (one coherent sub-step each); push every 1–3 commits; **never push
red**; keep RC1/RC2/RC3 tests green with **zero** assertion changes. Each lane reports its own head
SHA, commands run, focused + full test results, CI run id, and what is NOT yet verified.
**Report = CLAIM** — cross-checked against actual diff/tests/CI. No self-declared runtime/device PASS;
BLOCKED_EXTERNAL ingest gates are reported as operational status, not verified by code.
