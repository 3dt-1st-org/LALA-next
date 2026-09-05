# P7 durable chat controls — devlog and runbook (Session B)

- Date: 2026-09-05/06
- Branch: `geondongkim/feature-community-durability-20260905` (child of Draft #187
  `geondongkim/fix-runtime-plan-search-20260904`)
- Base: `b5455a942b9af98160fb6c0df4fbc4a01fcda163` (#187 head at start)
- Scope owner: OpenCode GLM-5.3 (max variant), Session B of the 2026-09-05 resume plan
- Status: CODE_VERIFIED (unit/widget/API tests, lint, migration rehearsal on a
  disposable local DB). RUNTIME_UNVERIFIED against a live multi-instance
  deployment; no production DB apply, no main merge.

## What this closes

From the #193 integration ledger the remaining P7 gaps were: durable
idempotency, room membership authorization, WebSocket ticket/origin policy and
multi-instance fanout. This lane implements all four, plus two latent defects
found on the way:

1. The app's WebSocket send frame carried `{"type": "message", ...}` while the
   server schema is `extra="forbid"` — every app ws send would have been
   rejected with INVALID_MESSAGE at runtime.
2. `CommunityService.create_post` → `_post_payload` required `author_user_id`,
   which the plain insert row never carried (runtime 500 on the REST path).

## Reserved migration

- Number: **068** (highest existing was `067_community_post_reports.sql`)
- File: `sql/canonical/068_community_chat_durable_controls.sql` (additive,
  idempotent; re-apply verified in rehearsal)
- Manifest updates required by the migration contract, done in the same change:
  `apps/api/app/services/canonical_sql.py` (baseline tuple),
  `apps/api/tests/test_canonical_sql.py`, and the tail assertion in
  `apps/api/tests/test_local_signals_contract.py`. Shared-file disclosure: these
  two test files belong to other lanes' contracts; the change is the one-line
  baseline extension mandated by the migration contract.

## Authorization model (criterion 1)

- `chat_rooms.visibility` ∈ {public, private}, default **public** — existing
  rooms and the guest-readable public-room semantics are preserved.
- `chat_rooms.created_by_issuer/subject` (nullable, FK → identity.users ON
  DELETE SET NULL) + `community.chat_room_members` (PK room+member,
  role owner|member, FK cascade) make access explicit.
- One SQL predicate (`_ROOM_ACCESS_SQL`) guards **room list, history, REST send,
  guarded WS insert** and the ws-ticket access check: public rooms for anyone;
  private rooms only for the owner anchor or an explicit member row.
- Identity comes only from verified OAuth (`require_oauth_identity` /
  ticket-bound issuer/subject). No client-supplied identity is trusted; the
  optional client idempotency key never contributes to identity.
- No-leak guarantee: denial for private rooms is the same 404 code/body as an
  unknown room across list/history/send/ticket; the ws handshake rejects with a
  content-free 1008 both for missing and inaccessible rooms.
- `POST /rooms/{room_id}/members` (owner-only, private rooms only) grants
  membership by internal user UUID, mirroring the follows wire policy.

## Durable idempotency (criterion 2)

- Table `community.idempotency_keys`, PK `(scope, actor_issuer, actor_subject,
  idempotency_key)`; scopes `community.chat.message.create` and
  `community.post.create`.
- Wire: `Idempotency-Key` header on `POST /community/posts` and
  `POST /community/chat/rooms/{room_id}/messages` (1–200 printable chars;
  malformed → deterministic 400 `IDEMPOTENCY_KEY_INVALID`). WebSocket frames may
  carry an optional `idempotency_key` field with the same scope.
- Canonical payload hash: sha256 over key-sorted compact JSON
  (`{"room_id","body"}` for messages, `{"title","body","tags"}` for posts), so
  field order never changes the hash.
- Protocol (one transaction): claim key with placeholder response → guarded
  insert → store real response → `pg_notify`. Concurrent same-key writers
  serialize on the PK: the loser replays the committed response verbatim
  (byte-identical, survives restart — the store is Postgres, not a process-local
  dict); same key with a different canonical payload → deterministic 409
  `IDEMPOTENCY_KEY_CONFLICT`; business failure (room inaccessible) releases the
  claim so the key is never burned.
- TTL/retention: rows expire after **24 h**. The purge runs scope-wide
  (`expires_at < now()`, indexed) on every idempotent write, so retention is
  bounded even for actors who never write again. The actor FK cascades on
  account deletion — no replay copies of a deleted account's writes survive.

## WebSocket auth (criterion 3)

- Bearer tokens are no longer accepted on the ws URL (`?token=` is gone; the
  client never puts a bearer in a URL). The client exchanges its bearer over
  REST: `POST /rooms/{room_id}/ws-ticket` (OAuth, rate-limited 30/min/actor)
  returns a `secrets.token_urlsafe(32)` ticket valid **60 s**; only its sha256
  digest is stored (`community.chat_ws_tickets`).
- Handshake order (all before `accept()`): ticket presence/length → origin
  policy → atomic single-use claim (`UPDATE ... SET used_at=now() WHERE
  used_at IS NULL AND expires_at > now() RETURNING ...`) → room binding check →
  access re-check → connection caps. A claimed ticket never works again on any
  instance; used/expired rows purge on each issuance.
- Origin policy: no Origin (native clients) allowed; browser Origin must be
  same-host (Origin netloc == Host header) or exactly match the existing
  CORS allowlist. No new configuration surface was added.
- REST fallback: `POST /rooms/{room_id}/messages` always works; if the ticket
  store is unavailable the handshake closes 1013 (retry later) and clients
  continue over REST.
- Bounds: frame ≤ 8192 bytes (`FRAME_TOO_LARGE`), 30 frames/min/actor+client
  (unchanged), idle timeout 600 s → normal 1000 close, ≤200 sockets/room,
  ≤8 sockets/actor (1013 when exceeded).

## Multi-instance behavior (criterion 4)

- Writers emit `pg_notify('community_chat_fanout', {room_id, message_id})`
  **inside the message transaction**, so a notification always corresponds to a
  committed message; payloads carry ids only (bounded far below the 8000-byte
  NOTIFY limit).
- Each API instance lazily starts one listener thread on the first accepted ws
  connection (only when `DB_DSN` is configured): LISTEN → `select` loop →
  fetch the wire-shaped message through the service → schedule the local
  broadcast on the serving event loop.
- Delivery dedup: `ConnectionManager.broadcast_once` claims message ids in a
  bounded (256) in-process set before broadcasting; the local fast path and the
  NOTIFY path converge on this single claim point on the event loop, so a
  message is never delivered twice to local sockets. Postgres remains the only
  durable truth; the set is a delivery optimization, not durability.
- Honest degradation: listener down ⇒ cross-instance realtime pauses until
  reconnect (bounded backoff, `connection.cancel()` for prompt stop; lifecycle
  lock guarantees at most one listener thread); messages stay committed and
  readable via REST, and clients recover by refreshing history on reconnect.
  No Redis was introduced; the in-memory registry is never represented as
  cross-instance delivery.

## Runtime client (criterion 5)

- `ChatWsClient` connects through a URI provider: every (re)connect fetches a
  fresh single-use ticket; handshake failures surface via `channel.ready` with a
  per-connection termination guard; provider failures never auto-retry —
  permission denial (404/403) stops realtime without probing room existence,
  while socket terminations keep the exponential backoff.
- `ChatRoomPage`: REST fallback send when offline; idempotency keys are stable
  across manual retries of the same draft (server-side dedup makes a retried
  send idempotent); messages dedup by id across REST/WS/reconnect overlap;
  reconnect triggers a silent history refresh; permission denial shows
  non-retryable guidance, transient failures keep the draft with a retry bubble.

## Account-deletion lifecycle (controller review round)

- Creator columns are `ON DELETE SET NULL`; no non-null CHECK exists, so
  account deletion can never be blocked by chat rooms. After owner deletion a
  private room stays private, remaining member rows keep explicit access, and a
  room with no remaining accessors becomes inert (invisible to everyone, never
  leaked to public).
- Idempotency rows FK-cascade on actor deletion; expired rows purge scope-wide.
- `ChatFanoutBridge.stop()` cancels the blocking select under a lifecycle lock
  (no overlapping listeners) and `handle_notification` is exception-safe.

## Migration rehearsal (disposable DB, no production credentials)

Docker was unavailable; a throwaway PostgreSQL 16 cluster was created with
`initdb` on a unix socket (port 5544, user `p7rehearsal`), never touching the
host's 5432 service, then shut down and deleted. Because the local Homebrew
Postgres lacks postgis/pgvector, the full canonical baseline could not run;
the community chain (005, 060, 061, 067, **068**) was applied instead and 068
was re-applied to prove idempotency. Rehearsed and asserted
(`output/local/p7_rehearsal.sql`, run with `ON_ERROR_STOP`):
public default preserved; outsider list predicate sees exactly the public
rooms; ticket claims exactly once; duplicate idempotency key hits the PK
(unique_violation); account deletion satisfies every lifecycle assertion
(creator SET NULL, room stays private, membership + idempotency rows cascade,
remaining member retains access); expired tickets purge; `pg_notify` delivered
cross-session.

## Deploy order and rollback

1. Merge child PR → #187 (no main merge, no deploy).
2. When #187 deploys: apply canonical SQL (000..068) to the target database
   during the release window using the guarded apply tool
   (`ALLOW_CANONICAL_SQL_APPLY=1` + confirm text) — 068 is additive and
   idempotent; no data backfill needed (existing rooms become public by
   default, which matches their current semantics).
3. Rollback (database): 068's objects can be dropped in a dedicated reversal
   migration (`chat_ws_tickets`, `idempotency_keys`, `chat_room_members`,
   the added columns/constraints/indexes) — the API degrades to 503 on the new
   endpoints until the app is rolled back to the previous image; existing
   public chat semantics never depended on 068.
4. Order note: deploy API before clients; old clients that still send
   `?token=` get a 1008 close and fall back to REST reads after upgrade.

## Evidence

- API: focused community suites (chat 66 + guards 30 + idempotency 9 + canonical
  16 + community 37) and the full suite **2,470 passed**; `ruff check`/`format`
  clean; OpenAPI compat tests green (new paths are additive).
- Flutter app: `flutter analyze` clean; community suites 65 passed; full suite
  **1,189 passed**.
- Reference client: 49 tests passed (dart test).
- Migration rehearsal: see above (real disposable Postgres 16).
- Not exercised: live multi-instance ws fanout, real Logto-authenticated
  handshake, production apply. Those remain RUNTIME_UNVERIFIED, reported as
  remaining work, not external blockers.

## Shared-file disclosure (beyond exclusive lanes)

- `apps/api/app/services/canonical_sql.py` — migration manifest line (mandated).
- `apps/api/tests/test_canonical_sql.py`, `test_local_signals_contract.py` —
  baseline assertions extended by one entry each.
- `apps/api/app/core/openapi.py` — `COMMUNITY_MUTATION_PATHS` gained the three
  new POST paths so the 429 documentation contract stays correct.
- `clients/flutter/lib/lala_api_client.dart` (+ its test) — controller-approved
  community methods (tickets, REST send, ticket-only URI).
- `.secrets.baseline` — pre-commit detect-secrets refresh only.
- No changes were needed in `core/config.py` (no new settings; TTLs are
  documented module constants).

## Remaining (implementable, not externally blocked)

- Membership management UI (invite flow) beyond the owner-only REST grant.
- Private-room membership revocation/leave and moderation tooling (explicitly
  out of this lane's scope).
- Multi-instance ws fanout against a real multi-node deployment + load test.
- Optional: move ws ticket TTL / connection caps into settings when a
  deployment needs them tuned.
