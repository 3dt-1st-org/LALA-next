# Place ID lookup

`GET /api/v1/places/{place_id}` and `POST /api/v1/places/lookup` expose the
existing public place read model without requiring caller coordinates. The
batch accepts 1 to 100 IDs, validates every entry before repository access,
deduplicates by first occurrence, and returns found rows in that order plus
source-scoped `missing_place_ids`. Both routes accept `lang` or `language`,
normalize them to `ko` or `en`, and accept `include_scores` consistently with
the existing `/api/v1/places` route. A single source miss returns
`404 PLACE_NOT_FOUND`; a batch source miss remains a successful response.

## Request and response contract

- `lang` defaults to `ko`; when both aliases are sent, `language` takes
  precedence. `include_scores` defaults to `false`.
- Each ID is 1 to 128 characters after validation. Blank values and control
  characters are rejected. The batch body is exactly
  `{"place_ids":["id-a","id-b"]}` with 1 to 100 input entries.
- Duplicate IDs are removed only after the entire request validates. Both
  `places` and `missing_place_ids` follow first-occurrence input order.

Successful responses use the standard envelope. A batch response has this
shape (place fields abbreviated):

```json
{
  "ok": true,
  "data": {
    "places": [{"place_id": "id-a", "distance_m": null}],
    "missing_place_ids": ["id-b"],
    "query": {
      "place_ids": ["id-a", "id-b"],
      "language": "ko",
      "include_scores": false
    },
    "source": "db",
    "data_as_of": null
  },
  "error": null,
  "meta": {"request_id": "...", "source": "db"}
}
```

The single route places its public place object directly in `data` and reports
normalized language, score inclusion, source, and optional snapshot timestamp
in `meta`. Errors use the standard error envelope: `404 PLACE_NOT_FOUND` for a
single miss in a usable source, `422 VALIDATION_ERROR` for invalid input, and
retryable `503 PLACES_DB_UNAVAILABLE` when neither the DB nor an explicitly
enabled, usable snapshot can serve the lookup.

The DB path performs one parameterized query against `travel.public_places`,
joins the latest score and existing event/enrichment projections, and makes no
external provider calls. `distance_m`, `reason`, and `freshness` are null
because an ID lookup has no location or weather context. A DB read error is a
retryable 503 unless the existing static snapshot fallback was explicitly
enabled and its snapshot is usable. A missing, corrupt, or empty fallback
snapshot is also a retryable 503; a miss within a valid source never asserts
deletion.

## DBA handoff

No DDL, migration, backfill, new permission, or DB apply is required. The
lookup relies on the existing `travel.places.place_id` uniqueness contract and
the existing `travel.public_places` read boundary. The request cap of 100 is
the application guard for the array lookup; DB execution-plan validation may
be repeated by the independent integration tester without changing schema.

Behavior-event ledgers, offline-unsave tombstones, and related indexes are
outside this change. They require separate product and retention decisions and
must not be inferred from this read API.

| Future capability | Likely DBA responsibility if approved | Product decisions still required |
|---|---|---|
| Behavior-event ledger | Append-only identity/deduplication invariant, retention-aware storage, and indexes based on real read patterns | Allowed event names and payload, guest/account actor model, idempotency key, retention, deletion semantics |
| Offline unsave tombstone | Transactional revision/deduplication invariant, tombstone lifecycle, bootstrap and safe garbage collection | Remove-wins versus revision conflict policy, device operation ID, sync cursor, acknowledgement rules |

Any approved future storage change needs a separate additive migration,
backfill/bootstrap decision, rollback plan, and live-schema/plan review. This
repository-only assessment does not claim production grants, row counts, or
schema drift were verified.
