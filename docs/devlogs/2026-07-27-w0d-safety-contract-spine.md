# W0-d safety-contract test spine — 2026-07-27

## Start

- Branch: `codex/w0d-safety-contract-spine`
- Base: refreshed `origin/main` at `a2e1ed9`
- Worktree: `/private/tmp/lala-w0d-safety-contract-spine`
- Scope: safety-contract tests and secret-safe planning evidence only.

## Contract covered

`test_safety_contracts.py` now exercises the 063 Local Signals SQL view
projections and Pydantic boundaries, aggregate-only review governance,
`place_mention` RAG and docent citation projections, DB-first normal place
reads, validation-input redaction, and operational secret redaction.

The source boundary is deliberately not an all-community-source ban. Review
evidence is eligible only from an approved API, licensed data, or static data
whose terms explicitly permit this processing; public availability alone is
not authorization. An approved Naver Search/Blog API source can register and
produce normalized attribute evidence. Raw blog text is rejected at the
governed normalized-record boundary and cannot persist to quarantine metadata
or cross into aggregate, user, RAG, or docent output. Local Signals remain
first-party UGC with their own `source_kind` and author-identity boundary; they
are not joined to review-source identity.

## Limits and next dependency

No source consumer, API/schema/flag/worker, migration apply, crawl, live
provider call, or deployment is included. Live source terms/legal approval and
acquisition remain external gates. W0-e OpenAPI compatibility CI is the next
foundation slice.

## Evidence

- Focused safety suite: `19 passed, 1 warning`.
- Full clean no-`.env` API suite: `1058 passed, 1 warning` in `28.02s`.
- `ruff check .`, `ruff format --check .`, `pre-commit run --all-files`, and
  `git diff --check`: passed.
- PR: [#71](https://github.com/3dt-1st-org/LALA-next/pull/71)
- Head: `4b6818c143604a71a720a8c23fbef0d490a743f2`
- Successful CI run: [30210233934](https://github.com/3dt-1st-org/LALA-next/actions/runs/30210233934)
  — API job [89815099051](https://github.com/3dt-1st-org/LALA-next/actions/runs/30210233934/job/89815099051),
  Flutter job [89815099007](https://github.com/3dt-1st-org/LALA-next/actions/runs/30210233934/job/89815099007),
  Unix job [89815098998](https://github.com/3dt-1st-org/LALA-next/actions/runs/30210233934/job/89815098998):
  all green.

The PR was kept Draft during implementation and review; merge remains gated on
the final required checks.
