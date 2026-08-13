# V1-RC3 Design Contract — selected-place weather/PM + official source on the normal path

> **Slice within V1 phase PR #133.** This is a foundation design contract on the canonical branch
> `geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133). It ships as a **doc-only foundation
> slice** — **no separate branch or PR is created for it.** Binding work is deferred to a later
> per-phase implementation lane (one branch + one Draft PR each, per the V1 delivery policy).
> Retargeting PR #133's base to `integration/lala-vision-v3` is owned by the integrator, not here.

**Canonical branch:** `geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133; head `23e7b50`).
**Scope:** Flutter-side binding only. Deterministic. **NO new external / AI / mock / snapshot call.**
**NO API change** (0 files under `apps/api/`). **Status:** foundation doc — all design decisions
approved by the controller (§7); no product code in this slice.

This contract is a **claim about the real code at `23e7b50`**. Every file path / line number
below was verified against the working tree this session. The controller and the independent
verifier will cross-check it.

> **Token source (corrects the mission wording).** There is **no** `docs/STYLEGUIDE.md` and **no**
> `main.css` anywhere in the LALA worktree (verified: `find … -iname STYLEGUIDE*` / `-name main.css`
> → empty). Those are Orca-renderer artifacts referenced by the repo-root `CLAUDE.md`; they do not
> apply to the Flutter app. The canonical token SSOT here is
> `apps/flutter_app/lib/app/lala_visual_tokens.dart` (`LalaVisualColors`, `LalaVisualTokens`) plus
> the existing in-code `Color(0xFF…)` literals already used pervasively. This is exactly the
> precedent RC2 followed. **No new colors / sizes / shadows are introduced** — every value below
> maps to an existing token or literal.

---

## 0. Current state (audit, not guess) — and one correction to the mission premises

The mission's controller-verified premises are accurate on the **dock** and on the **proof row**,
but slightly off on the **detail weather**. The audit correction matters because it shrinks RC3's
detail work from "add weather" to "extend weather + add source".

| Claim | Verified at | Verdict |
|---|---|---|
| Dock shows official source via `sourceLabel(source)` + RC2 reason/freshness; **no weather/PM** | `map_bottom_dock.dart:159-176` (`sourceLabel` TinyMeta at `:165`; `PlaceReasonLine` at `:176`) | ✅ accurate |
| `currentWeather` is computed and in scope in dashboard but NOT passed into `MapBottomDock` | `dashboard.dart:211` (`publicWeatherOrNull(weather?.data)`); dock ctor `:438-477` has no `weather` param | ✅ accurate — pure plumbing |
| Detail `PublicDataProofRow` (source/weather/score proof) only when `showEvidence=true` | `featured_place_panel.dart:145-154` (`if (showEvidence)`) | ✅ accurate |
| **Detail weather via `PlaceContextCard` only when `showEvidence=true`** | `home_view_helpers.dart:405-410` | ❌ **INACCURATE** — see below |

**Correction (the detail weather fact is already on the normal path).** In `placeContextFacts`
(`home_view_helpers.dart`), the weather fact is added **unconditionally**, *not* inside the
`if (includeEvidence)` guard:

```dart
// home_view_helpers.dart:405-410  — NOT gated by includeEvidence
if (weather != null) {
  final outdoor = outdoorLabel(weather.outdoorStatus, language: language);
  final temp = temperatureLabelOrNull(weather.temp);
  add(Icons.wb_cloudy_outlined, temp == null ? outdoor : '$outdoor · $temp');
}
```

The `includeEvidence` gates in that function are: spend (`:382`), transactions (`:394`), and the
**provenance** source `externalSourceLabel(...) ?? sourceLabel(place.source)` (`:412-421`). So on
the **normal path** the detail panel **already shows** `outdoor · temp` (e.g. "보통 · 23°C"), and
shows **no source label at all** (neither recommendation source nor weather source).

**Consequence for RC3 scope:**
- **Dock:** add weather/PM summary + weather source (today: none). Thread `currentWeather`.
- **Detail:** the temp/outdoor chip is already there → RC3 **extends** it (add dust) and **adds**
  the weather-source chip + the recommendation-source chip on the normal path. It does **not**
  introduce weather rendering from scratch (avoids duplicating temp).

Both surfaces today lack: **dust/PM**, the **weather source** (`weatherSourceLabel`), and (on the
detail normal path) the **recommendation source** (`sourceLabel`). Those three are the RC3 bind.

### Honest helpers already exist and are correct — REUSE, do not reinvent

| Helper | File:line | Role |
|---|---|---|
| `publicWeatherOrNull(LalaWeather?)` | `weather_helpers.dart:12` | placeholder/skeleton/fallback → `null` (the honest gate; already applied at `dashboard.dart:211`) |
| `temperatureLabelOrNull(String)` | `weather_helpers.dart:22` | `23` → `23°C`; empty/`-` → `null` |
| `sourceLabel(String?, {language})` | `source_label.dart:24` | `db`→실시간 추천, `mixed`→실시간·공식 데이터, `skeleton`→로컬 큐레이션, fallback→제한적 오프라인 데이터 |
| `weatherSourceLabel(String?, {language})` | `source_label.dart:46` | `kma_ultra_srt_ncst`→기상청 실황, `airkorea_sido_realtime`→AirKorea 대기질, combos, placeholder→날씨 준비 중 |
| `weatherPillDustLabel(LalaDust, lang)` | `dust_label.dart:75` | `PM10 30 보통 · PM2.5 25 좋음`, else falls back to situation grade |
| `dustSituationLabel(LalaDust, lang, {includePrefix})` | `dust_label.dart:92` | KO `미세 30 보통 · 초미세 25 좋음` / `미세먼지 보통` |
| `outdoorLabel(String, {language})` | `place_labels.dart:96` | outdoor activity status: 좋음/보통/주의 |
| `proofSourceLabels(...)` / `PublicDataProofRow` | `home_view_helpers.dart:32` / `public_data_proof_row.dart` | the **deep** proof block (stays gated) |

### Model shape (verified, `clients/flutter/lib/lala_api_client.dart`)

- `LalaWeather` (`:1167`): `temp` (`:19`, **String**), `dust` (`:21`, `LalaDust`), `outdoorStatus`
  (`:23`, String), `source` (`:25`, **String** — non-nullable; placeholder sources are caught by
  `publicWeatherOrNull` upstream).
- `LalaDust` (`:1220`): `pm10`/`pm25` (`:1232-1233`), `grade`/`gradeKo` (`:1234-1235`),
  `pm10Grade`/`pm10GradeKo`/`pm25Grade`/`pm25GradeKo` (`:1236-1239`).

---

## 1. Data flow + single source of truth

`currentWeather` is computed **once** in `Dashboard.build` and already travels to the detail sheet;
RC3 only forks it into the dock too. **No new fetch, no new external call** (mission hard invariant).

```
dashboard.dart:211  currentWeather = publicWeatherOrNull(weather?.data)   ← SSOT gate (already exists)
   │  (placeholder/skeleton/fallback weather is null HERE → honest omission downstream)
   ├── MapBottomDock(...)            (dashboard.dart:438)   ← [+RC3] add optional `weather: currentWeather`
   │     └── TinyMeta Wrap + PlaceReasonLine  →  [+RC3] PlaceWeatherSourceLine(weather)
   └── MapDraggableSheet(weather: currentWeather)  (dashboard.dart:524)
         └── FeaturedPlacePanel(weather:, source:)   (map_draggable_sheet.dart:158, weather:161, source:169)
               └── PlaceContextCard(weather:, [+RC3] source:)   (featured_place_panel.dart:87)
                     └── placeContextFacts(weather:, source:, includeEvidence:)  (home_view_helpers.dart:336)
                          ├── region / events / spend* / transactions*        (* = evidence-gated, unchanged)
                          ├── weather fact: outdoor · temp · [+RC3 dust]       (unconditional)
                          ├── [+RC3] weather-source fact: weatherSourceLabel   (unconditional)
                          └── [+RC3] recommendation-source fact: sourceLabel   (unconditional)
                          (provenance externalSourceLabel fact stays evidence-gated at :412)
```

**Single source of truth for the rendered text (both surfaces):** a **new composition helper**
`publicWeatherSummary` (§4) — the only place weather chip text is assembled. `sourceLabel` /
`weatherSourceLabel` remain the SSOT for the two source labels. **No surface recomputes or rewords**
temp/dust/source.

### 1a. Normal-path vs evidence — the separation RC3 enforces

| Concept | Helper | Normal path (`showEvidence=false`) | Evidence path (`showEvidence=true`) |
|---|---|---|---|
| Recommendation source | `sourceLabel(source)` | **[+RC3] shown** (dock already; detail newly) | shown (unchanged) |
| Weather summary (temp·dust) | `publicWeatherSummary` | **[+RC3] shown** | shown (unchanged text) |
| Weather source | `weatherSourceLabel` | **[+RC3] shown** | shown |
| Internal score components | `SignalGrid` | hidden | shown (`featured_place_panel.dart:116`) |
| Deep proof (provenance, basis, input_sources, RAG) | `PublicDataProofRow` / `proofSourceLabels` | hidden | shown (`featured_place_panel.dart:145`) |

**Invariant:** toggling "점수/근거" **adds** the deep proof/score; it never removes the normal-path
source/weather truth. Source/weather truth is **never** gated by `showEvidence`.

---

## 2. ASCII wireframes (normal path, `showEvidence=false`)

Legend: `[+]` = newly bound by RC3. `[W]` = weather line. `[WS]` = weather source.
`[RS]` = recommendation source. Existing chips shown unmarked.

### 2a. Selected — pinned dock — `MapBottomDock` (LIVE; mobile ~196dp, wide ~218dp)
Weather added as a **single compact line** (not more chips) to respect the dock's tight height —
see D-Dock. Honest-omitted (whole line) when `publicWeatherOrNull(weather) == null`.
```
┌────────────────────────────────────────────┐
│ ───(handle)───                  [상세 ↑]    │
│ [CategoryBadge]  경복궁          [점수/근거] │
│ [수원][300m][실시간 추천][5분 전][데이터 기준:…] │ ← TinyMeta Wrap (RC2, unchanged)
│ [R] 영업중 · 근접                           │ ← RC2 reason (PlaceReasonLine)
│ [W] 23°C · PM10 30 보통 · 기상청 실황       │ ← [+RC3] weather summary · weather source (1 line, ellipsis)
│ ┌── docent preview ──────────────────────┐ │
└────────────────────────────────────────────┘
   weather null/fallback → the [W] line is omitted entirely (honest).
```

### 2b. Selected — detail — `PlaceContextCard` inside `FeaturedPlacePanel` (LIVE, roomy scrollable sheet)
RC3 **extends** the existing weather chip and **adds** two chips. The card's `Wrap` of
`ContextFactChip` lays them out; the sheet scrolls, so width/height are not constrained.
```
┌────────────────────────────────────────────┐
│ ▣ 로컬 맥락                                 │
│ [📍 수원] [📅 장소 연계 행사 2건*]          │  (* evidence-gated spend/txn omitted on normal path)
│ [☁ 보통 · 23°C · PM10 30 보통]            │  ← weather fact: outdoor · temp · [+RC3 dust]
│ [🌤 기상청 실황]                           │  ← [+RC3] weather source (weatherSourceLabel)
│ [✪ 실시간 추천]                            │  ← [+RC3] recommendation source (sourceLabel)
└────────────────────────────────────────────┘
   weather null → weather chip + weather-source chip both omitted; recommendation-source chip
   still shown when source resolves to a real label (≠ '-').
```
Below this card (unchanged): the "점수/근거 보기" toggle, then **only when toggled on** the
`SignalGrid` + `PublicDataProofRow` deep proof (`featured_place_panel.dart:116-154`).

---

## 3. Binding matrix — helper → rendered chip, per surface × per honest state

`S = publicWeatherSummary(weather, lang)` → record `({String? summary, String? source})`
(§4). `summary` joins non-empty `[outdoor, temp, dust]`; `source = weatherSourceLabel(...)`.
Both are `null` when `publicWeatherOrNull(weather) == null`. `source` is **paired** to `summary`
(we render the weather-source only alongside a non-empty weather summary — attribution without a
value it attributes-to would mislead).

| Surface | Element | Source | weather present | weather null/fallback | source empty (`'-'`) |
|---|---|---|---|---|---|
| **Dock** | `[W]` line | `S.summary` + ` · ` + `S.source` | render line | omit line | n/a (line pairs them) |
| **Dock** | rec-source chip | `sourceLabel(source)` | already shown (`:165`) | already shown | today shows `-`; see D-Src |
| **Detail** | weather fact | `S.summary` (outdoor·temp·dust) | render chip | omit chip | n/a |
| **Detail** | weather-source chip | `S.source` | render chip | omit chip | n/a |
| **Detail** | rec-source chip | `sourceLabel(source)` | render chip | render chip | omit chip (≠ `-`) |

Honest states (mission invariant — never fabricate):
- **weather present (real source):** temp + dust + weather source, all from real helpers.
- **weather null / fallback / skeleton / placeholder:** filtered to `null` by
  `publicWeatherOrNull` at `dashboard.dart:211` → **honest omission** on both surfaces (no chip /
  no line). "날씨 준비 중" is *reachable* via `weatherSourceLabel` for placeholder sources, but
  those never reach the dock/detail (already nulled) — see D-Wait.
- **dust values missing (temp present):** `weatherPillDustLabel` falls back to the dust grade
  (`보통`); if the grade is also empty, the dust part is dropped and `summary` = `outdoor · temp`
  (current behavior preserved). Never a fabricated number/grade.
- **temp missing (dust present):** `summary` = `outdoor · dust`. Never a fabricated temperature.

---

## 4. Shared SSOT — one new helper (+ one optional small widget)

To guarantee the two surfaces never diverge on weather text, extract the composition into the
weather SSOT file (next to `publicWeatherOrNull`/`temperatureLabelOrNull`):

- **New helper in `apps/flutter_app/lib/features/weather/weather_helpers.dart`:**
  ```dart
  /// V1-RC3: 정직한 날씨 요약 파트. placeholder/fallback 은 publicWeatherOrNull 에서 이미
  /// null 처리됨(독·상세 모두 동일 입력). temp/dust/outdoor 이 모두 비어 있으면 summary=null.
  /// source 는 summary 가 있을 때만 의미 있으므로 summary null 이면 source 도 null(정직한 생략).
  ({String? summary, String? source}) publicWeatherSummary(
    LalaWeather? weather,
    String language,
  ) {
    final data = publicWeatherOrNull(weather);
    if (data == null) return (summary: null, source: null);
    final outdoor = outdoorLabel(data.outdoorStatus, language: language).trim();
    final temp = temperatureLabelOrNull(data.temp);
    final dust = weatherPillDustLabel(data.dust, language).trim();
    final summary = [outdoor, temp, dust]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    if (summary.isEmpty) return (summary: null, source: null);
    return (
      summary: summary,
      source: weatherSourceLabel(data.source, language: language),
    );
  }
  ```
  (Requires importing `outdoorLabel` from `place_labels.dart`, `weatherPillDustLabel` from
  `dust_label.dart`, `weatherSourceLabel` from `source_label.dart` — all already in the package.)

- **Optional small widget `apps/flutter_app/lib/features/place/widgets/place_weather_source_line.dart`**
  (mirrors the RC2 `PlaceReasonLine` SSOT-widget pattern; used by the dock):
  `PlaceWeatherSourceLine({required LalaWeather? weather, required String language})` → renders
  `S.summary · S.source` as `Row>Expanded>Text(maxLines:1, overflow:ellipsis)`, style `bodySmall` +
  slate-500 (`0xFF64748B` = `LalaVisualColors.muted`) + `w600` + height `1.2` (identical to
  `PlaceReasonLine`'s style so the two lines read as one family). Returns `SizedBox.shrink()` when
  `S.summary == null`. *If the controller prefers inlining in the dock file to avoid a new widget
  file, the helper alone is sufficient — see D-Widget.*

**Adoption:**
- **Dock:** add optional `LalaWeather? weather` param to `MapBottomDock` (default `null`); render
  `PlaceWeatherSourceLine` (or inline `Text`) after `PlaceReasonLine` (`map_bottom_dock.dart:176`).
- **Detail:** add `String? source` param to `PlaceContextCard`; pass `source: source` from
  `FeaturedPlacePanel` (`featured_place_panel.dart:87`). In `placeContextFacts`: replace the inline
  `outdoor · temp` weather fact with `S.summary`; add `S.source` chip + `sourceLabel(source)` chip
  (unconditional). Raise the `.take(5)` cap (`home_view_helpers.dart:423`) — see D-Cap.

**Colors/styles:** slate-500 `0xFF64748B` (`LalaVisualColors.muted`), chip bg `0xFFF1F5F9`
(existing `TinyMeta`/`ContextFactChip` literals). **No new token.**

---

## 5. Accessibility (a11y)

- Weather/source `Text` nodes are semantics-included by default (Flutter `Text` exposes its string
  to the a11y tree), so screen readers already announce "23°C · PM10 30 보통 · 기상청 실황".
- The dock weather line is non-interactive → adds **no new touch target** (44dp-min does not apply).
- KO-only copy on the normal path (mission invariant). No AI/robot/✨/emoji. No KO+EN mix per
  screen (`uiLanguage` switches the whole string set via the existing `language` param).
- (Optional, not required for PASS) enrich the dock's combined semantics label to include the
  weather line — only if the controller wants a single merged announcement. Default: rely on the
  per-node Text semantics (matches how the detail `ContextFactChip`s already behave).

---

## 6. Responsive — no overflow at narrow viewport (follow #124 / RC2 §6)

- **Dock `[W]` line** is `Row>Expanded>Text(maxLines:1, ellipsis)` by construction → never overflows
  (same shape as `PlaceReasonLine`, proven at 320/360dp in RC2). The dock is wrapped in
  `SingleChildScrollView` (`map_bottom_dock.dart:86`) so even a worst-case 2-row TinyMeta Wrap +
  reason + weather + docent cannot crash; the risk is only vertical tightness in the fixed
  `height` (`dashboard.dart:266-270`: 218 wide / 196 mobile / 164 short). **Verification gate:**
  pump `MapBottomDock` with weather + reason + long dust at 360/393dp and assert
  `tester.takeException()` is null (extend `narrow_viewport_no_overflow_test.dart`).
- **Detail** chips live in a `Wrap` inside a scrollable draggable sheet → wrap, never overflow.
- **Gate (test):** extend `narrow_viewport_no_overflow_test.dart` with a `MapBottomDock` case
  (weather present, long PM label) at 360/393dp.

---

## 7. Decisions — approved by controller (locked)

All seven decisions below are **approved** by the controller; the recommended option is locked in.
Rejected alternatives are retained for the record.

- **D-Src — APPROVED: guard the empty `'-'` source chip on both surfaces.** `sourceLabel('')` →
  `'-'`; apply a 1-line `!= '-'` guard to the dock's existing source TinyMeta
  (`map_bottom_dock.dart:165`) **and** omit the detail rec-source chip when `'-'`, so dock + detail
  are byte-identical (honest absence instead of a bare `-`). *(Rejected: dock shows `-` while detail
  omits → surfaces diverge.)*
- **D-Wait — APPROVED: weather null → honest omission (no pending chip).** Because
  `publicWeatherOrNull` already nulls placeholder/fallback weather at `dashboard.dart:211`, "날씨 준비
  중" never reaches these surfaces; omit the weather line/chip on both when weather is null. The map's
  existing `WeatherMapPill` (`MapUtilityControlRow`, `dashboard.dart:507`) already shows the pending
  state. *(Rejected: render "날씨 준비 중" when null.)*
- **D-Cap — APPROVED: raise `placeContextFacts` cap `.take(5)` → `.take(8)`.** Required so the new
  unconditional source/weather facts are not truncated; the normal path can reach 6 and the evidence
  path up to ~9. The detail sheet scrolls; `ContextFactChip` wraps. *(Rejected: render the new facts
  as a separate always-on block outside the capped `Wrap`.)*
- **D-Outdoor — APPROVED: keep outdoor status in the weather chip (additive).** The summary stays
  `outdoor · temp · dust`; outdoor is not removed (do not drop existing honest info). *(Rejected:
  strict `temp · dust` only.)*
- **D-Icon — APPROVED: distinct icons.** Rec-source chip = `Icons.bolt_outlined`; weather-source
  chip = `Icons.cloud_outlined`; dust rides the existing `wb_cloudy_outlined` weather chip. Avoids
  two identical `verified_outlined` chips when `showEvidence=true` (the gated provenance fact keeps
  `Icons.verified_outlined`, `home_view_helpers.dart:414`). No new color.
- **D-Widget — APPROVED: new `PlaceWeatherSourceLine` widget** (mirrors `PlaceReasonLine`,
  testable, future-reusable), used by the dock. *(Rejected: inline the `Text` in the dock file.)*
- **D-SourceParam — APPROVED: thread `source` into `PlaceContextCard`.** `FeaturedPlacePanel.source`
  (`featured_place_panel.dart:48`) is passed one level deeper to `PlaceContextCard`. No new data/call.

---

## 8. Acceptance matrix (what must be true to PASS)

Per surface, normal path (`showEvidence=false`), weather present:
- [ ] **Dock** shows a weather line = `summary · weatherSourceLabel` (e.g.
      "23°C · PM10 30 보통 · 기상청 실황"); recommendation-source chip unchanged (or `'-'`-guarded
      per D-Src).
- [ ] **Detail** `PlaceContextCard` shows: weather chip `outdoor · temp · dust`; weather-source
      chip (`weatherSourceLabel`); recommendation-source chip (`sourceLabel`).

Honest omission:
- [ ] **Dock** weather null → weather line absent (no "날씨 준비 중" unless D-Wait says so); no
      fabricated temp/dust/source.
- [ ] **Detail** weather null → weather chip + weather-source chip absent; rec-source chip still
      present when source ≠ `-`.
- [ ] Dust values missing → dust part dropped (falls back to grade, then omitted); never a
      fabricated number/grade.

Evidence gating (must not regress):
- [ ] `showEvidence=false` → `SignalGrid` + `PublicDataProofRow` **not** rendered.
- [ ] `showEvidence=true` → `SignalGrid` + `PublicDataProofRow` rendered; normal-path
      source/weather truth **still** rendered.
- [ ] Internal `score` components never appear on the normal path.

Consistency:
- [ ] One `LalaWeather` → identical `summary` + `source` text on dock and detail (both via
      `publicWeatherSummary`; consistency test pumps the helper with one fixture).
- [ ] No surface recomputes/rewords temp/dust/source (grep: weather text only via
      `publicWeatherSummary`; source only via `sourceLabel`/`weatherSourceLabel`).

Scope / honesty:
- [ ] **0 files under `apps/api/`**; no new external/AI/mock/snapshot call.
- [ ] KO-only normal-path copy; no emoji/AI decoration; no KO+EN mix.
- [ ] Carousel / header / marker **untouched** (RC3 = selected surfaces only).
- [ ] RC2 dataset `dataAsOf` chip + per-place freshness concept **unchanged** (D-2 preserved).

Tests (Phase 2 — only after approval):
- [ ] **Keep green with ZERO assertion changes:** `search_page_states_test.dart`,
      `narrow_viewport_no_overflow_test.dart`, `v1_rc2_reason_freshness_test.dart`,
      `map_bottom_dock_test.dart` (the dock's new `weather` param is **optional, default null** →
      existing ctors compile unchanged → these tests are not even edited).
- [ ] New `publicWeatherSummary` unit tests: present → `(summary, source)`; null/fallback →
      `(null, null)`; dust-missing → dust dropped; temp-missing → temp dropped. (Extend
      `test/features/weather/weather_helpers_test.dart`.)
- [ ] Dock widget test: weather present → line shown; weather null → line absent (extend
      `map_bottom_dock_test.dart` with a `_dock(weather: …)` variant).
- [ ] Detail widget test (new — `PlaceContextCard` has no test today): normal path shows
      rec-source + weather-source + dust; weather null omits weather chips; `showEvidence=true`
      still gates `SignalGrid`/`PublicDataProofRow` via `FeaturedPlacePanel`.
- [ ] Overflow: extend `narrow_viewport_no_overflow_test.dart` — `MapBottomDock` with weather +
      long dust at 360/393dp, `tester.takeException()` null.
- [ ] Weather is a static server string + already-fetched model → **no frozen-wall-clock** needed
      in Flutter tests (same as RC2). Fixtures use literal temp/dust/source.

---

## 9. Out of scope (frozen / explicit non-goals)

- Carousel card / header / marker (RC3 = selected dock + detail only; weather is selected/region
  truth — rendering it per carousel card would mislead).
- Merging/altering the RC2 dataset `dataAsOf` chip or the per-place `freshness` concept (D-2 stays).
- Any API, client-model, or state-management change; any new fetch/external/AI/mock/snapshot call.
- The Kakao JS webview marker info-window (`LegacyMapCanvas`) — rendered in JS, not Flutter.
- PR mechanics for #133 — base retarget to `integration/lala-vision-v3`, title, open/close/merge —
  are **integrator-owned**; this foundation slice only adds one doc commit on the canonical branch.
  No separate RC3 branch or PR is created (binding work is a later per-phase lane, §10).
- Mutation of `23e7b50`, PR #132/#133, `main`, `integration/lala-vision-v3`, or any closed branch.
- main merge, deploy, production DB write/migration, crawl, DNS/auth mutation, paid AI/Speech,
  live provider call, secret output.

---

## 10. Implementation plan (future per-phase lane — NOT this foundation slice)

This foundation slice ships the contract **doc only** — one commit on the canonical branch
`geondongkim/lala-v1-rc2-rail-reason-freshness` (PR #133), approved as a contract-only commit. The
binding work below happens in a **later per-phase implementation lane** (its own branch + Draft PR
per the V1 delivery policy) — not in this doc commit, and without touching #133's base/title
(integrator-owned).

1. In the implementation lane's branch: add `publicWeatherSummary` to `weather_helpers.dart` (+ imports).
2. (D-Widget) Add the `PlaceWeatherSourceLine` widget.
3. Dock: add optional `weather` param to `MapBottomDock`; render the weather line after
   `PlaceReasonLine`; (D-Src) guard the source TinyMeta against `'-'`. Thread `weather:
   currentWeather` at `dashboard.dart:438`.
4. Detail: add `source` param to `PlaceContextCard`; pass from `FeaturedPlacePanel`; in
   `placeContextFacts` use `publicWeatherSummary` for the weather fact + add weather-source &
   rec-source chips (unconditional); (D-Cap) raise `take(5)`→`take(8)`; (D-Icon) distinct icons.
5. Tests per §8; `dart format`; `flutter analyze` on touched files; `flutter test` (affected +
   full). Keep RC1/RC2 green with zero assertion changes.
6. Incremental commits (one coherent sub-step each); push every 1–3 commits; **never push red**.
7. The implementation lane reports its own head SHA, commands run, focused + full test results,
   CI run id, and what is NOT yet verified. **Report = CLAIM** — cross-checked against actual
   diff/tests/CI. No self-declared visual PASS.
