# Naver Dynamic Map migration plan

Last updated: 2026-08-31

## Goal

Replace the Kakao JavaScript map surface with Naver Dynamic Map while keeping
LALA's place, clustering, viewport-query, location, language, and navigation
contracts provider-neutral. The map must show real provider tiles or an honest
unavailable state; a mock or decorative map is not a passing path.

## Operator setup

The following console work has been completed for the development application:

- Dynamic Map is enabled.
- Allowed URLs include `lala-next.cloud`, `localhost`, and `127.0.0.1`.
- `NAVER_MAP_CLIENT_ID` is present in the root developer `.env.local`.

The Naver Cloud "representative account" choice has no Flutter SDK or runtime
effect. It remains an account ownership/administration decision.

Before a preview or production hostname is used, add that exact URL to the
Dynamic Map allowlist. Do not broaden the allowlist with wildcards merely to
make a build pass.

## Credential boundary

| Value | Consumer | Client bundle |
| --- | --- | --- |
| `NAVER_MAP_CLIENT_ID` | Naver Dynamic Map JS loader | Required; URL-restricted public build configuration |
| `NAVER_CLIENT_ID` | Governed server-side Naver Search API adapter | Forbidden |
| `NAVER_CLIENT_SECRET` | Governed server-side Naver Search API adapter | Forbidden |

The guarded build wrapper resolves the map client id in this order:

1. Operator-specified SSM Parameter Store name.
2. Restricted AWS Secrets Manager build entry.
3. Explicitly selected trusted dotenv, sourced in an isolated subshell.

Only the map client id, public API base URL, and build SHA reach Flutter. The
wrapper must fail closed rather than substitute a fake value.

## Architecture

```text
Flutter screen
  -> buildLalaMapView (provider-neutral contract)
     -> Web: same-origin iframe /naver-map-embed.html
     -> iOS/Android: WebView https://lala-next.cloud/naver-map-embed.html
        -> Naver Maps JS v3 (ncpKeyId)
        -> HTML markers and provider controls
        -> cameraIdle / placeTap bridge messages
  -> LalaMapCamera / LalaMapBounds / LalaMapPlace
  -> existing viewport API, clustering, selection, and cross-tab state
```

Web bridge messages are accepted only from the same origin and must carry both
the `lala-naver-map` source marker and the per-frame bridge ID issued by Flutter.
Native messages use the same bridge-ID contract. Native WebView navigation is
limited to the LALA embed host and the Naver SDK host.

## Provider conversion

LALA's stable map level is `2..10`, where a larger number means a wider view.
Naver zoom uses the opposite direction. The only conversion is:

```text
naverZoom = 19 - lalaLevel
lalaLevel = clamp(19 - round(naverZoom), 2, 10)
```

Examples: level 2 -> zoom 17, level 6 -> zoom 13, level 10 -> zoom 9. Backend
query and pin-first clustering code continues to use the LALA level contract.

## Product and policy requirements

- Keep Naver logo and map-data copyright controls visible.
- Preserve category colors, selected-place labeling, place-tap behavior, and
  pin-first clustering.
- Map camera idle must return center, level, and SW/NE bounds.
- KO, EN, JA, and ZH map language inputs map to Naver's supported language
  query values; the existing app locale remains the source of truth.
- Onboarding preview is read-only. The main map remains interactive.
- Missing configuration, SDK load failure, and authorization failure render an
  honest unavailable state and never a fake tile surface.

## Delivery order

1. Rename provider-specific Flutter value/bridge types to `LalaMap*`.
2. Add the Naver same-origin embed and native/web bridges.
3. Migrate build, CI, deployment, and managed-configuration names.
4. Lock credential isolation, bridge origin checks, attribution controls, and
   zoom conversion with tests.
5. Build Flutter web with the registered local URL and capture a real Naver map
   with real API place pins.
6. Open a Draft PR. Do not deploy or merge on unit tests alone.
7. After review approval, merge and deploy the embed page, then rebuild iOS and
   Android so their remote WebView path can use the new page.
8. Capture iPhone 17 Pro and responsive web evidence for map load, location
   recovery, viewport refresh, marker selection, clustering, and all supported
   app languages.

## Acceptance matrix

| Gate | Evidence |
| --- | --- |
| Static | Flutter analyze/tests, API safety contracts, shell build-wrapper test, pre-commit |
| Web build | Release bundle contains `NAVER_MAP_CLIENT_ID`; no server secret identifier or value |
| Local web | Real Naver tiles, visible attribution, real place pins, distinct camera/selection states |
| Native | Deployed embed loads on iPhone 17 Pro; place taps and camera bounds return to Flutter |
| Failure | Missing/invalid id produces honest unavailable UI without mock tiles |
| Rollback | Revert the migration PR and redeploy the previous known-good frontend; no DB migration is involved |

## Non-goals

- This change does not replace Naver Search API ingestion or its server
  credentials.
- It does not change Logto, Geolocator/browser-location, place ranking, RAG,
  Local Signals, or production data.
- It does not authorize a production deployment, DNS change, paid provider
  call, crawl, or database mutation.
