# LALA Local Signals Community - Product and Technical Adaptation

> Status: target design, not a claim that public community is already live
> Companion specification:
> [geond-opic-community-cleanroom-technical-spec.md](geond-opic-community-cleanroom-technical-spec.md)

## 1. Decision

LALA should not launch a generic “community” tab copied from a study product.
It should launch **Local Signals**: a small, place- and route-connected layer
that helps a foreign visitor or a Korean traveller who wants a genuinely local
experience decide what to do next.

The success condition is not post count. It is:

```text
trusted, contextual local signal -> clearer choice -> visit / route action
-> more dispersed and respectful local consumption
```

The community layer complements LALA's existing map, weather/air context,
official culture/tourism data, local-economy signals, and grounded docent. It
does not replace them and it must not act as a raw-review warehouse.

## 2. Two audiences, one shared local truth model

### 2.1 Foreign visitors

Foreign visitors usually need interpretation before abundance: what a local
practice means, whether a place is practical today, how to behave respectfully,
and how the location connects to a route.

| Need | Local Signals response | Anti-pattern to avoid |
| --- | --- | --- |
| Understand local context | Short, dated “why locals value this” note tied to an official/canonical place | Unverified folklore presented as fact |
| Cross language safely | Source language plus labeled translation, culturally specific terms explained in context | Mixed Korean/English text or invisible machine translation |
| Navigate uncertainty | Recent seasonal/accessibility notes and official data links | Crowd-sourced certainty about opening, safety, or legality |
| Build a day | “Add to today's route” from a local tip, with weather/air-aware planner check | A detached social feed that never changes an itinerary |
| Avoid tourist traps without hostility | Disclosure-aware “local value” context, franchise/business identity when backed by data | Shaming tourists, businesses, or neighbourhoods |

### 2.2 Domestic travellers seeking a real local experience

Domestic users typically need discovery beyond famous places: neighbourhood
rhythm, seasonal timing, small-business context, practical constraints, and a
way to distinguish a locally rooted venue from a merely viral one.

| Need | Local Signals response | Anti-pattern to avoid |
| --- | --- | --- |
| Find non-obvious options | District/route notes grounded in canonical places and current context | “Hidden gem” ranking driven by hype alone |
| Support local economy fairly | Explain small-business/franchise status only where data confidence permits | Claiming all independent venues are better than franchises |
| Plan around conditions | Dated outdoor/indoor, weather, accessibility, and opening-context notes | Treating a month-old anecdote as live operational data |
| Share a route responsibly | Coarse district and opt-in place links; default private route note | Publishing exact homes, quiet residential shortcuts, or live location |
| Gain trust | Contributor disclosures and an on-demand evidence/provenance label | Likes/followers treated as authority |

### 2.3 Shared design principle

Both audiences receive the same factual place identity, weather, public event,
business-identity confidence, and moderation policy. Locale changes the
explanation and translation experience, not the underlying truth.

## 3. The product surface: Local Signals, not a message board

### 3.1 Core signal cards

Every card is tied to a canonical place or coarse locality and has a date. The
card includes:

* signal kind: `local tip`, `seasonal update`, `accessibility`, `route note`,
  `question`, or `correction`;
* place/district, observation month, source language, and translation label;
* disclosure label where relevant (`visitor`, `owner/staff`, `paid/gifted`);
* one bounded primary action: **view place**, **add to plan**, **save**, or
  **answer**;
* a compact provenance/trust indicator that opens only on request.

It does not show an opaque popularity score, a permanent “AI reason,” an exact
author location, a live crowd count, or raw third-party review snippets.

### 3.2 Where it appears

```text
Map pin -> bottom sheet -> compact local signal preview -> add / save / ask
Planner stop -> route note -> condition-aware substitution if needed
Place detail -> dated, filtered local signals -> official/cultural grounding
Local Signals -> contextual feed -> authored drafts / saved responses
```

The map remains LALA's home. A traveller should be able to discover, understand
and add a place without entering a separate social product.

### 3.3 First-release flows

1. **Read near a place:** select a real Kakao marker; see up to three recent,
   moderated signals; add the place to a plan.
2. **Ask locally:** choose a canonical place/district; write a bounded question
   such as access, timing, or culture; select Korean or English; submit for
   review; receive an honest pending state.
3. **Share a local note:** save a private route note first; decide later whether
   to publish a coarse-locality signal. No automatic public sharing from GPS or
   planner history.
4. **Use a translation:** read original or translation, with the method/source
   label. Report a poor translation or unsafe content.
5. **Return to travel:** save or add the place; planner re-evaluates route and
   weather/air. This is the completion action.

## 4. Trust model for “real local” information

### 4.1 Trust is multidimensional

Avoid a single “local score.” Surface bounded labels that answer distinct
questions:

| Label | Evidence source | User-facing meaning |
| --- | --- | --- |
| `official context` | TourAPI/KCISA/KOPIS/official place data | The place/event identity is supported by an official source |
| `recent visitor note` | Moderated opt-in LALA signal with observation date | A traveller's dated experience, not a guarantee |
| `local contributor` | Opt-in local credential policy, periodically reviewed | The contributor has met LALA's policy for this label |
| `business context available` | `analytics.place_business_identity` with confidence | LALA has a confidence-bounded franchise/independent classification |
| `needs confirmation` | Old date, ambiguous place match, weak evidence, or conflict | Do not make a travel decision solely from this note |

No label authorizes a user to speak for a venue, neighbourhood, or cultural
group. “Verified local” describes a policy check, not universal expertise.

### 4.2 Commercial and franchise fairness

LALA's local-economy model already distinguishes franchise/business identity
only where the source supports it. Community follows the same rule:

* contributors disclose `owner_or_staff` and `paid_or_gifted` status;
* undisclosed promotional content is withheld or removed;
* a franchise label is informational, never an automatic down-rank;
* an independent/small-business signal may contribute only to the existing
  explicit local-value formula with confidence and recency, never as a hidden
  social popularity multiplier;
* user-generated claims do not alter business identity, final score, or
  economy analytics without a separately audited aggregation process.

This preserves the project's public-value goal: distribute attention and spend
more fairly without falsely equating “small” with “good” or “chain” with “bad.”

## 5. Language, culture, and translation

### 5.1 Locale contract

LALA's existing KO/EN exclusivity remains binding: Korean mode displays Korean
as the primary UI language; English mode displays English. A signal's original
language and an available translation are a deliberate exception, always
labeled and switchable rather than shown as simultaneous duplicate paragraphs.

### 5.2 Translation workflow

```text
author submits source-language signal
  -> deterministic PII/policy scrub
  -> moderation state
  -> translation request (only published/eligible content)
  -> language QA / stale-content check
  -> reader chooses original or labelled translation
```

Store translation provenance: source language, method (`human`, `machine`, or
`community-reviewed`), model/version if machine-generated, source hash, and
review timestamp. A content edit invalidates prior translations. Machine
translation does not translate names, addresses, cultural claims, menu safety,
or operating hours into asserted facts without canonical/official support.

### 5.3 Cultural mediation

For foreign visitors, local stories should favor short, respectful context:
what to expect, what not to disturb, seasonal etiquette, and a route action.
Do not turn cultural communities into spectacles, solicit residential/private
access, or use “authentic” as a claim that excludes residents.

## 6. Data and AI integration rules

### 6.1 Four isolated data lanes

| Lane | Inputs | May affect | Must never contain |
| --- | --- | --- | --- |
| Official/cultural | TourAPI, KCISA, KOPIS, public events | place identity, docent citations, event status | user identity or unlicensed review body |
| Economy | aggregate card data, franchise registry match | local-economy explanation and score component | individual cardholder or community author identity |
| Review/mention aggregation | licensed/approved sources through ingestion governance | normalized place-week attributes and confidence | raw review body in served API/RAG |
| LALA Local Signals | moderated, opt-in traveller content | contextual community UX and delayed safe aggregate | private drafts, exact GPS, third-party review imports |

No SQL query or worker joins an author identity from the Local Signals lane to
the economy/review lane. This is a hard privacy and fairness boundary.

### 6.2 RAG hand-off

LALA's docent may use official chunks and already-governed aggregate signals.
Local Signals can enter RAG only through this additional gate:

1. explicitly opted-in published signal;
2. completed moderation and deterministic PII scrub;
3. aggregation across several independent signals or an operator-approved
   cultural note;
4. place-week/district-week summary with provenance, confidence, recency and
   language;
5. safe summary chunk only, with no author, raw body, comment, exact route,
   link token, or private location.

The RAG response cites a source class such as `community aggregate`, never a
traveller's private/individual text. Low sample count returns no community
grounding rather than invented consensus.

### 6.3 AI roles

| Role | Permitted use | Forbidden use |
| --- | --- | --- |
| `gpt-5.4-nano` bulk lane | schema validation assistance, language detection, PII/ad triage, safe aggregate normalization | autonomous publishing, final cultural/safety judgement |
| `gpt-5.4-mini` selective lane | low-confidence recheck, translation QA, representative docent/community quality review | ranking people or judging worthiness of a culture/community |
| Deterministic services | visibility, disclosure, place-link, locality, rate-limit, and PII rules | pretending an uncertain input is verified |

All model calls are opt-in/config-gated, traceable by prompt/schema version,
and run outside the map interaction hot path when possible.

## 7. Safety and moderation operating model

### 7.1 Before public launch

The following are release gates, not aspirational backlog:

- authenticated write operations through Logto;
- draft-first publishing, commercial disclosure, and locality precision control;
- report, block/mute, moderator review, reversible hide/remove, and appeal;
- rate limits by action and identity; IP-level abuse protection at the edge;
- raw-content redaction in logs, analytics, AI prompts, and RAG;
- dated observation labels and stale/uncertain content policy;
- incident runbook and moderator response SLA;
- Korean and English policy/report UI.

### 7.2 Explicitly deferred

Direct messages, public live rooms, meetups, follower-count gamification,
live-location sharing, and unmoderated photo/video uploads are deferred. They
increase safety and operational burden without being necessary to help choose a
local place today.

## 8. LALA architecture adaptation

### 8.1 Reuse without coupling

Reuse LALA's current architecture boundaries:

```text
Flutter conditional map/location layers
  -> typed generated API client
  -> FastAPI /api/v1 router and Logto identity boundary
  -> PostgreSQL/PostGIS canonical schemas
  -> outbox + workers
  -> aggregate-only RAG and existing docent pipeline
```

Do not make Flutter call a community provider directly, expose database IDs,
or use an in-memory social state as a source of truth. The map's marker
clustering, weather, docent, and planner remain independently operable when
Local Signals is empty or temporarily unavailable.

### 8.2 Existing schema migration strategy

`060_community_tables.sql` and `061_community_chat_tables.sql` show that a
basic community foundation exists. Before implementation, decide in one ADR:

* evolve `community.user_posts` with travel-specific columns and all necessary
  status/visibility/moderation fields; or
* introduce `community.local_signals*` as a separate family.

Recommended: the separate family. `user_posts` and `chat_*` can remain
compatible/experimental surfaces while Local Signals gets a policy-first
contract. In either case, never collide with `community.posts`, which belongs
to the provider-ingestion path.

### 8.3 API and client work

1. Publish Pydantic/OpenAPI schemas under `/api/v1/community`.
2. Generate/update the Dart Dio client; do not hand-maintain duplicate DTOs.
3. Add feature modules under `apps/flutter_app/lib/features/community/` rather
   than enlarging `main.dart`.
4. Use existing KO/EN copy source; no flag emoji and no bilingual default text.
5. Integrate compact signal previews into the selected place sheet and planner
   before building a full feed screen.

## 9. Phased delivery plan

| Phase | User outcome | Engineering scope | Acceptance evidence |
| --- | --- | --- | --- |
| LSC-0 Policy and contract | Team agrees what “local” means and what is unsafe | ADR, schema/API spec, synthetic fixtures, moderation rules | Review sign-off; no code claim |
| LSC-1 Private route notes | A user can write/save a local note privately | Auth, drafts, canonical place link, deletion | Android/iOS/web draft persistence |
| LSC-2 Moderated public signals | A user can submit safe place/district notes | policy queue, report/block, rate limits, status UI | pending/published/removed flow with synthetic tenant |
| LSC-3 Map and planner action | Local context changes the itinerary | place sheet preview, add-to-plan/save, dated weather-aware display | real map/place flow and no fake signal data |
| LSC-4 Cross-language reading | Foreign visitors can understand a vetted local note | translation provenance, locale UI, correction/report | KO/EN device checks |
| LSC-5 Contextual feed | Users find useful signals without hype ranking | deterministic context ranking, author/place diversity, follow optional | relevance/diversity fixture evaluation |
| LSC-6 Aggregate learning | Aggregate safe community context can strengthen docent | opt-in aggregation, provenance, RAG guard tests | proof raw UGC never reaches RAG |

## 10. Measures of public value

Evaluate the feature on more than engagement:

* percentage of Local Signal views that lead to save/add-to-plan/directions;
* visits and itineraries dispersed beyond the most concentrated areas, measured
  only with aggregate anonymous signals;
* exposure share for matched small-business and non-franchise places, with
  confidence and fairness audits;
* foreign visitor comprehension/helpfulness feedback by language;
* number of stale/unsafe reports and their resolution time;
* proportion of community information that is dated, place-linked, and
  disclosure-complete;
* no increase in raw-text, identity, or precise-location leakage incidents.

Success is a traveller making a safer, more informed local choice and local
economic opportunity being more visible - not a feed maximising time spent.

## 11. Decisions required before implementation

1. Who can earn a `local contributor` label, how long it lasts, and how it can
   be appealed or removed.
2. Which localities are safe to publish at `district` versus `place` precision.
3. Whether business owners/staff may publish at launch and what disclosure
   review is required.
4. Human moderation ownership, Korean/English coverage, and incident SLA.
5. Translation provider, cost ceiling, source-language retention, and whether
   contributors can opt out of translation.
6. Retention/deletion policy for drafts, published notes, reports, and
   aggregate safe summaries.
7. The minimum sample/confidence threshold for an opt-in aggregate to be
   considered as a docent grounding source.
