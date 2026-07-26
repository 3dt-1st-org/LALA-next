# W0-c feature-flag registry — 2026-07-26

## Scope

- Source of truth: `docs/planning/cleanroom-reimplementation-execution-program.md`
  §5.0 and §10.1 P0-3.
- Clean implementation worktree: `/private/tmp/lala-w0c-feature-flag-registry`.
- Branch: `codex/w0c-feature-flag-registry`, based on `origin/main` after PR
  #67 and #68.
- This slice adds a typed, non-secret registry and configuration resolution
  only. No existing feature consumer is enabled, and no API schema, DB
  migration, Flutter source, crawl, deploy, or live provider call is included.

## Registry contract

`apps/api/app/core/feature_flags.py::FEATURE_FLAG_REGISTRY` owns the program
flag namespace. Missing values resolve to the documented current behavior;
invalid boolean/integer values fail closed. `Settings.feature_flags` exposes the
resolved values without replacing existing settings fields. The execution
program contains the corresponding key, environment, default, behavior, and
owner table.

## Cleanup evidence

Before cleanup, the #67 worktree was clean at `8cd5b85` and the #68 worktree
contained only its sibling-local untracked handoff. Both PR heads were verified
as ancestors of `origin/main` after their merge commits. The clean #67 worktree
and its local/remote branch were removed. The #68 worktree and branch remain
because its local handoff makes the worktree intentionally non-clean; no user
worktree was removed.

Root `/Users/geondongkim/LALA-next` remains outside this implementation
worktree and its user-owned dirty files are preserved exactly.

## Verification at phase start

- W0-a: canonical SQL ordering/safety tests already run in the API CI path;
  no new migration is needed here.
- W0-b: merged through PR #68 before this branch was created.
- W0-d and W0-e remain later W0 prerequisites; this PR does not claim them.

## Draft publication

- Commit: `ade7fc4`.
- Draft PR: `https://github.com/3dt-1st-org/LALA-next/pull/70`.
- Local verification: API `1043 passed, 1 warning`; W0-c targeted `41 passed,
  1 warning`; OpenAPI compatibility + safety `29 passed, 1 warning`; ruff,
  format, pre-commit, and diff check passed.
- Draft PR CI run `30207498540` is green: API job
  `89808004443`, Unix job `89808004423`, and Flutter job `89808004436`.
- Review/CI and merge remain external gates; no live runtime acceptance is
  claimed for this configuration-only slice.
