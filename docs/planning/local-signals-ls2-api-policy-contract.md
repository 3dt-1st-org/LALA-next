# LS-2 Local Signals API and policy contract

## Scope

LS-2 exposes policy-first API behavior for first-party traveller Local Signals
only. The public read surface is limited to rows that are published, approved,
and public. Mutations derive author and actor identity exclusively from the
current Logto request identity.

The API does not ingest, repost, or join Local Signals to third-party review
content. An approved Naver Blog API or other lawful, licensed source may be
handled by the separate review/mention evidence pipeline. That lane has its
own source registration, provenance, moderation, identity boundary, and
aggregate contract; it is not a Local Signals write or read path.

## Public safety boundary

The Local Signals public projection and response schemas do not contain:

- Logto issuer/subject, direct author identity, private draft fields, or
  moderation decision internals;
- exact GPS, exact author location, phone numbers, email addresses, bearer
  tokens, capability tokens, or raw third-party review/blog text;
- opaque internal ranking scores or review-pipeline source payloads.

First-party signal body/title may be returned only from the approved public
projection. The requested KO/EN locale selects exactly one display body. If a
published source has no eligible translation for the requested locale, it is
not presented as if translated; the response remains an honest unavailable
result.

## Separate evidence lane

Approved Naver Blog API data, when authorized and implemented by the review
pipeline, may contribute only after its independent governance checks:
advertising classification, duplicate detection, canonical-place matching,
confidence, sentiment/attribute filtering, provenance, and retention policy.
Raw blog/review text remains unavailable to Local Signals public responses,
RAG, docent, and operational logs. Only a delayed, privacy-safe aggregate may
be consumed by a future review/RAG boundary.

This document does not implement Naver ingestion, scraping, login bypass, or
external collection. It records the domain separation required when the
separate approved-source pipeline is reviewed.

## Write policy

The write flag and read flag are independent, non-secret, default-off registry
entries. Flag-off requests return an explicit LOCAL_SIGNALS_DISABLED error.
Guest/static/public-contest access can read only; create, edit, submit, react,
comment, save, and report require the Logto identity dependency.

Draft creation and edit never accept an author field or client-controlled
status/visibility/moderation state. Deterministic policy checks reject contact
PII, coordinates, credentials, live-location/meet-up coordination, and
undisclosed promotional language. Submit can only move an owned draft into the
pending moderation state. Publication is not a client operation.

Idempotency is keyed by actor, operation, idempotency key, and normalized
payload; identical in-flight requests single-flight and replay, while a
conflicting in-flight payload returns a safe 409. The current implementation
provides an in-process seam and must be replaced or backed by a durable
deployment-level store before multi-instance production rollout. Pagination
cursors are opaque, strict, and sort-bound: recent compares
`published_at,id`, while useful compares `useful_count,published_at,id`.
Reaction and save add/remove routes use bounded actor-scoped rate limits. Rate
limiting and safe event metrics use replaceable seams; bodies and identity
values are not logged or metric labels.

## External decisions still required

- moderation ownership, Korean/English coverage, and response SLA;
- draft/published/report retention, deletion, and tombstone policy;
- translation provider, cost ceiling, provenance/version policy, and
  contributor translation opt-out;
- approved-source review pipeline retention and evidence thresholds;
- minimum sample/confidence/delay gate before any aggregate can reach RAG or
  docent grounding.
