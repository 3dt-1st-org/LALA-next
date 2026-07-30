# 03. States and Interaction (20260728)

Covers item (6) per-state design (loading / loaded / empty / unavailable /
error — including honest empty, never mock-filled) and item (7) interaction, for
each of the four screens.

State rule (global): a state without data shows an **honest** empty/unavailable
surface. It must **not** be filled with mock, demo, random photo, or invented
approval data. Source: target README ("mock 또는 임의의 값으로 화면을 채우면 안
된다") + `code: local_signals_page.dart` status machine +
`code: plan_page.dart` status machine.

---

## Screen 01 — Map

### (6) States
| State | Surface | Copy / treatment | Source |
| --- | --- | --- | --- |
| Loading | Skeleton map tiles + shimmer rail; no fabricated markers | `muted` helper | code: `home_view_helpers.dart` recovery copy; target-derived pending for skeleton |
| Loaded | Kakao tiles + individual category markers + rail | per-place card | code: `home_page.dart` |
| Empty (no nearby place) | Honest empty message; **no** invented POIs | `muted` empty copy | target-derived (20260728); design-owner pending |
| Unavailable (map/geo failure) | Map unavailable surface; region fallback to manual `regionId` | error copy | code: `home_view_helpers.dart` (`추천 장소를 불러오지 못했어요…`) |
| Error (rec-connect degrade) | Auto-retry banner; rail preserved | `추천 연결이 잠시 지연되고 있어요…` | code: `home_view_helpers.dart` |

### (7) Interaction
- **Pinch/pan → debounce bounds query**: after the pan ends, debounce, then query
  the visible bounds for official places. `Source: target README P5` + `target:
  01_target_map.png`. Debounce window: `target-derived (20260728); design-owner
  pending` (no constant in code yet).
- **Marker ↔ card bidirectional selection**: tapping a marker selects the
  matching rail card and vice-versa; scrolling a card into focus selects its
  marker. `Source: design-qa.md` (rail first card aligns with selected panel) +
  `code: home_page.dart` (`_selectPlace`).
- **`왜 지금 추천해요?` folded by default**: rationale is collapsed; score and
  ranking formula hidden until the user opts in. `Source: target README`
  ("추천 점수와 내부 계산식은 기본 화면에서 감추고, 근거는 사용자가 요청할 때").
- **`일정에 넣기`**: enters the existing selected-place planner sheet; does not
  create a new itinerary until the planner produces one. `Source: target README`
  + `code: planner sheet` reuse.
- **Pin-first clustering**: individual markers at close zoom; cluster only at far
  zoom or ≥ 80 places. `Source: target README P5` + `00` §3 invariants.
- **Honest "no image"**: a place without an image shows the no-image state, never
  a random substitute. `Source: target README P5`.

---

## Screen 02 — Local Signals

### (6) States — `code: local_signals_page.dart` (`_LocalSignalsStatus`)
| State | Surface | Copy | Source |
| --- | --- | --- | --- |
| `loading` | List placeholder | — | code: status machine |
| `loaded` | `_SignalCard` list + `더 보기` | per card | code |
| `empty` | Honest empty (no signals) — **not** mock-filled | `target-derived (20260728); design-owner pending` | code status + target |
| `disabled` | Feature-off surface (read disabled) | `target-derived; design-owner pending` | code: `disabled` branch |
| `error` | Error surface + retry | `target-derived; design-owner pending` | code: `error` branch |

> Each card exposes only the public projection fields (`code:
> local_signal_public.dart`): source, freshness date, translation provenance,
> policy status. No author, score, raw review, moderation, token, or
> coordinates.

### (7) Interaction
- **Place action boundary**: a signal with a canonical `place_id` link offers a
  view-place/add-to-plan intent; a signal without one renders **no** place
  action. `Source: code: core/navigation/local_signal_action.dart` + PR #77
  contract.
- **Pending intent resolves against real map results only**: unresolved IDs show
  an honest localized unavailable state; never fabricate a marker/detail.
  `Source: code: local_signal_action.dart` + PR #77.
- **Duplicate dispatch collapsed**: identical action dispatches consume once.
  `Source: code: local_signal_action.dart`.
- **Region selector**: coarse manual `regionId` only (`전국`/`Nationwide`);
  region is not a server region code. `Source: code: local_signals_page.dart`.

---

## Screen 03 — Plan

### (6) States — `code: plan_page.dart` (`_PlanLoadStatus`)
| State | Surface | Copy | Source |
| --- | --- | --- | --- |
| `loading` | Overview + slot placeholders | — | code |
| `data` | 4-slot timeline + overview + toast | per slot | code |
| `error` | Error surface + retry | `target-derived; design-owner pending` | code: `error` branch |
| Empty (no plan yet) | Honest empty "make a plan" CTA; no seed slots | `target-derived; design-owner pending` | target README + `code: plan_page.dart` |

### (7) Interaction
- **4 slots**: morning/lunch/afternoon/dinner, filtered by language
  (`hasVisiblePlanSlot`). `Source: code: plan_page.dart` + `target README P4`.
- **Intervention toast**: weather/PM or open-hours change surfaces an alternate
  with reason. `Source: code: InterventionToast` + `target README P4`.
- **Travel time / open hours / meal context**: shown inline per slot; no food
  filter, meals placed by context. `Source: target README P4`.
- **Small-merchant vs franchise**: card consumes aggregate economy data to
  distinguish; no ranking score shown. `Source: target README P1`.

---

## Screen 04 — Weather recovery (plan sub-state)

### (6) States
| State | Surface | Copy | Source |
| --- | --- | --- | --- |
| Restored | Prior plan restored after relaunch; recovery banner | `target-derived; design-owner pending` | `target README P4` + `code: plan_page.dart` restore |
| Swapped | Prior (muted) → alternate (`primaryBlue` accent) + per-swap reason | `target-derived; design-owner pending` | target README + `04_target_weather_recovery.png` |
| Persisting toast | `InterventionToast` remains until dismissed | per toast | code: `InterventionToast` |

### (7) Interaction
- **Transparent swap**: show old **and** new place + change reason together
  (rain / PM / closed-day). `Source: target README P4`.
- **State restore on relaunch**: location + plan restored; if context changed,
  show original vs alternate. `Source: target README`.
- **No silent overwrite**: the prior slot is kept visible (muted) — not erased —
  while the alternate is highlighted. `Source: target: 04_target_weather_recovery.png`.
