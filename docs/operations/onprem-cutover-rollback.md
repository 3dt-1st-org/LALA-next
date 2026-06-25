# On-Premises Cutover And Rollback

Last updated: 2026-06-26 KST

This document defines the cutover path after the on-premises API and database
have already passed rehearsal. It does not authorize a DNS change by itself.

## Parallel Verification Gate

Keep Azure and on-premises running at the same time until all are true:

- Azure `/readyz` is healthy and remains the rollback target.
- On-premises `/healthz` and `/readyz` are healthy.
- On-premises `/readyz` reports DB-backed data with PostGIS configured.
- API matrix smoke passes against the on-premises URL.
- Browser/mobile rehearsal can use the on-premises API by explicit API base URL
  override.
- Operators have current database backup and restore evidence.
- Secret inventory has an owner and no tracked doc contains secret values.

## Pre-Cutover Evidence

Record the following in a private runbook:

- Azure API health timestamp.
- On-premises API health timestamp.
- Commit SHA deployed on on-premises API.
- DB dump timestamp and restore timestamp.
- Schema verification output summary.
- API smoke summary.
- DNS current value and intended replacement.
- Rollback owner and rollback command or DNS change path.

Do not paste DSNs, tokens, Key Vault URLs, live resource ids, or private host
credentials into tracked docs.

## DNS Cutover

The expected public behavior after cutover is:

- `lala-next.cloud` remains the Flutter Web site.
- `api.lala-next.cloud` resolves to the on-premises API ingress.
- TLS certificate is valid for `api.lala-next.cloud`.
- Existing Flutter Web build can call the API without changing the public site
  hosting path.

Recommended DNS process:

1. Lower DNS TTL before the maintenance window if the provider supports it.
2. Confirm Azure and on-premises smoke results.
3. Confirm the on-premises TLS certificate is already issued and renews without
   manual intervention, or that a documented renewal owner and calendar exists.
4. Update only the API record.
   - If the on-premises ingress has a static public IP, replace the existing
     `api` CNAME with `A` and optional `AAAA` records.
   - If the on-premises ingress is behind an approved managed tunnel or reverse
     proxy hostname, keep `api` as a CNAME to that provider target.
   - Preserve the previous Azure record type and value in the private runbook
     before changing anything.
   - Do not remove Azure custom-domain validation records during the rollback
     window unless the team separately approves it.
5. Wait for DNS propagation.
6. Run public smoke against `https://api.lala-next.cloud`.
7. Run browser/mobile happy path checks.
8. Keep Azure API untouched as rollback.

TLS acceptance criteria:

- `https://api.lala-next.cloud/healthz` succeeds without certificate warnings.
- The certificate common name or SAN covers `api.lala-next.cloud`.
- The renewal process is documented and assigned to an owner.
- Expired, self-signed, or browser-warning certificates block cutover.

## Public Smoke After DNS

```bash
curl -fsS https://api.lala-next.cloud/healthz
curl -fsS https://api.lala-next.cloud/readyz
scripts/unix/smoke_api.sh --base-url https://api.lala-next.cloud
scripts/unix/smoke_api_matrix.sh --base-url https://api.lala-next.cloud
```

Browser/mobile happy path:

- location permission prompt or manual region selection works;
- category pins render before clustering dominates;
- weather and PM10/PM2.5 are visible or explainable;
- docent script is grounded and does not expose scores or internal source names;
- no normal path displays mock/demo wording.

## Rollback Criteria

Rollback immediately when any of these persist after one restart and one smoke
rerun:

- public `/healthz` or `/readyz` fails;
- `/readyz` is not DB-backed;
- PostGIS is degraded for current-location recommendations;
- API matrix smoke fails on core place/weather/docent routes;
- browser/mobile route cannot load map recommendations;
- logs show secret loading failure or DB connection failure;
- on-premises latency is unacceptable for the review window.

## Rollback Steps

1. Change `api.lala-next.cloud` DNS back to the Azure API target.
2. Confirm public DNS resolves back to Azure.
3. Run Azure public smoke.
4. Keep on-premises logs and DB state for diagnosis.
5. Do not delete the on-premises database until the incident review completes.

## Azure Retention Window

After successful cutover:

- Keep Azure API, database, Key Vault, and deploy workflow available for the
  agreed rollback window.
- Disable scheduled or manual writes to the old Azure DB unless explicitly
  needed for rollback.
- Document the final source of truth date.
- Only decommission Azure after a separate approval checklist is complete.

## Final Acceptance

The migration is complete only when:

- public API smoke is green on the on-premises endpoint;
- Flutter Web/mobile flows are green;
- fresh backups exist for the on-premises database;
- rollback target and retention policy are documented;
- team agrees Azure is no longer the source of truth.
