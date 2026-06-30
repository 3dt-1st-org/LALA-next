# On-Premises Post-Contest Auth Transition

Last updated: 2026-06-26 KST

During the contest/review window, LALA intentionally allows public reviewer
traffic without a sign-in ceremony. That state is operationally explicit:
`LALA_PUBLIC_CONTEST_ACCESS=true`.

After the contest window closes, the team must turn this into a normal
authenticated API edge instead of leaving the review bypass enabled.

## Current Review Setting

- Public API: `https://api.lala-next.cloud`
- Runtime env file: ignored `runtime/onprem-api.env`
- Review access flag: `LALA_PUBLIC_CONTEST_ACCESS=true`
- Normal data path: PostgreSQL/PostGIS/pgvector, not mock/demo data
- Static snapshot fallback: `LALA_STATIC_SNAPSHOT_FALLBACK=false`

The review flag is not a data fallback. It only relaxes client authentication
for the public contest surface.

## Disable Review Access

1. Announce a short maintenance window to the team.
2. Confirm the intended client authentication method for the next stage:
   Kakao login, signed reviewer token, API key, or another approved route.
3. Edit ignored `runtime/onprem-api.env`.
4. Change:

   ```dotenv
   LALA_PUBLIC_CONTEST_ACCESS=false
   ```

5. Add only the required auth values as environment variables. Do not commit
   them to the repository.
6. Restart the API LaunchAgent:

   ```bash
   launchctl kickstart -k gui/$UID/cloud.lala-next.api
   ```

7. Verify readiness:

   ```bash
   curl -fsS https://api.lala-next.cloud/readyz
   scripts/unix/check_onprem_runtime.sh --require-live-ai --require-live-speech
   ```

8. Run authenticated route smokes with the approved client credential.

## Acceptance Criteria

- `/readyz` still reports DB-backed data.
- `/readyz.data.checks.static_snapshot_fallback` remains `disabled`.
- `/readyz.data.checks.public_contest_access` no longer reports `enabled`.
- Authenticated Flutter web and mobile flows can load places, weather, docent
  scripts, and speech.
- Unauthenticated route behavior is intentional and documented.

## Rollback

If the auth transition blocks contest judging or the next review window, restore
the last known-good ignored env file or temporarily set:

```dotenv
LALA_PUBLIC_CONTEST_ACCESS=true
```

Then restart `cloud.lala-next.api` and rerun the public smoke checks. Keep the
rollback window short and record the reason in the operations log.
