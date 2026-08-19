# 2026-08-19 Canonical English Place-Name Repair (name_en only)

## Summary

Two confirmed wrong public English labels in `travel.places.name_en` got a
durable fix path: exact curated romanization entries for future deterministic
generation, plus a repeatable bounded targeted repair mode in the local
enrichment CLI for the existing rows. The code path merged as PR #152 (squash
commit `db5ccac097fc5bc13c7b64646a308e48c3cc352`, 2026-08-18), and the
guarded targeted apply was then executed once, bounded to exactly the two rows
below. The runbook in this devlog is the record of that execution and the
reference for any future guarded use.

| place_id | name_ko | wrong label before repair | canonical public label |
| --- | --- | --- | --- |
| `tour-api-1017547` | 중명전 | `Myeongjeongjeon Hall` | `Jungmyeongjeon` |
| `tour-api-130420` | 한밭교육박물관 | `Daejeon Hanhat Education Museum` | `Hanbat Education Museum` |

The earlier 3-record docent QA replay passed only because its manifest
injected the corrected labels; the stored rows stayed wrong until this path.

## What changed (code, merged in PR #152)

- `_KNOWN_NAME_EN` in `apps/api/app/services/local_place_enrichment.py` gains
  the two exact Korean-to-English entries, so future local romanization of
  these names yields the canonical labels.
- New targeted mode in `apps/api/app/tools/enrich_place_local_columns.py`
  (`--target-place-id PLACE_ID`, repeatable):
  - requires `--refresh-local` and `--preview` or `--apply`;
  - rejects blank values, duplicate ids, non-positive `--limit`, and any
    explicit `--limit` (broad-run option) combined with targets;
  - fetches exactly the requested ids (`place_id = ANY(...)`, no broad
    candidate set filtered later);
  - before any mutation, fails closed unless every id exists exactly once and
    its `name_ko` has a curated entry;
  - repairs **name_en only** — `address_en` and `region_name_en` are neither
    recomputed nor overwritten, and the new enrichment-history rows record
    only the corrected `name_en`;
  - each guarded `UPDATE ... WHERE place_id = %s AND name_ko = %s` and its
    history insert run in one transaction; a missing or concurrently changed
    target rolls back the whole run;
  - apply stays behind the existing `--confirm APPLY_LOCAL_PLACE_ENRICHMENT`
    and `ALLOW_LOCAL_PLACE_ENRICHMENT_APPLY=1` guards; JSON output carries
    only public ids/names and counts — the DSN is never printed.
- Default non-targeted plan/preview/apply behavior is unchanged.
- `sql/canonical/` is untouched: it is a replayable empty-DB schema baseline
  and must not carry row-specific UPDATEs.

## Operational outcome (completed 2026-08-18)

- Merged: PR #152 squash commit `db5ccac097fc5bc13c7b64646a308e48c3cc352`.
  CI and the standard deploy for that exact SHA both concluded `success` on
  2026-08-18.
- Scope actually mutated: exactly two `travel.places.name_en` values —
  `tour-api-1017547` → `Jungmyeongjeon` and `tour-api-130420` →
  `Hanbat Education Museum`. No `address_en` or `region_name_en` field was
  changed.
- Public confirmation (fresh no-cache reads): `GET /api/v1/places` with
  `language=en` returns `Jungmyeongjeon` and `Hanbat Education Museum` for
  the two ids; `/healthz` and `/readyz` report `ok` with `db` and `postgis`
  configured (db-backed mode).
- **This operation is complete. Do not rerun the targeted apply merely to
  confirm it.** The labels are already canonical in production, and a second
  apply would append redundant `local_romanization` enrichment-history rows —
  the history table is an append-only audit trail.
- `sql/canonical/` remains untouched: it is a replayable empty-DB schema
  baseline and must not carry row-specific UPDATEs. The repository CLI is the
  governed mutation path for bounded corrections like this one.

## Operator runbook (executed once 2026-08-18; retained for reference)

Preconditions: a shell in the repo root with `DB_DSN` exported by your usual
secrets flow. The wrapper never prints the DSN value. No `psql` CLI is
assumed on the production host: the backup and read-back examples below use
the repository Python runtime with the same driver the enrichment CLI uses.

### 1. Dry-run (no mutation)

```bash
# Plan only: reads nothing, mutates nothing.
scripts/unix/plan_place_local_enrichment.sh --json

# Targeted preview: fetches exactly the two rows and shows the labels
# that would be written (db_mutation=false).
scripts/unix/plan_place_local_enrichment.sh --json --preview --refresh-local \
  --target-place-id tour-api-1017547 \
  --target-place-id tour-api-130420
```

### 2. Backup / preflight (read-only)

```bash
mkdir -p output/local/place-name-repair
uv run python - <<'PY'
import os

import psycopg2

# DB_DSN comes from the usual secrets flow; it is never printed or logged.
dsn = os.environ["DB_DSN"]
target_ids = ("tour-api-1017547", "tour-api-130420")
with psycopg2.connect(dsn, connect_timeout=5) as conn:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT place_id, name_ko, name_en, address_en, region_name_en, updated_at
              FROM travel.places
             WHERE place_id IN %s
            """,
            (target_ids,),
        )
        rows = cur.fetchall()
with open("output/local/place-name-repair/backup-two-rows.tsv", "w") as fh:
    for record in rows:
        fh.write("\t".join(str(column) for column in record) + "\n")
print("backup rows written:", len(rows))
PY
```

Keep the TSV (gitignored under `output/local/`); it is the rollback reference
for all English columns of both rows. Inspect it locally only — do not print
backup contents to shared logs.

### 3. Exact two-target apply (guarded mutation)

```bash
ALLOW_LOCAL_PLACE_ENRICHMENT_APPLY=1 \
scripts/unix/plan_place_local_enrichment.sh --json --apply --refresh-local \
  --target-place-id tour-api-1017547 \
  --target-place-id tour-api-130420 \
  --confirm APPLY_LOCAL_PLACE_ENRICHMENT
```

Expect `"ok": true`, `"updated_rows": 2`, `"name_en_only": true`. Any refusal
or mid-run change exits 2 and writes nothing.

### 4. Read-only post-check

```bash
uv run python - <<'PY'
import os

import psycopg2

# DB_DSN comes from the usual secrets flow; it is never printed or logged.
dsn = os.environ["DB_DSN"]
target_ids = ("tour-api-1017547", "tour-api-130420")
with psycopg2.connect(dsn, connect_timeout=5) as conn:
    with conn.cursor() as cur:
        # Labels now canonical; address/region unchanged versus the backup TSV.
        cur.execute(
            """
            SELECT place_id, name_ko, name_en
              FROM travel.places
             WHERE place_id IN %s
             ORDER BY place_id
            """,
            (target_ids,),
        )
        for place_id, name_ko, name_en in cur.fetchall():
            print(place_id, name_en)
        # Exactly one new local_romanization history row per target, name_en only.
        cur.execute(
            """
            SELECT place_id, count(*)
              FROM travel.place_enrichments
             WHERE place_id IN %s
               AND source_method = 'local_romanization'
             GROUP BY place_id
             ORDER BY place_id
            """,
            (target_ids,),
        )
        for place_id, count in cur.fetchall():
            print(place_id, "local_romanization history rows:", count)
PY
```

Rollback (operator decision only): restore the two rows' `name_en` from the
backup TSV; the history rows are an append-only audit trail.

## Verification (this change)

```bash
uv run pytest apps/api/tests/test_local_place_enrichment.py -q
uv run pytest apps/api/tests/test_safety_contracts.py -q
uv run pytest apps/api/tests/test_enrich_place_local_columns.py -q
uv run ruff check apps/api/app/services/local_place_enrichment.py apps/api/app/tools/enrich_place_local_columns.py apps/api/tests
uv run ruff format --check apps/api/app/services/local_place_enrichment.py apps/api/app/tools/enrich_place_local_columns.py apps/api/tests
uv run pre-commit run --all-files
git diff --check
```

Mocked coverage: curated-label regression (romanize + replace-existing build),
name-only targeted build, exact-ID query, fail-closed refusal for
missing/uncurated/duplicate targets before mutation, name-only two-row atomic
apply with full rollback on a changed target, DSN redaction in error output,
and unchanged legacy plan/preview/apply.
