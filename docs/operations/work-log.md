# LALA Work Log

Last updated: 2026-06-24 KST

This document is the dated execution log for non-trivial LALA repo work.

Use it together with the other docs layers:

- strategy docs explain what we intend to do and why;
- status docs explain the current baseline and remaining gaps;
- this work log records what actually changed, when, and where to look next.

Keep this document secret-safe: do not add live Key Vault URLs, database DSNs,
subscription ids, tokens, or generated resource names.

## Recording Rule

For every non-trivial slice, update at least:

1. the strategy or status doc that changed meaningfully;
2. this work log with a dated summary, verification shape, and follow-up.

If a slice changes ingest behavior, score semantics, rollout policy, or shared
environment evidence, it should not live only in chat history.

## 2026-06-24

### Chrome Automation and Flutter Web Semantics Slice

What changed:

- Investigated the user's `@chrome` complaint directly against the live
  `https://lala-next.cloud/` tab.
- Confirmed that the Codex Chrome Extension, native-host manifest, and Chrome
  runtime are all installed, enabled, and communicating correctly.
- Compared the live LALA tab against a normal GitHub tab and found that Chrome
  automation works on standard DOM pages but sees only the Flutter web
  placeholder/accessibility surface on the LALA map page.
- Updated [apps/flutter_app/lib/main.dart](/Users/geondongkim/LALA-next/apps/flutter_app/lib/main.dart)
  to force Flutter web semantics on startup so browser automation and assistive
  tooling can inspect more than the minimal canvas fallback.

Why it matters:

- The root problem is not a broken Chrome plugin install.
- The main issue is that the live Flutter web surface exposes too little DOM to
  automation until semantics are enabled.

Follow-up:

- redeploy the Flutter web app so the semantics fix reaches
  `lala-next.cloud`;
- re-check `@chrome` against the deployed site after rollout.

### Live Recommendation Recovery Slice

What changed:

- Re-checked the live `lala-next.cloud` issue that initially looked like a
  Chrome-plugin problem and confirmed the backend API itself was healthy.
- Direct live checks showed `/readyz`, `/api/v1/places`, and `/api/v1/weather`
  were responding successfully while one browser tab had fallen into a
  recommendation-error state.
- A live tab reload restored the recommendation rail immediately, which pointed
  to weak frontend recovery rather than a persistent service outage.
- Updated [apps/flutter_app/lib/main.dart](/Users/geondongkim/LALA-next/apps/flutter_app/lib/main.dart)
  so the initial `getPlaces` load retries once before surfacing the user-facing
  recommendation failure when the app has no previously loaded places.
- Added focused regression coverage in
  [apps/flutter_app/test/widget_test.dart](/Users/geondongkim/LALA-next/apps/flutter_app/test/widget_test.dart)
  for the single-retry helper.

Why it matters:

- A transient first-load hiccup should no longer strand the live web app in an
  empty recommendation state as easily.
- The fix targets the actual user-facing symptom rather than the browser
  tooling around it.

Verification:

- `flutter analyze lib/main.dart test/widget_test.dart`
- `flutter test test/widget_test.dart --plain-name 'single retry loader'`

### First-Load Latency Reduction Slice

What changed:

- Updated [apps/flutter_app/lib/main.dart](/Users/geondongkim/LALA-next/apps/flutter_app/lib/main.dart)
  so the first-load `health`, `readyz`, and `places` requests start together
  instead of waiting for each other in sequence.
- Slow or unanswered geolocation now falls back to the default recommendation
  load after a short grace period, so judges do not stare at an empty startup
  screen while the browser location prompt stalls.
- The follow-up `weather` and `intervention` requests now also start together
  once the recommendation rail is ready.
- Added focused regression coverage in
  [apps/flutter_app/test/widget_test.dart](/Users/geondongkim/LALA-next/apps/flutter_app/test/widget_test.dart)
  to keep the startup path parallelized.

Why it matters:

- Live API timing showed the old first-load path stacked several ~3-4 second
  calls, which made the first recommendation surface feel much slower than the
  backend needed to be.
- The homepage can now reach its first useful state much closer to the slowest
  single core request instead of the sum of three sequential requests.
- Browser geolocation delays no longer block the first default recommendation
  surface for the whole timeout window.

Verification:

- `flutter analyze lib/main.dart test/widget_test.dart`
- `flutter test test/widget_test.dart --plain-name 'loads core startup requests in parallel'`
- `flutter test test/widget_test.dart --plain-name 'slow location startup falls back to default recommendations first'`
- `curl -sS -o /dev/null -w 'health %{time_total}\n' https://api.lala-next.cloud/healthz`
- `curl -sS -o /dev/null -w 'ready %{time_total}\n' https://api.lala-next.cloud/readyz`
- `curl -sS -o /dev/null -w 'places %{time_total}\n' 'https://api.lala-next.cloud/api/v1/places?lat=36.9940&lng=127.1128&radius_m=3000&category=all&include_scores=true'`

### Queryless Root Freshness Slice

What changed:

- Updated [apps/flutter_app/web/vercel.json](/Users/geondongkim/LALA-next/apps/flutter_app/web/vercel.json)
  so the deployed root document `/` and `/index.html` use `Cache-Control:
  no-store` instead of relying only on the broader revalidation rule.
- Added matching no-cache meta tags to
  [apps/flutter_app/web/index.html](/Users/geondongkim/LALA-next/apps/flutter_app/web/index.html)
  as a secondary guard for the app shell document.

Why it matters:

- Judges and first-time visitors should be able to open
  `https://lala-next.cloud` directly without appending a cache-busting query
  string just to fetch the latest deployed Flutter shell.
- The change keeps the HTML entry document fresh while leaving the rest of the
  asset caching behavior unchanged.

Verification:

- `curl -sSI https://lala-next.cloud/`
- `curl -sSI 'https://lala-next.cloud/?qa=root-check'`

### Instant Startup Recommendations Slice

What changed:

- Updated [apps/flutter_app/lib/main.dart](/Users/geondongkim/LALA-next/apps/flutter_app/lib/main.dart)
  so the deployed root experience no longer waits for the live `places`
  response before showing a recommendation rail.
- Added a bundled official-data-backed startup recommendation set around the
  default Suwon coordinates and wired the dashboard to use it whenever the live
  place payload is still empty.
- Added focused regression coverage in
  [apps/flutter_app/test/widget_test.dart](/Users/geondongkim/LALA-next/apps/flutter_app/test/widget_test.dart)
  to prove that the first paint shows real places instead of a `0곳` empty
  state, and that the UI swaps over to live API places once they arrive.

Why it matters:

- Judges opening `https://lala-next.cloud/` should never interpret the homepage
  as broken just because the first network round-trip is still in flight.
- The map page now has a reliable first useful state even before the live
  recommendation fetch completes.

Verification:

- `cd apps/flutter_app && flutter analyze lib/main.dart test/widget_test.dart`
- `cd apps/flutter_app && flutter test test/widget_test.dart --plain-name 'shows bundled startup recommendations before live places resolve'`
- `cd apps/flutter_app && flutter test test/widget_test.dart --plain-name 'loads core startup requests in parallel'`

### Nationwide Region and Culture Expansion Slice

What changed:

- The nationwide rollout plan was refreshed in
  [nationwide-expansion-plan.md](/Users/geondongkim/LALA-next/docs/operations/nationwide-expansion-plan.md).
- The backend already has a shared region-catalog direction and nationwide
  batching flags around TourAPI, KCISA, and KOPIS.
- Nationwide preview checks were run for KCISA and KOPIS, and TourAPI was
  checked successfully by individual area-code slices after a bulk timeout.

Why it matters:

- Nationwide expansion is now treated as a real backend path, not just a docs
  idea.
- The blocker is no longer schema shape; it is source coverage and rollout
  cadence.

Follow-up:

- run nationwide place-score preview after the broader place/culture sweep;
- apply score and RAG only after preview quality is acceptable.

### Card-Spending Coverage Inventory Slice

What changed:

- Added
  [card-spending-source-inventory.md](/Users/geondongkim/LALA-next/docs/operations/card-spending-source-inventory.md)
  to track free public regional card-spending sources.
- Classified sources into `drop-in`, `small-adapter`, and
  `operationally-unsuitable`.
- Confirmed the current best next candidates as Seoul, Sejong, and Gyeongnam.
- Explicitly excluded Busan from the default next wave because the public metric
  is monthly daily-average rather than direct monthly total.

Why it matters:

- Card-spending expansion is now tracked as a source-onboarding problem, not as
  an undefined future task.
- The repo has a concrete shortlist for the next adapter work.

Follow-up:

- obtain one sample file each for Seoul, Sejong, and Gyeongnam;
- map real columns against `card_spending_ingest.py`;
- keep non-approved regions null for `local_spending_score`.

### Nationwide Fallback Score Policy Slice

What changed:

- Added
  [nationwide-fallback-score-plan.md](/Users/geondongkim/LALA-next/docs/operations/nationwide-fallback-score-plan.md)
  to document how nationwide recommendations should work when card coverage is
  partial.
- The plan keeps `local_spending_score` null where no approved regional card
  source exists.
- The fallback path is defined in terms of already supported public signals:
  TourAPI, KCISA, KOPIS, weather observations, franchise identity, and review
  quality where available.

Why it matters:

- Nationwide rollout is no longer blocked on nationwide card data.
- The repo now has a documented answer for "how do we score regions without
  card-spending coverage?"

Follow-up:

- preview score output in card-null regions;
- validate that the existing null-preserving score contract is enough before
  changing any formula.

### Sample Collection Guide Slice

What changed:

- Added
  [card-source-sample-collection-guide.md](/Users/geondongkim/LALA-next/docs/operations/card-source-sample-collection-guide.md)
  as a user-facing operator guide for collecting Seoul, Sejong, and Gyeongnam
  sample files.
- Documented the exact portals, likely account/application requirements, local
  storage paths, and handoff format expected by Codex.

Why it matters:

- The user's manual part of the nationwide card-source workflow is now captured
  in repo docs instead of chat only.

## 2026-06-23

### Shared-Dev Public-Data Refresh Slice

What changed:

- Shared dev recorded guarded apply evidence for KCISA, KOPIS, weather refresh,
  Gyeonggi card-spending file ingest, place-score batch, and RAG regeneration.
- The backlog and verification docs now reflect that these guarded apply paths
  record `ops.job_runs` rows and feed the current DB-backed baseline.

Where to look:

- [completion-backlog.md](/Users/geondongkim/LALA-next/docs/operations/completion-backlog.md)
- [verification.md](/Users/geondongkim/LALA-next/docs/operations/verification.md)

Why it matters:

- Shared-dev evidence moved from partial ingest support to repeatable guarded
  operation with observable job history.

## 2026-06-19

### Terraform-First Azure Migration Slice

What changed:

- The repo completed the Terraform-first Azure transition planning and
  validation lane for dev/prod structure, workflows, and verification docs.

Where to look:

- [azure-migration-status.md](/Users/geondongkim/LALA-next/docs/operations/azure-migration-status.md)
- [azure-dev-deployment.md](/Users/geondongkim/LALA-next/docs/operations/azure-dev-deployment.md)

Why it matters:

- Infra changes now have a documented source of truth instead of living only in
  shell history or CI runs.

## Next Logging Habit

From this point on, each meaningful slice should leave:

1. one updated strategy/status doc;
2. one short dated entry here;
3. verification notes in
   [verification.md](/Users/geondongkim/LALA-next/docs/operations/verification.md)
   if the operator command or rollout proof changed.
