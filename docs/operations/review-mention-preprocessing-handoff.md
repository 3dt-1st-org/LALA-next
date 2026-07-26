# Review/Mention Preprocessing Handoff

This handoff is the secret-safe implementation record for the review and
mention preprocessing pipeline. It is separate from the Local Signals handoff.

## M3 implementation record — 2026-07-27

Branch: `codex/m3-review-preprocessing` (Draft PR; merge is not part of this
phase).

The batch boundary now has the following contracts:

- approved API, licensed data, or static data whose terms explicitly permit
  this processing are the only eligible external review evidence inputs;
  no public-data assumption authorizes processing;
- `review_bulk` is the strict JSON gpt-5.4-nano lane for category-typed
  attributes and bounded ad signals;
- `review_recheck` is a selective gpt-5.4-mini resolution lane only. It does
  not generate docent content or replace final docent QA;
- schema-invalid, low-confidence, ambiguous-ad, and unresolved recheck
  outcomes retain only bounded status/reason metadata and do not receive a
  quality score or approved RAG projection;
- source content is read only in memory for an approved processing call. The
  persisted/API/RAG shape contains aggregate attributes, confidence, status,
  provenance, and a content hash, never body/title/evidence phrases/summary or
  free-form model reasons;
- accepted safe attributes are updated in
  `community.place_mentions_weekly` and mirrored idempotently to
  `travel.place_enrichments`. No migration is applied by this phase.

The worker contract exposes dry-run counts/status only. Missing
`OPENAI_API_KEY` or a disabled live-AI gate returns `disabled` without a DB read
or provider call; apply remains fail-closed. No crawl, seed, live provider
request, deployment, or DB migration apply was performed for this phase.

## Remaining gates

- operator-approved quarantine/recheck/replay persistence and replay-window
  controls remain the M4 decision gate;
- broader approved source onboarding and legal/terms verification remain
  external gates;
- live OpenAI cost, latency, and quality evidence remains uncollected until a
  separately approved controlled smoke;
- actual production DB apply and deployment remain outside this phase.
