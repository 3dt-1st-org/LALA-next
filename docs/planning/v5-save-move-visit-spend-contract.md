# V5 — Save / Move / Visit / Spend Conversion Design Contract (D1–Dn per lane)

> Phase V5 contract off the V4 head `6da6510`. One V5 branch + one Draft PR.
> Authoritative for V5. **Offline + CI only.** Runtime/device/live API = **V7 BLOCKED_EXTERNAL**.
>
> | | |
> |---|---|
> | Phase | V5 — "save-move-visit-spend conversion" |
> | Base SHA | `6da6510` (V4 head) |
> | Branch | `geondongkim/lala-v5-save-move-visit-spend` |
> | Draft PR base | `geondongkim/lala-v4-rag-docent-speech` |
> | Status | **GREENFIELD** — no prior V5 spec/slice/commit exists; this contract is the spec |
> | Mode | Offline-only. No paid/live/Azure call. No migration-apply. No DB. |

## 0. Context & scope verdict

V5 is the **action / conversion layer** on top of V1 (location/map/reason) → V2 (Local Signals)
→ V3 (4-slot plan) → V4 (RAG docent/speech/QA). It is **GREENFIELD**: at base `6da6510` no V5
spec, slice, or commit exists — this document is the specification.

### 0.1 Root structural fact (verified by-SHA @ `6da6510`)

**Daily plans are NOT persisted today.** `apps/api/app/services/planner_service.py` is fully
stateless — pure functions computed on-the-fly, no DB writes. There are **no**
`plans` / `plan_slots` / `user_saves` / `visits` / `budget` tables. Migrations are canonical
SQL files under `sql/canonical/` (no alembic; raw-SQL applied via `db_repository.py` /
`canonical_sql.py` / `db_schema.py`). V5 introduces persistence for the action layer; the
canonical-SQL files are **written and committed** but **NEVER applied to a DB in V5**
(apply = explicit user action, never a controller/worker action).

### 0.2 Per-concept status (verified @ `6da65100`)

| Concept | Status | In-tree evidence @ `6da6510` |
|---|---|---|
| **SAVE** | PARTIAL-ephemeral | `apps/flutter_app/lib/features/home/home_page.dart:153` keeps an in-memory `Set<String> _savedPlaceIds` (resets on cold start); UI copy in `featured_place_header.dart:74-79` ("저장/저장됨" / "Save/Saved"). No persistence, no backend, no generated-client method. |
| **MOVE** | PARTIAL | Haversine walk-time only: `apps/api/app/services/travel_time_service.py:37 estimate_walking_minutes()` (straight-line ÷ 4 km/h), emitted as `travelTimeFromPreviousMinutes` on `LalaPlanSlot`. No Kakao/Naver Directions, no transit mode, no polyline, no road distance, no ETA authority. |
| **VISIT** | ABSENT | No check-in / visited / visit-status field, table, UI, or endpoint anywhere. |
| **SPEND** | ABSENT (user-facing) | Only aggregate demographic `economy.card_spending_area_monthly`, a `localSpendingScore` 0–1 docent signal, and `ops.daily_costs` infra accounting — none is per-place/per-plan user budget. |
| **Generated client** | No methods | `clients/flutter/lib/lala_api_client.dart` has NO save/visit/spend/route methods. |

⇒ V5 = introduce persistence + action endpoints + regenerated client (V5-A), wire the action UI
(V5-B), and place a flag-gated routing seam that keeps the offline honest estimate unchanged
(V5-C). V5 keeps the existing SAVE UI shape and the existing Haversine output byte-for-byte.

## 1. Hard invariants (carry from V1–V4, unchanged)

1. **Offline-only.** No network call leaves the process except the gated provider boundary.
2. **Standard OpenAI only, never Azure.** The Azure firewall (`config.py` reject-Azure contract)
   holds at every resolution. V5 adds no LLM path, so this is a non-regression assertion.
3. **Mock ONLY at the gated provider boundary.** No mock/demo on the normal path; the normal
   path is real code against real (persisted) data or honest unavailable.
4. **No paid/live provider call.** Real Kakao/Naver Directions and real per-place pricing are
   BLOCKED_EXTERNAL / V7 (§3).
5. **KO/EN single-language.** All new copy via `lalaCopy(language, ko:, en:)`. No third language.
6. **Generated-client SSOT.** `clients/flutter/lib/lala_api_client.dart` is regenerated from
   `openapi.py`. NO hand-edits. `toJson` count on the generated client must remain `0`.
7. **Honest unavailable / empty states** when data is absent. Never fabricate a visit, a save,
   a budget, or a route.
8. **Preserve all V1–V4 surfaces.** Docent/speech/QA, plan slots, Local Signals, map/reason —
   all additive only.
9. **Canonical-SQL files are committed but NEVER applied to a DB in V5.** Migration-apply is an
   explicit user action, not a controller/worker action.
10. **No secret output.** No API keys, no PII beyond the action DTO, in logs/responses/docs.

## 2. V5 dependency DAG

```
V5 base @ 6da6510
  ├── V5-A (persistence foundation)  ── DATA-INTEGRITY root; ONE lane first
  │     ↳ V5-B (Flutter action UI)      ┐ disjoint (Flutter vs backend-routing);
  │                                     │  parallel after V5-A green
  │     ↳ V5-C (MOVE routing boundary)  ┘
  └── V5-F offline verifier → V5_PHASE_PASS  (runtime/device/live API = V7 BLOCKED_EXTERNAL)
```

- **V5-A is the data-integrity root and lands first.** V5-B and V5-C consume its schemas.
- **V5-B and V5-C are pairwise disjoint** (Flutter UI vs backend routing seam) and may run in
  parallel once V5-A is green.
- **V5-F re-derives** all claims from the integrated head; it does not trust controller reports.

## 3. BLOCKED_EXTERNAL / V7 (flag-gated OFF — NOT V5 actions)

Mirror V4's speech/AI gating discipline. V5 lands the **offline fallback + honest unavailable**
shape only; the live call is never made.

- **(a) Real routing via Kakao/Naver Directions API (paid/live).** Offline stays the existing
  Haversine walk-time (`travel_time_service.py:37`) as the honest estimate; the V5-C seam adds
  a flag-gated hook that returns null ETA when the flag is OFF (default). The Directions call
  itself is V7.
- **(b) Real per-place pricing (paid/live data source).** Offline uses category-band estimates
  with honest unavailable; no live pricing fetch in V5. The live source is V7.

Both are flagged OFF by default. V5 ships the gating + the honest-offline path, never the call.

## V5-A — Persistence foundation (DATA-INTEGRITY; contract-gated; backend)

### A1. Scope

- New canonical-SQL file(s) under `sql/canonical/` for: persisted daily-plan, plan-slots,
  `user_saved_places`, `slot_visits`. Additive numbering; do not touch existing files.
- A new repository module (raw-SQL, parameterized, additive). Do **not** rewrite
  `db_repository.py` — extend via a sibling module that imports the shared connection helpers.
- Additive endpoints in the v1 router: toggle/save a place, save/load a persisted plan,
  visit/check-in a slot. Auth-scoped to the caller; honest empty when absent.
- Additive `openapi.py` schema entries (DTOs only for the action layer).
- Regenerate `clients/flutter/lib/lala_api_client.dart` from the updated spec (SSOT).

### A2. Off-limits (do not mutate)

- `apps/api/app/services/planner_service.py` — read-only; extend-via-composition only. Its pure
  functions stay pure (no DB writes introduced into existing signatures).
- `docent_*` services, `ai_service`, `speech_service` — untouched.
- Existing `openapi.py` schemas — add only, never edit existing DTOs.
- Existing migrations under `sql/canonical/` — append-only.

### A3. D-gates (each must be testable offline)

- **D1 — Persisted-plan + slots schema.** Versioned envelope (`schema_version`, `created_at`,
  `updated_at`); slots reference place-id + slot-index; one plan per user-visible itinerary
  calendar date. A date-only key is not converted through UTC.
- **D2 — `user_saved_places`.** User-scoped, place-id only (no coordinates/PII), idempotent
  toggle (save → unsaved → save is a no-op delta, not a duplicate row).
- **D3 — `slot_visits` / check-in.** Status enum (`planned` / `visited`) + optional timestamp;
  idempotent re-check-in (no duplicate row).
- **D4 — Repository CRUD.** Parameterized SQL everywhere; no string concatenation of user
  input; injection-immune by construction (prove with a negative test).
- **D5 — Endpoints.** Auth-scoped to the caller (user-id bound); honest empty (`[]` / `null`)
  when absent; never 500 on missing data.
- **D6 — openapi additions.** Additive only; `additionalProperties: false` on new DTOs unless
  envelope-versioned; no change to existing DTO field names/types.
- **D7 — Client regen (SSOT).** Prove `toJson` count on `lala_api_client.dart` == 0 and the
  regen path is `openapi.py → generator → client` with no hand-edit diff.
- **D8 — Data-integrity.** Corrupt envelope → `null` graceful (no throw); version-mismatch →
  `null` graceful; privacy scope = user-id + place-id/plan-id only (no coordinates/PII beyond
  the DTO); cross-user read returns empty, never another user's data.
- **D9 — Honest unavailable/empty.** No persisted plan for today → empty plan object, not an
  error; no saves → empty list; no visits → slots render as `planned`.
- **D10 — No AI/paid call on this lane.** Zero new live/Azure/paid invocations.

### A4. Acceptance matrix (V5-A)

| ID | Requirement | Offline proof |
|---|---|---|
| A1 | Canonical-SQL files committed, **not applied** to any DB | files present under `sql/canonical/`; no apply-step in CI/worker |
| A2 | `planner_service.py` byte-identical (or composition-only) | `git diff` shows no mutation of pure functions |
| A3 | Repository is parameterized-SQL, injection-immune | negative test with `' OR 1=1 --` style input returns empty/error |
| A4 | Idempotent toggle (save/unsaved/save = one row) | repeat-toggle test asserts single row |
| A5 | Idempotent check-in (re-check-in = one row) | repeat-check-in test asserts single row |
| A6 | Cross-user isolation | user-B cannot read user-A's plan/saves/visits |
| A7 | Corrupt envelope → null, no throw | malformed-json test returns null gracefully |
| A8 | Version-mismatch → null, no throw | future-version envelope returns null gracefully |
| A9 | Endpoints honest-empty when absent | missing-data fixtures return `[]` / `null`, 200 |
| A10 | `openapi.py` additions are additive | no existing DTO field renamed/removed/retyped |
| A11 | Client SSOT: `toJson` == 0, no hand-edit | generated diff matches regen output exactly |
| A12 | No AI/paid/Azure call on the lane | grep proves zero new live invocations |
| A13 | Standard OpenAI never Azure (non-regression) | Azure firewall contract test still green |

## V5-B — Flutter action UI (depends on V5-A schemas)

### B1. Scope

- **SAVE persist + hydrate** the existing ephemeral UI via a NEW namespaced SharedPreferences
  key prefix `lala.v5.*` + a new store. Mirror the V1 `cross_tab_preferences.dart` pattern:
  app-owned encoder, versioned envelope, corrupt → null. Do **not** add `toJson` to the
  generated client (the store owns serialization).
- **VISIT check-in UI** on plan slots (status badge `planned` / `visited`; tap to check in).
- **SPEND budget-band offline view** (category-band estimate per slot; honest unavailable band
  when no estimate). No live pricing.
- Keep the existing SAVE UI shape in `home_page.dart` / `featured_place_header.dart` — extend
  via a store, do **not** rewrite the widgets.

### B2. Off-limits (do not mutate)

- Generated client (`lala_api_client.dart`) — regen only, no hand-edit.
- `dashboard.dart` core wiring — additive optional params only.
- `widget_test.dart` golden — extend, do not break.
- V1–V4 feature files — extend, do not mutate existing render contracts.

### B3. D-gates

- **D1 — SAVE persist + hydrate.** Cold-start restores saves; epoch-guard discards stale
  envelopes (older schema version → null, hydrate empty).
- **D2 — VISIT check-in UI.** Tap toggles `planned` ↔ `visited`; persists through the store.
- **D3 — SPEND budget-band view.** Category-band estimate rendered; honest-unavailable band
  when absent (no fabricated number).
- **D4 — Wire via regenerated client.** Uses V5-A client methods only; no hand-written HTTP.
- **D5 — Honest states.** Empty saves / no visits / no estimate each render their distinct
  honest state, never a spinner-as-failure or fabricated data.
- **D6 — KO/EN single-language.** All new strings via `lalaCopy(language, ko:, en:)`.
- **D7 — No new color tokens** outside the documented tile/toast sets (per STYLEGUIDE).

### B4. Acceptance matrix (V5-B)

| ID | Requirement | Offline proof |
|---|---|---|
| B1 | Cold-start hydrates saves | restart test asserts saves restored from `lala.v5.*` |
| B2 | Corrupt envelope → empty, no crash | malformed-pref test hydrates empty |
| B3 | Epoch-guard discards stale envelope | older-version pref is ignored gracefully |
| B4 | VISIT check-in persists | toggle survives store reload |
| B5 | SPEND band honest-unavailable | absent-estimate slot renders unavailable band |
| B6 | No hand-edit to generated client | `toJson` == 0; diff is pure regen |
| B7 | KO/EN via `lalaCopy` | grep finds no raw user-facing KO/EN literal in new code |
| B8 | No new color tokens | new styles use documented tile/toast tokens only |
| B9 | `widget_test.dart` golden still passes | golden extended, not broken |

## V5-C — MOVE routing boundary (flag-gated, parallel-able with V5-B)

### C1. Scope

- Extend `apps/api/app/services/travel_time_service.py` **additively** with a flag-gated routing
  seam. New flag e.g. `LALA_ENABLE_LIVE_ROUTING`, default **False**.
- Offline path = existing Haversine walk-time (`estimate_walking_minutes`, byte-for-byte
  unchanged) as the honest estimate.
- Add a `stay_duration_minutes` / ETA field that is **honestly null** when live routing is OFF.
- Real Kakao/Naver Directions = BLOCKED_EXTERNAL / V7 — the seam is a hook, never a call.

### C2. Off-limits

- Do **not** change the Haversine offline output (existing callers must see identical numbers).
- Coordinate the shared openapi field addition with V5-A (one additive DTO field, not two).

### C3. D-gates

- **D1 — Flag OFF default.** `LALA_ENABLE_LIVE_ROUTING` defaults to False; no env override in CI.
- **D2 — Offline = Haversine byte-for-byte.** `travelTimeFromPreviousMinutes` identical pre/post.
- **D3 — No live/paid call.** The seam never invokes Directions; gated hook only.
- **D4 — Honest ETA unavailable when off.** `stay_duration_minutes` / ETA is null, not a guess.
- **D5 — Additive.** Existing callers of `estimate_walking_minutes` unchanged.

### C4. Acceptance matrix (V5-C)

| ID | Requirement | Offline proof |
|---|---|---|
| C1 | Flag OFF by default | config assertion in tests |
| C2 | Haversine output unchanged | golden test on `estimate_walking_minutes` inputs |
| C3 | ETA null when routing OFF | response fixture shows null ETA |
| C4 | No Directions call | grep proves zero live-routing invocations |
| C5 | Existing callers unchanged | `git diff` on call sites = none |
| C6 | openapi field additive | shared with V5-A; no existing DTO mutated |

## V5-F verifier carry-in (re-derive — do NOT trust controller claims)

The verifier MUST confirm, by re-deriving from the integrated head (not by reading this doc):

- **Offline / boundary integrity.** No live/paid call on any V5 lane; mock only at the gated
  provider boundary; a `live_client_constructions=0`-style proof where applicable.
- **Standard OpenAI never Azure.** The reject-Azure contract still holds (non-regression; V5
  adds no LLM path, so this asserts the firewall is intact).
- **Generated-client SSOT.** `toJson` == 0 on `lala_api_client.dart`; regen path intact; no
  hand-edit diff between generator output and committed client.
- **Honesty.** Honest unavailable/empty states for SAVE/VISIT/SPEND/MOVE; no mock/demo on the
  normal path.
- **Data-integrity.** Corrupt → null; version-mismatch → null; privacy scope (user-id +
  place-id/plan only, no coordinates/PII beyond DTO); idempotent toggle and idempotent check-in;
  cross-user isolation.
- **Scope / disjoint.** V5-A ∩ V5-B ∩ V5-C = pairwise disjoint; no off-limits files mutated; no
  api/schema bleed beyond the V5 DAG.
- **KO/EN single-language.** All new copy via `lalaCopy`.
- **On-demand score/reason preserved.** V1 `/docents/reason` deferred state unchanged (not
  regressed, not silently built).
- **CI green** at the exact integrated head.

A V5_PHASE_PASS requires every item above green. Any single failure blocks the phase.

## Carry-in / deferred (NOT V5 failures)

- **Speech provider (V4, BLOCKED_EXTERNAL)** — live TTS provider decision is V7.
- **`/docents/reason` (V1 invariant)** — on-demand score/reason surface; deferred, not V5.
- **Real routing + real per-place pricing (V7 BLOCKED_EXTERNAL)** — V5 ships the gating +
  honest-offline fallback only; the live call is V7.
- **Runtime / device (iPhone 17 Pro) / web / live API** — V7.
