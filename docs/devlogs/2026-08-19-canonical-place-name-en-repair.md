# 2026-08-19 Canonical English Place-Name Repair (name_en only)

## Summary

Two confirmed wrong public English labels in `travel.places.name_en` got a
durable fix path: exact curated romanization entries for future deterministic
generation, plus a repeatable bounded targeted repair mode in the local
enrichment CLI for the existing rows. The code path merged as PR #152 (squash
commit `db5ccac097fc5bc13c7b64646a308e48c3cc352`; merged 2026-08-18T16:17:55Z,
which is 2026-08-19 in the project's Asia/Seoul reporting timezone — all
dates below are KST), and the guarded targeted apply was then executed once,
bounded to exactly the two rows below. The runbook in this devlog is the
record of that execution and the reference for any future guarded use.

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

## Operational outcome (completed 2026-08-19, KST)

- Merged: PR #152 squash commit `db5ccac097fc5bc13c7b64646a308e48c3cc352`,
  merged 2026-08-18T16:17:55Z = 2026-08-19 01:17:55 KST. CI and the standard
  deploy for that exact SHA both concluded `success` immediately after
  (2026-08-19 KST).
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

## Operator runbook (executed once 2026-08-19 KST; retained for reference)

Preconditions: the repository runtime resolves the connection itself through
its managed secret contract — the examples below call
`get_settings().db_dsn`, which honors `LALA_RUNTIME_PROFILE`: operational
profiles (`api`/`worker`) pull from the managed secret store fail-closed, so
never export a raw connection value on the production host. Local development
is the separate, clearly-labeled option: `LALA_RUNTIME_PROFILE=local` with
`DB_DSN` in the environment (or `.env.local`) is the supported override.
Nothing here ever prints the DSN value. No `psql` CLI is assumed on the
production host: the backup and read-back examples below use the repository
Python runtime with the same driver the enrichment CLI uses.

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
import psycopg2

from apps.api.app.core.config import get_settings

# The repository runtime resolves the DSN (managed secret contract per
# LALA_RUNTIME_PROFILE); its value is never printed or logged.
dsn = get_settings().db_dsn
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
        # Pre-apply boundary: per-target all-time count of local_romanization
        # history rows, to compare against the same count in the post-check.
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
        history_before = dict(cur.fetchall())
with open("output/local/place-name-repair/backup-two-rows.tsv", "w") as fh:
    for record in rows:
        fh.write("\t".join(str(column) for column in record) + "\n")
print("backup rows written:", len(rows))
print("local_romanization history before:", history_before)
PY
```

Keep the TSV and the printed pre-apply count (gitignored under
`output/local/`); they are the rollback reference for all English columns of
both rows and the boundary for proving the apply added exactly one history
row per target. Inspect them locally only — do not print backup contents to
shared logs.

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
import psycopg2

from apps.api.app.core.config import get_settings

# The repository runtime resolves the DSN (managed secret contract per
# LALA_RUNTIME_PROFILE); its value is never printed or logged.
dsn = get_settings().db_dsn
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
        # All-time per-target total of local_romanization history rows.
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

The history count is an all-time total, not a delta: this query alone cannot
prove the apply added exactly one row per target. A true one-new-row proof
needs the same count captured before the apply and compared after — the §2
preflight records that boundary alongside the backup TSV.

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
