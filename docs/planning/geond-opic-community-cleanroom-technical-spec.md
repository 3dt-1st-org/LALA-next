# Clean-Room Technical Specification - GEOND_OPIc Community Capabilities

> Status: planning specification, not an implementation claim
> Target: LALA-next community capability foundation
> Source examined: `/Users/geondongkim/GEOND_OPIc` on 2026-07-26
> Clean-room rule: this document derives observable product behaviour and data
> contracts. It does not copy source code, UI assets, prompt text, test fixtures,
> data, secret values, or OPIc-specific content from the source project.

## 1. Purpose and boundary

GEOND_OPIc's community is not merely a free-form bulletin board. Its useful
pattern is a **closed learning loop**:

```text
personal work -> explicit sharing decision -> peer response -> relevant next action
```

This specification extracts that pattern for a clean-room implementation. It
does **not** carry the OPIc learning domain, its personas, background-fact
vectors, Apache AGE graph implementation, GraphQL schema, React/React Native
components, legacy Flask routes, or presentation copy.

For LALA, the replacement loop must become:

```text
local discovery or saved plan -> explicit local signal -> trustworthy response
-> map / itinerary action -> aggregate, privacy-safe learning
```

The LALA-specific product design is in
[lala-community-local-experience-adaptation.md](lala-community-local-experience-adaptation.md).

## 2. Evidence ledger

The following is a behavioural inventory, not a porting checklist.

| Capability observed in GEOND_OPIc | Evidence read | Clean-room interpretation | Carry status |
| --- | --- | --- | --- |
| Posts, tags, comments and likes | `fastapi_app/community.py`, `app/models.py` | A small, authenticated contribution and peer-feedback surface | Carry with stronger safety model |
| Paginated latest feed, search, tag and author filters | `community.py::list_posts` | Cursor-based contextual feed instead of offset-only global feed | Carry, redesign contract |
| Popular/following/recommended/weakness feed variants | `fastapi_app/feed.py` | Several ranking intents can coexist, but each needs an explainable product purpose | Carry only as later contextual ranking |
| Follow relationship with SQL as durable source and graph mirror as derived index | `fastapi_app/follow.py`, `graph.py` | Durable relational relationship first; recommendation index is optional and rebuildable | Carry the principle, not Apache AGE |
| Explicit asset sharing with visibility controls | `community.py::create_share`, `CommunityShareItem` | Public contribution is an opt-in publication action, separate from an author's private work | Carry as a core invariant |
| Automatic masking of selected preview PII | `_anonymize_text`, `_prepare_share_preview` | Publication requires deterministic scrubbing plus server policy, never client-only masking | Carry and extend |
| Link-share capability with opaque token | `_ensure_link_token`, `get_share` | Unlisted sharing requires revocable, hashed capability tokens and audit | Carry later, with stronger token handling |
| Rooms and message history | `CommunityRoom`, `CommunityRoomMessage`, mobile screens | Synchronous discussion is a distinct product and moderation burden, not a prerequisite for useful community | Do not carry in LALA MVP |
| New-post WebSocket notice | `community.py::community_feed_ws`, web `Community.tsx` | Delivery acceleration only; correctness must remain REST/cursor based | Optional later |
| Community challenges | `community.py::community_challenges` | A progress layer can motivate contribution, but should never reward volume over trustworthy local usefulness | Defer |
| Experiment event logging | `experiment_user_logs`, implementation plan | Product changes require measurable outcomes and separately auditable events | Carry as privacy-safe analytics |

### 2.1 Source limitations and identified gaps

The inspected source does not establish production-grade moderation, block,
report, edit/delete, media lifecycle, translation, notification preference,
rate limiting, or durable multi-instance realtime semantics as a complete
system. A clean-room LALA design must treat all of these as required before
open public contribution, rather than silently inheriting their absence.

The source's recommendation graph is useful evidence that social signals can
be derived, but it is not proof that a graph database is required. LALA should
begin with PostgreSQL queries and a materialized/derived candidate table only
when measured demand warrants it.

## 3. Product capability model

### 3.1 Primary roles

| Role | May do | Must not receive by default |
| --- | --- | --- |
| Guest | Read curated public local signals and official place context | Identity, exact author location, private/shared-to-followers content, write controls |
| Authenticated traveller | Save, draft, publish, react, comment, report, block | Other users' private signals, hidden exact locations, moderation notes |
| Verified local contributor | Same as traveller plus a displayed provenance tier after review | Authority to declare a place safe/open/official without source support |
| Moderator | Review reports, resolve policy actions, redact/remove content | Raw third-party review corpus or secret source credentials |
| Service worker | Build allowed aggregate place signals and search indexes | Direct publication rights or the ability to bypass moderation |

Authentication is a prerequisite for create/react/comment/follow. LALA's
current competition access mode may permit anonymous **read** flows, but must
not make anonymous publication or social actions a normal code path.

### 3.2 Core objects

Names intentionally differ from the source project where the LALA domain is
different. UUIDs are external identifiers; no sequential IDs are exposed.

| Object | Purpose | Required fields | Lifecycle |
| --- | --- | --- | --- |
| `local_signal` | A traveller-authored, place- or route-scoped local observation, question, tip, or correction | `id`, author identity composite, `kind`, `status`, language, title/body, locality precision, created/updated timestamps | `draft -> submitted -> published`; may become `hidden`, `removed`, `deleted` |
| `signal_place_link` | Explicit connection of a signal to a LALA canonical place | signal id, `place_id`, relation, source confidence | active/revoked |
| `signal_route_link` | Optional link to a saved itinerary snapshot | signal id, opaque plan snapshot id | active/revoked |
| `signal_translation` | Human or machine translation derived from a published source language | signal id, target language, body, method, version, review state | pending/available/stale/rejected |
| `signal_reaction` | One idempotent lightweight response from a user | signal id, actor composite, reaction type | active/revoked |
| `signal_comment` | Threaded only one level deep feedback or answer | id, signal id, parent comment nullable, actor, language, body, status | submitted/published/hidden/removed/deleted |
| `follow_edge` | Opt-in author or local-guide follow relation | follower and followee identity composites, created time | active/revoked |
| `report_case` | A private policy report against a signal/comment/account | reporter, target type/id, reason code, optional safe note, status | open/triaged/actioned/dismissed |
| `moderation_action` | Immutable operator decision record | target, action type, reason code, actor role, timestamp | append-only |
| `publication_capability` | Revocable unlisted-link grant, if enabled | hashed token, resource id, expiry, revoked time, scope | active/expired/revoked |
| `community_event` | Privacy-safe product event for evaluation | actor pseudonym/digest, event type, context, timestamp | append-only with retention policy |

### 3.3 Signal kinds

The server validates a narrow enum. Free-form tags are secondary metadata, not
the primary safety control.

```text
place_tip            practical, time-bounded local tip
route_note           reflection attached to a plan or neighbourhood sequence
local_question       request for advice with a bounded locality
accessibility_note   wheelchair, stroller, sensory, language-access observation
seasonal_update      date/season-sensitive observation
correction           correction request for official/curated place information
local_story          opt-in cultural context; requires stronger review
```

`deal`, `promotion`, `business_ad`, and `review_dump` are not signal kinds.
Commercial disclosure is a separate, explicit property and may be rejected
under the initial policy.

## 4. Data ownership and schema boundary

LALA already deliberately separates two domains:

* `community.posts` and `community.place_mentions_weekly` are provider/ingest
  pipeline data. They must remain aggregate/controlled-source evidence.
* `community.user_posts`, `community.post_comments`, `community.post_likes`,
  `community.user_follows`, `community.chat_*` are the earlier user-generated
  community foundation.

Do not overload either set. Additive canonical SQL should introduce an
explicit `community.local_signals_*` family, or evolve the existing
`user_posts` family only through a reviewed migration. The recommended first
option preserves auditability and prevents an accidental query joining
traveller identity to third-party review ingestion.

### 4.1 Recommended additive tables

```sql
-- Illustrative shape only; use a numbered canonical migration when implemented.
CREATE TABLE community.local_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_issuer text NOT NULL,
  author_subject text NOT NULL,
  kind text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  source_language text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  locality_level text NOT NULL DEFAULT 'district',
  locality_code text,
  commercial_disclosure text NOT NULL DEFAULT 'none',
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (author_issuer, author_subject)
    REFERENCES identity.users (issuer, subject),
  CHECK (kind IN ('place_tip','route_note','local_question',
                 'accessibility_note','seasonal_update','correction','local_story')),
  CHECK (status IN ('draft','submitted','published','hidden','removed','deleted')),
  CHECK (locality_level IN ('none','province','city','district','place')),
  CHECK (commercial_disclosure IN ('none','visitor','owner_or_staff','paid_or_gifted'))
);
```

Supporting tables require these uniqueness and safety constraints:

* `local_signal_places(signal_id, place_id, relation)` is unique per tuple and
  references `travel.places(place_id)`, not a raw provider place string.
* `local_signal_reactions(signal_id, issuer, subject, reaction_type)` is unique
  per actor/type; the API uses `PUT`/`DELETE`, not a toggle endpoint.
* `local_signal_comments` has `parent_id` nullable and validates maximum depth
  one in service code. No unbounded nested thread.
* `local_signal_translations` is unique on `(signal_id, target_language,
  source_content_hash)`, allowing stale translations to be detected.
* `local_signal_reports` deduplicates an unresolved report by
  `(reporter, target, reason_code)`.
* `local_signal_capabilities` stores only `sha256(token)` plus an expiry and
  revocation timestamp. Raw bearer links never enter logs or responses.

### 4.2 Identity and deletion

Every author/action foreign key uses `(issuer, subject)` against
`identity.users`, as in the current canonical schema. On account deletion:

1. remove active sessions and publication capabilities;
2. redact author display data in published signals while retaining a minimal
   policy/audit record where legally required;
3. delete or anonymize personal drafts, reports, and private plans according
   to LALA's retention policy;
4. never cascade a user's content into review/economy/RAG evidence;
5. rebuild any derived feed/index without the deleted identity.

## 5. API contract

All endpoints live under `/api/v1/community`, use LALA's normal response
envelope, and derive the actor only from the Logto-backed request identity.
No client supplies `author_id`.

### 5.1 Read endpoints

| Method and path | Contract | Notes |
| --- | --- | --- |
| `GET /signals` | Contextual cursor feed filtered by `place_id`, `region`, `kind`, `language`, and `sort` | Public published only for guests; no raw internal score exposed |
| `GET /signals/{id}` | Published signal with safe author profile, translation availability, reaction/comment counts | 404 for unavailable content to avoid enumeration |
| `GET /signals/{id}/comments` | Cursor-paginated, published comments | Translation is a separate, explicit field |
| `GET /places/{place_id}/signals` | Place-scoped signals with a verified/recency filter | Map sheet uses a compact preview, not an endless feed |
| `GET /me/signals` | Actor's own drafts and published items | Authentication required |
| `GET /profiles/{public_handle}` | Public profile summary with opt-in local credentials | Never expose issuer/subject |
| `GET /feed` | Named contextual surfaces (`nearby`, `saved_plan`, `following`, `local_questions`) | Each response includes a safe reason code, not hidden model scores |

Cursor pagination uses `(published_at, id)` as the stable ordering key. A
response returns `items`, `next_cursor`, `has_more`, and a `context` object
that explains the selected filter. Offset pagination is only acceptable for
moderator console queries.

### 5.2 Mutations

| Method and path | Behavioural contract |
| --- | --- |
| `POST /signals` | Create a private draft only. Validate language, body length, locality precision, disclosure, canonical place links, and rate limits. |
| `POST /signals/{id}/submit` | Run deterministic PII/policy checks and enqueue moderation/translation. Never publish directly from client state. |
| `PATCH /signals/{id}` | Owner may update a draft; editing a published item creates a revision and may return it to review. |
| `DELETE /signals/{id}` | Owner deletion is idempotent and revokes public capability links. Preserve a minimal tombstone only when a report is open. |
| `PUT /signals/{id}/reactions/{type}` / `DELETE ...` | Idempotent set/unset. No optimistic count is authoritative until server response. |
| `POST /signals/{id}/comments` | Authenticated, limited, scrubbed, policy-checked comment. |
| `POST /signals/{id}/reports` | Private report submission; returns case receipt only. |
| `PUT /profiles/{handle}/follow` / `DELETE ...` | Idempotent follow/unfollow after block checks. |
| `POST /signals/{id}/share-links` | Optional future capability-link creation; explicit expiry and revocation required. |

### 5.3 Status and error policy

Use typed error codes rather than generic strings:

`AUTH_REQUIRED`, `CONTENT_NOT_FOUND`, `NOT_OWNER`, `INVALID_PLACE_LINK`,
`LOCATION_TOO_PRECISE`, `DISCLOSURE_REQUIRED`, `CONTENT_REVIEW_PENDING`,
`CONTENT_POLICY_BLOCKED`, `RATE_LIMITED`, `BLOCKED_RELATIONSHIP`, and
`TRANSLATION_UNAVAILABLE`.

The Flutter UI must show an honest pending or unavailable state. It must never
substitute canned “local” posts as a successful community response.

## 6. Service architecture

```text
Flutter/Web
  -> typed community client
  -> FastAPI community router + require_client_auth
  -> CommunityPolicyService (validation, visibility, block, rate limit)
  -> CommunitySignalRepository (PostgreSQL transaction)
  -> outbox row
       -> moderation/translation/index worker
       -> aggregate-only community signal worker (optional, delayed)
  -> read repository / contextual feed composer
```

### 6.1 Transaction rule

The authoritative transaction writes the signal/reaction/comment plus an
outbox event in the same PostgreSQL transaction. Realtime notification,
translation, feed materialization, and analytics consume the outbox later.
They cannot decide whether a contribution exists.

### 6.2 Derived ranking rule

Start with deterministic candidate selection:

1. only published, non-expired, non-blocked, language-compatible content;
2. place/region/route context match;
3. recency band, verified local contribution, accessibility/season relevance;
4. diversity cap by author and place; deduplicate translation variants;
5. optional user controls: newest, useful, following, questions.

Any future semantic reranker is a derived service. Its input is
privacy-scrubbed published summaries, its output is an ordering plus a reason
code, and it may not write an opaque “quality” score into a traveller's public
profile. Do not feed raw third-party reviews or private traveller drafts into
this ranker.

### 6.3 Realtime rule

Do not copy a process-memory WebSocket manager into a horizontally scaled
LALA deployment. Initial release is pull-to-refresh plus short polling/refetch
after mutation. Add SSE/WebSocket only after the outbox is wired through a
durable broker and the product has a real need for it.

## 7. UX contract

### 7.1 Entry surfaces

Community must be embedded in the travel loop, not introduced as a fourth
empty social tab.

* **Map place sheet:** “recent local notes” preview, a deliberate “ask/tip”
  entry point, and an action to add the place to today's itinerary.
* **Planner:** route notes attached to a day/area; publication defaults to
  private and the user chooses locality precision before submitting.
* **Place detail:** concise local-signal summary with filters for season,
  accessibility, language, and recency.
* **Dedicated Local Signals screen:** contextual feed, saved items, authored
  drafts, and moderation/result states. It is not a generic high-volume feed.

### 7.2 Compose flow

1. Choose intent: tip, question, accessibility, seasonal update, correction,
   or story.
2. Confirm a canonical place or coarse district. Exact current GPS is never
   copied automatically into a publishable signal.
3. Write in one source language; select any commercial relationship.
4. Preview locality disclosure, translation state, and visibility.
5. Save draft or submit. Submission explicitly says review/translation may be
   pending.

### 7.3 Display rules

* Display only locale-appropriate primary copy. A translation is labeled with
  method and source language, not blended into a Korean/English hybrid block.
* Use author handle and trust badges only when backed by a policy state; never
  show identity-provider identifiers.
* Do not surface “score/reason” permanently. Contextual selection rationale is
  on demand and includes bounded labels such as `same district`, `recent`, or
  `saved route`, not an internal ranking number.
* For a place with no signals, present an honest empty state plus official
  place/docent information. Do not create synthetic community content.

## 8. Trust, safety, privacy, and data boundaries

### 8.1 Publication policy

Before publish, run deterministic detection for contact details, exact address
when the user selected coarse locality, private booking details, hateful or
sexual content, unsafe/illegal activity, impersonation, misleading
official-status claims, and promotional disclosure omissions. A classifier can
assist triage but never silently turns a rejected policy case into published
content.

### 8.2 Travel-specific safeguards

* No live-location sharing, meet-up coordination, minor-related content, or
  real-time crowd/safety claims in the first release.
* Place tips may mention a venue only through a canonical LALA place link.
  Unmatched names enter correction review, not the public map.
* Business owners/staff and gifted/paid visitors must disclose the relation;
  commercial posts are excluded from “authentic local” ranking by default.
* Safety/accessibility information displays observation date and a disclaimer
  that official venue information prevails where available.
* Report, block, mute, and appeal paths are available before open publication.

### 8.3 RAG and recommendation firewall

User-generated signal text is **not** an automatic RAG source. The allowed
path is:

```text
published, moderated, opt-in signal
  -> privacy scrub + de-identification
  -> operator/automated aggregation at place-week level
  -> confidence/provenance stamp
  -> optional safe summary chunk
```

Only a safe aggregate summary may enter `rag.knowledge_chunks`, and only under
a dedicated source type such as `community_signal_aggregate`. Never embed raw
body text, comments, author identity, exact location, unpublished drafts,
report notes, or third-party review text. This preserves the existing LALA
review-ingestion policy that raw review text is not served or grounded.

### 8.4 Retention and audit

* Drafts: user-controlled deletion; short backup window documented separately.
* Published content: tombstone + revision/audit policy; author deletion must be
  actionable without exposing prior text publicly.
* Reports/moderation: restricted access, minimum necessary retention, append-
  only decision metadata.
* Event analytics: pseudonymous identifiers, no exact GPS, no raw content,
  fixed retention and deletion-aware aggregation.
* Logs: redact body, tokens, headers, `DB_DSN`, identity tokens, and source
  credentials.

## 9. Observability and outcome metrics

Track product behaviour without treating posting volume as success.

| Event family | Example fields (safe only) | Why |
| --- | --- | --- |
| `community.signal_*` | kind, locality level, language, moderation result, place link present | Publish funnel and policy health |
| `community.feed_*` | feed context, result count band, cursor, reason code band | Empty-feed and relevance diagnosis |
| `community.place_action_*` | signal id pseudonym, add-to-plan/favorite/directions action | Whether local information leads to travel action |
| `community.report_*` | reason code, resolution SLA band | Safety workload and efficacy |
| `community.translation_*` | source/target locale, method, failure code | Cross-language accessibility |

Primary outcomes: useful-signal save/add-to-plan rate, route completion after
signal exposure, cross-language comprehension feedback, local-business
dispersion proxy, report resolution SLA, and policy false-positive review rate.
Do not use likes alone as a quality metric.

## 10. Test strategy

### 10.1 Unit and contract tests

* visibility, ownership, block, follow, reaction idempotency, cursor stability;
* identity composite foreign-key mapping and account deletion behaviour;
* locality precision, disclosure, PII scrub, invalid canonical-place handling;
* post/comment/report state transitions and moderation action authorization;
* translation stale detection, locale-exclusive rendering contract;
* no raw signal body/author identity in aggregate/RAG output or logs;
* no relationship between user-generated content and `community.posts` ingest
  data in scoring queries.

### 10.2 Integration tests

Use synthetic, operator-authored fixtures only. Verify:

1. guest read vs authenticated write separation;
2. draft -> submit -> moderated publish -> map/place preview;
3. report -> hide -> appeal decision visibility;
4. delete -> capability revocation -> feed/index removal;
5. worker retry/outbox idempotency;
6. Korean and English source/translation views with no mixed-language default;
7. disabled RAG ingestion for raw UGC, and allowed aggregate-only opt-in path.

### 10.3 Device acceptance

On Android, iOS, and web: enter via a real place, author a coarse-locality
draft, submit, view honest pending state, recover from denied location, view a
translation-aware published item, report/block, and add the linked place to a
plan. Evidence uses real API data or explicitly labeled synthetic test tenant
data; no bundled fake posts count as acceptance.

## 11. Delivery sequence

| Slice | Scope | Exit criterion |
| --- | --- | --- |
| C0 | Policy, canonical migration design, API schemas, synthetic fixtures | Privacy/RAG firewall contract reviewed |
| C1 | Drafts, signals, canonical place link, detail/read feed | Authenticated write and guest read work with cursors |
| C2 | Submit/moderation queue, reports, blocks, rate limits, audit | No public content bypasses policy path |
| C3 | Map/planner integration, KO/EN translation state, saves/actions | Signal reliably leads to a travel action |
| C4 | Follow/contextual feed and diversity logic | Deterministic, explainable ranking passes eval fixtures |
| C5 | Aggregate opt-in learning and safe RAG hand-off | No raw UGC reaches RAG; provenance is testable |
| C6 | Optional capability links/realtime/challenges | Only after operational load and moderation readiness prove need |

## 12. Explicit non-goals

* Anonymous public posting, direct messaging, real-time meetups, or live
  location sharing.
* Scraping/copying Naver, Daangn, social-media, or review bodies into a public
  traveller community.
* Migrating OPIc users, posts, vectors, graph edges, chat messages, prompts,
  images, screenshots, CSS, or tests.
* A graph database, WebSocket server, or LLM recommender in the first viable
  LALA community release.
* Rewarding content volume, follower count, or commercial activity as proof of
  authentic local value.

## 13. Implementation readiness checklist

- [ ] Product policy owner approves signal kinds, commercial disclosure, and
      location precision rules.
- [ ] Legal/privacy review confirms retention, deletion, translation, and
      consent for the aggregate-only RAG path.
- [ ] Additive canonical SQL is numbered after the current canonical sequence;
      no destructive rewrite of `community.posts`.
- [ ] OpenAPI contract and generated Flutter client are the API SSOT.
- [ ] Logto-only authenticated mutation boundary is enforced server-side.
- [ ] Moderation/report/block/rate-limit path exists before public publication.
- [ ] Synthetic fixtures, API tests, and Android/iOS/web acceptance scenarios
      pass without mock community data.
- [ ] Community analytics are pseudonymous and separated from recommendation
      score/economy evidence.
