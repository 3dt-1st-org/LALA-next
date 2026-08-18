# 2026-08-19 Canonical English Place-Name Repair (name_en only)

## Summary

Two confirmed wrong public English labels in `travel.places.name_en` get a
durable fix path: exact curated romanization entries for future deterministic
generation, plus a repeatable bounded targeted repair mode in the local
enrichment CLI for the existing rows. This change touches no database; the
apply below is an operator runbook for a later guarded execution.

| place_id | name_ko | wrong label today | canonical public label |
| --- | --- | --- | --- |
| `tour-api-1017547` | 중명전 | `Myeongjeongjeon Hall` | `Jungmyeongjeon` |
| `tour-api-130420` | 한밭교육박물관 | `Daejeon Hanhat Education Museum` | `Hanbat Education Museum` |

The earlier 3-record docent QA replay passed only because its manifest
injected the corrected labels; the stored rows stayed wrong until this path.

## What changed (code)

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

## Operator runbook (no secrets, no cloud identifiers)

Preconditions: a shell in the repo root with `DB_DSN` exported by your usual
secrets flow. The wrapper never prints the DSN value.

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
psql "$DB_DSN" -At -F $'\t' -c \
  "SELECT place_id, name_ko, name_en, address_en, region_name_en, updated_at
     FROM travel.places
    WHERE place_id IN ('tour-api-1017547', 'tour-api-130420');" \
  > output/local/place-name-repair/backup-two-rows.tsv
cat output/local/place-name-repair/backup-two-rows.tsv
```

Keep the TSV (gitignored under `output/local/`); it is the rollback reference
for all English columns of both rows.

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
# Labels now canonical, address/region unchanged versus the backup TSV.
psql "$DB_DSN" -c \
  "SELECT place_id, name_ko, name_en FROM travel.places
    WHERE place_id IN ('tour-api-1017547', 'tour-api-130420')
    ORDER BY place_id;"

# Exactly one new local_romanization history row per target, name_en only.
psql "$DB_DSN" -c \
  "SELECT place_id, name_en, address_en, region_name_en, source_method, prompt_version
     FROM travel.place_enrichments
    WHERE place_id IN ('tour-api-1017547', 'tour-api-130420')
      AND source_method = 'local_romanization'
    ORDER BY place_id, generated_at DESC;"
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
