# On-Premises Browser and iOS Revalidation

Last updated: 2026-06-26 KST

Run this checklist after any change to Cloudflare Tunnel, API base URL, live
AI/Speech flags, database restore, or public contest access.

## API Preflight

```bash
scripts/unix/check_onprem_runtime.sh \
  --require-live-ai \
  --require-live-speech \
  --require-data-freshness

scripts/unix/smoke_api_matrix.sh \
  --base-url https://api.lala-next.cloud \
  --profile deploy \
  --timeout 30
```

Acceptance:

- DB-backed data is active.
- PostGIS is configured.
- Static snapshot fallback is disabled.
- Live AI and live speech are enabled when the review build expects them.

## Desktop Browser

Open:

```text
https://lala-next.cloud
```

Checklist:

- The app asks for location permission or shows the manual region selector when
  permission is unavailable.
- Places appear from the API-backed dataset around the selected/current area.
- Individual markers appear at normal zoom; clustering appears only when marker
  density makes it useful.
- Weather, PM10, and PM2.5 appear after the location or manual region is set.
- The bottom sheet shows the selected place, docent summary, and action buttons
  without a floating card blocking the map.
- Score/reason details stay hidden until the user opens them.
- No user-facing text says demo mode, mock data, or public demo mode.
- Korean mode shows Korean labels only; English mode shows English labels only
  where data is available.

## Mobile Browser

Use a narrow viewport or a physical mobile browser:

- Repeat the desktop checklist.
- Confirm top chips, carousel, bottom sheet, and voice controls fit without
  clipped text.
- Confirm location permission and manual region selection are reachable without
  desktop-only affordances.

## iOS Simulator

Run the Flutter app or iOS web wrapper used by the team:

```bash
scripts/unix/verify_flutter_app.sh
```

If the simulator target is already booted, open the app and verify:

- Location permission prompt and fallback region selector.
- Place markers and clustering behavior.
- Weather/air quality display.
- Docent script quality for at least three categories: place, food, event.
- Speech playback from the live speech endpoint.

## Evidence To Capture

For handoff, capture:

- `/readyz` snapshot without secret values.
- API matrix summary.
- Desktop browser screenshot.
- Mobile/narrow screenshot.
- iOS Simulator screenshot or short recording.
- Any known issue with owner and next action.
