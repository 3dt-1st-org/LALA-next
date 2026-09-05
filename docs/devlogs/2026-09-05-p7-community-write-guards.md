# Devlog — P7 community write throttling + strict WebSocket chat input (2026-09-05)

Base: `4111feb5b2a9df5fffe47a209b1e5a66ce6dce8e` (Draft PR #187 integration head), Orca
worktree `p7-community-write-guards-20260905`. No production access, no live provider
calls, no DB writes/migrations, no deploy, no browser/simulator, no secret/env reads.

## Objective (code-now scope only)

1. Bounded per-actor/per-client rate limits on authenticated community and chat
   mutation paths, including inbound WebSocket chat frames.
2. Actually validate every inbound WebSocket chat JSON object with the existing
   `ChatMessageIn` Pydantic schema, including the 4000-character cap.

Explicitly NOT built here (recorded as follow-ups, not half-built): idempotency keys
for community/chat writes, one-time WebSocket handshake tickets, room-membership
authorization, cross-instance broadcast (pub/sub), moderation UI, real Logto login
flows.

## Design

- Reused the single existing bounded seam in `apps/api/app/core/rate_limit.py`:
  extracted the shared fixed-window core (`_window_allows` + `_hashed_key`) and added
  two enforcement functions beside the unchanged Local Signals one. No new
  dependency, no second limiter. `enforce_local_signals_rate_limit` and
  `enforce_public_contest_paid_route_limit` keep their exact public error contracts.
- New `enforce_community_write_rate_limit(request, ...)` for HTTP mutations:
  429 / `COMMUNITY_RATE_LIMITED` / "Too many community requests. Please retry shortly."
  / retryable=true, delivered through the normal bounded API error envelope.
  Deliberately not the paid-route or Local Signals code/message.
- New `enforce_chat_message_rate_limit(...)` for WebSocket frames: no per-frame
  `Request` exists, so the caller passes the connection's stable client key
  (resolved once at handshake). Raises the bounded `ApiError` contract
  (429 / `RATE_LIMITED` / chat-specific message) which the frame handler converts to
  exactly one error frame.
- Internal window keys remain one-way SHA-256 hashed (`route:actor:client`) exactly
  like the Local Signals seam — no raw issuer/subject/IP is ever stored in limiter
  state, logs, or error payloads. Nothing new logs identity, token, IP, or body
  content.
- Auth before throttle: enforcement is the first statement of each handler body, so
  `require_oauth_identity` (dependency) always runs first; unauthenticated 401s never
  consume or touch an actor window, and a throttled request never reaches the
  service/repository. Same ordering on the WebSocket: handshake auth runs before the
  loop, then per-frame validate → throttle → persist.

## Documented route limits (per actor+client, per 60s fixed window)

| Route key | Limit/min | Path |
|---|---|---|
| `community-post-create` | 10 | POST /api/v1/community/posts |
| `community-comment-create` | 20 | POST /api/v1/community/posts/{id}/comments |
| `community-like-toggle` | 60 | POST /api/v1/community/posts/{id}/like |
| `community-follow-toggle` | 30 | POST /api/v1/community/follows |
| `community-report-create` | 5 | POST /api/v1/community/posts/{id}/reports |
| `community-chat-room-create` | 5 | POST /api/v1/community/chat/rooms |
| `community-chat-message` | 30 | WS frames on /api/v1/community/chat/rooms/{id}/ws |

Magnitudes mirror the Local Signals vocabulary (create 10 / comment 20 / reaction 60 /
report 5). Read routes stay unthrottled at this seam. Limits are module constants and
are pinned by test.

## Strict WebSocket input (`ChatMessageIn`)

- `extra="forbid"` added; a `body` field validator rejects whitespace-only bodies.
- Handler order per frame: parse JSON (fail → `INVALID_JSON`) → require a JSON
  object (arrays/scalars/strings → `INVALID_MESSAGE`) →
  `ChatMessageIn.model_validate` (missing/wrong-type/whitespace/over-4000/unknown
  fields → `INVALID_MESSAGE`) → rate limit (→ `RATE_LIMITED`) → persist → broadcast.
- Every rejection answers one bounded error frame with a fixed help message
  ("Message must be a JSON object with a body of 1-4000 characters.") that never
  echoes payload, token, or identity content; nothing is persisted or broadcast; the
  connection deterministically stays open and keeps answering.
- Boundary bodies (1 char, exactly 4000 chars, padded whitespace-inclusive) persist
  byte-exactly as before.

## OpenAPI

`_add_community_write_error_responses` documents 429 (`ApiErrorEnvelope`) on exactly
the six community mutation POSTs. GETs and Local Signals paths are untouched
(Local Signals keeps its own distinct 429 description; `setdefault` ordering
guarantees no churn).

## Tests (`apps/api/tests/test_community_write_guards.py`, +30)

- Parametrized exact-limit boundary for all six HTTP mutation families: first call
  200, next 429 with the bounded envelope (ok=false, retryable=true, request_id),
  and the counting service records exactly one call — rejection never advances it.
- Auth-before-throttle: unauthenticated POSTs return `USER_AUTH_REQUIRED` with the
  limiter spy never invoked, and the actor's window is intact afterwards.
- Actor isolation (distinct subject → fresh window) and client isolation
  (distinct `CF-Connecting-IP` → fresh window) at HTTP and seam level.
- Seam tests: exact 429 error contracts, actor/client scoping, and proof that no
  raw issuer/subject/IP appears in stored window keys (one-way hashing).
- WS negative matrix (9 frames: malformed JSON, array, string, number, missing
  body, whitespace-only, wrong type, unknown field, 4001 chars): one bounded error
  frame each, zero persistence, zero broadcasts (delegating broadcast spy).
- WS boundary persistence (1 / 4000 / padded), throttle window (limit=2 → third
  frame throttled, connection stays open and keeps answering, error frame contains
  no payload echo), WS actor isolation, failed handshake (1008) does not consume
  the message window.
- `ChatMessageIn` wire-contract unit test; documented-limits pin test; OpenAPI 429
  presence/description and read-route absence + Local Signals non-churn test.

Shared limiter state is reset by the existing autouse `isolate_db_env` conftest
fixture, so test order is irrelevant. No existing test was weakened, deleted,
skipped, or loosened.

## Compatibility boundaries

- Local Signals behavior and error contract unchanged (suite green, contract tests
  untouched). Public-contest paid-route limiter behavior unchanged.
- The Logto/OAuth identity path is untouched. The `?token=` WebSocket query-token
  mechanism is intentionally unchanged this checkpoint and is honestly recorded as
  a separate security follow-up (tokens in URLs can leak via logs/referrers; the
  replacement is one-time WS tickets, out of scope here).
- Successful response envelopes, service/repository contracts, and chat message
  persistence shapes are byte-identical; only previously-unvalidated WS frames and
  over-limit writes change behavior (rejection).

## Honest limitation

The limiter is a process-local fixed window: a tested, replaceable seam — NOT
multi-instance production enforcement. Each API replica keeps its own windows, so
N replicas multiply the effective limit and windows reset on deploy/restart.
Production enforcement needs the existing edge/distributed limiter swapped in
behind these same functions (contract-preserving).

## Verification

- `uv run pytest apps/api/tests -q` → **2055 passed**, 1 pre-existing warning, 0 failed.
- `uv run ruff check .` → All checks passed.
- `uv run ruff format --check .` → 460 files already formatted.
- `uv run pre-commit run --all-files` → all hooks Passed (incl. Detect secrets).
- `git diff --check 4111feb5b2a9df5fffe47a209b1e5a66ce6dce8e..HEAD` → clean.

## Remaining P7 gates (separate follow-ups)

1. Distributed/edge rate limiting behind the same seams (multi-instance enforcement).
2. One-time WebSocket handshake tickets replacing the `?token=` query mechanism.
3. Room-membership authorization for chat (join/leave, membership-checked broadcast).
4. Idempotency keys for community/chat writes (duplicate-submission protection).
5. Cross-instance chat broadcast (pub/sub) — current fan-out is in-process only.
6. Moderation UI/workflows for reports.
7. Real Logto login integration end-to-end.
