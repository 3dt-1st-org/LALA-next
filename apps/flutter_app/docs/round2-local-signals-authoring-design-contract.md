# Round 2 Local Signals authoring (F-071) — design contract

Scope: `apps/flutter_app/lib/features/local_signals/**`. No API, SQL, client,
router, or product-doc changes. Base:
`origin/integration/canonical-screen-completion-20260903` @ `f97215d`.

## Problem

The full create/update/submit/delete draft composer existed only inside S-32
detail. With an empty public feed (current production truth) there is no S-31
route to any detail, so nothing on the Local Signals tab lets a user
contribute. F-071 stays PARTIAL for that reason, not for missing code.

## Solution shape

1. The private-draft composer is extracted (not copied) from
   `local_signal_detail_page.dart` into
   `presentation/widgets/local_signal_contribution_composer.dart` as the public
   `LocalSignalContributionComposer`. Hosts own navigation; the widget takes an
   `onClose(submitted)` callback.
2. Two hosts:
   - S-32 detail keeps its in-page entry, which opens the composer as a modal
     sheet with the linked canonical place context (`locality_level: place`).
   - S-31 gains `LocalSignalDetailArguments.contribute(...)` — a visible
     "Share your experience" entry that routes through the existing
     `onOpenDetail` channel to the S-32 route in contribute mode. The S-32
     route is the only Local Signals surface the shared router already wires
     with the app's `LalaAuthController`, so reusing it avoids both a router
     edit and a second auth-controller instance (which would desync sign-in
     state from S-50/S-51).
3. Contribute mode on the S-32 route renders the auth gate first (guests get a
   real sign-in flow or an honest "unavailable in this build" notice — never a
   simulated session), then the embedded composer.

## S-31 entry-state matrix (policy)

| S-31 state | Share entry | Why |
| --- | --- | --- |
| loading | hidden | transient; entry appears with the resolved state |
| loaded | shown | policy permits contribution |
| aggregate-only (empty feed + aggregates) | shown | feed empty is exactly when contribution is most needed |
| empty | shown | same |
| error | hidden | retry is the honest next action; feed state unknown |
| disabled (`LOCAL_SIGNALS_DISABLED`) | hidden | the readiness flag is externally owned and off; inviting writes the server has not announced readiness for would end in a 503. This is the "where policy permits" boundary. |

The entry also requires a non-null `onOpenDetail` (always provided by the app
router) so the button never dead-ends.

## Context truthfulness

- Manual coarse region (S-31): payload sends `locality_level: 'district'`,
  `locality_code: <manual region id>`, no `place_links`. The composer shows the
  region label. With no manual region the composer honestly shows
  "nationwide / no region context" and omits `locality_code` (API-legal).
- Canonical place (S-32): `locality_level: 'place'`,
  `place_links: [{place_id, relation: 'primary'}]`, no locality code.
- Precise coordinates are never sent: `RegionSource.current` carries lat/lng
  and is excluded from contribution context by the same manual-only rule the
  S-31 feed read already uses.
- KO/EN source-language constraint stays truthful on ja/zh UI: the composer
  states that only Korean and English originals are accepted; non-ko UI
  submits an English source language.

## Input protection contract

- Unsaved-dismiss confirmation: sheet is not barrier/drag-dismissible; the
  explicit close action and system back (PopScope) confirm before discarding
  dirty input. Clean (untouched) input closes without a dialog.
- Busy guard: save/update/submit/delete disable each other while a request is
  in flight; close is blocked while busy.
- Validation feedback: save with empty title/body keeps the button reachable
  and shows inline per-field errors instead of silently doing nothing.
- Retry-safe failure: any failure keeps typed text, shows a safe error, and a
  `LOCAL_SIGNALS_DISABLED` write rejection renders the honest
  "not accepting contributions right now" copy instead of a generic error.
- Delete: explicit confirmation dialog before the irreversible call.
- Receipt: status / moderation state / visibility labels come only from the
  API receipt; unknown wire values render raw. After submit, the receipt stays
  visible until the user explicitly closes (완료/Done).
- No "My drafts" list: no proven read API exists for listing own drafts.

## Separation guarantees preserved

Governed aggregates remain labelled as system data; user contributions remain
labelled as private-until-reviewed. Ad/sponsorship disclosure, anonymous
aggregate opt-in (raw text/author never exposed in aggregates), moderation,
source privacy, and the no-Daangn / no-HTML-scraping boundaries are unchanged.
No demo/mock content is inserted into any state.

## Accessibility and locales

All new copy goes through `lalaCopyMulti` with ko/en/ja/zh-Hans/zh-Hant.
Layouts survive 200% text scale (scrollable bodies, wrapping buttons, no fixed
heights); focused tests pin overflow-free rendering at 2.0 scale.
