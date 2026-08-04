# Devlog: P2 Official Media Probe Contract

- **Date:** 2026-08-05 KST
- **Branch:** `codex/p2-official-media-probe-contract`
- **Base:** `origin/main`
- **Status:** DRAFT_PR / IMPLEMENTED_NOT_RUNTIME_VERIFIED

## Summary

Offline contract for deterministic, fail-closed verification of official image
URLs. No real network/provider/DB/device action; all I/O flows through one
injected transport. Reuses `validate_image_url` and the source registry so URL,
governance, and image-rights rules match the rest of the inventory.

## Design

A single request object carries method + timeout + byte budget; a single
response object carries status, final URL, raw MIME, Content-Length, observed
bytes, and body-completeness; one result object exposes only a SHA-256 URL
fingerprint, normalized hostname, status/reason, normalized media type, proven
size, method, and HTTP status. `repr=False` hides the request URL and the
response's raw URL/MIME/length; literal-IP hostnames collapse to `ip-address`.

Flow (enforced order):

1. Source registered + `image_rights_status == "verified"` checked **before**
   transport; URL safety reuses `validate_image_url` plus localhost /
   `.localhost` / `.local` rejection. Rights/source/URL failures make zero calls.
2. HEAD first. A 2xx is accepted only with image MIME and a proven positive size
   at or below the budget. Missing MIME or size is inconclusive and triggers at
   most one bounded GET.
3. One bounded GET also runs for 403/405/501. 404/429/500/503 never fall back.
   Actual fallback statuses are only 403/405/501 and incomplete 2xx HEAD metadata;
   503 must not fall back.
4. GET size proof: a header Content-Length, or a complete body with positive
   observed bytes. Bounded GET enforces fail-closed size checks even when
   Content-Length header appears small: negative or oversized observed_bytes,
   contradictory size evidence, or incomplete bodies are rejected.
5. The final redirect URL is validated identically after every response; an empty
   `final_url` means no redirect.
6. Every transport exception is caught and collapsed to one generic probe error.
7. MIME is normalized to a lowercase `image/<subtype>` before exposure; invalid
   header values are never echoed.
8. URL fingerprinting preserves path/query case (they can be case-sensitive);
   only scheme and hostname are lowercased for canonicalization.

Batch and reconciliation outputs are deterministic tuples keyed by fingerprint.

## Files

- `apps/api/app/services/official_media_probe.py` (533 lines). Over the ~350
  preference because the consolidated request/response/result trio, the HEAD and
  GET classifiers, and full redirect/size/MIME safety each require distinct
  code; the module holds one transport protocol and one response validator.
- `apps/api/tests/test_official_media_probe.py` (806 lines). A parametrized
  matrix rather than per-case functions, covering every requirement below.
- This devlog.

## Test matrix (observed)

Governance before transport (zero calls): non-verified rights; unregistered
source; unsafe initial URL (wrong scheme, credentials, malformed, empty).
Host rejection: localhost, `127.0.0.1`, `[::1]`, private/reserved IPv4, `0.0.0.0`,
`*.localhost`, `*.local`, and exact hostname `local`. HEAD 2xx accepted with image MIME + proven size;
boundary size accepted. Exactly one bounded GET for 403/405/501 and for HEAD
missing MIME or missing size. No GET for 404/429/500/503. Size: malformed /
zero / negative rejected, oversized rejected. GET partial without total proof
rejected; complete body with positive observed bytes proves size. Bounded GET
enforces fail-closed: negative observed_bytes, oversized observed_bytes even
with small Content-Length, contradictory size evidence, and incomplete bodies
are rejected. Unsafe HEAD and GET redirects quarantined. MIME normalization
strips charset/case; invalid header value not echoed. Exceptions redacted (HEAD
and GET). No raw URL/query/token/hostname leak across result, `to_public_dict`,
repr, batch, or reconciliation. GET request carries the byte budget. Batch order
and counts deterministic; reconciliation fingerprint-only, immutable, stable
across runs. URL fingerprinting preserves case-sensitive paths/queries: `/A.jpg`
and `/a.jpg` produce different fingerprints while maintaining redaction.

## Verification (this worktree, observed exit 0)

```
uv sync --extra dev
uv run pytest apps/api/tests/test_official_media_probe.py -q        # 65 passed
uv run ruff check   apps/api/app/services/official_media_probe.py apps/api/tests/test_official_media_probe.py
uv run ruff format --check apps/api/app/services/official_media_probe.py apps/api/tests/test_official_media_probe.py
uv run pytest apps/api/tests/test_official_media.py apps/api/tests/test_official_source_inventory.py \
  apps/api/tests/test_official_source_registry.py apps/api/tests/test_official_source_adapters.py \
  apps/api/tests/test_official_media_probe.py -q                       # 106 passed
uv run pre-commit run --all-files
git diff --check origin/main...HEAD
```

Exact counts on the rewritten head: 65 probe tests; 106 across the five related
modules. All checks pass on the current head.

## Safety

- No live AI, provider, crawl, network, DB apply, deploy, or device action.
- No secret/PII/raw-review output; the two detect-secrets hits on test fixtures
  are deliberate credential/token strings guarded by redaction assertions and
  marked `# pragma: allowlist secret`.
- Replaces the prior untracked `COMPLETION_REPORT.md`; none remains.

## Remaining

- Merge dependency: none (standalone offline contract).
- External blocker: none.
- Next slice: a live transport implementation behind an approved live-ingest gate
  (every registered source is `blocked_external` today).
