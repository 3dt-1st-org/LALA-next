# On-Premises Edge, Backup, Alert, and Standby Operations

Last updated: 2026-06-27 KST

This document closes the remaining post-cutover operations gaps that require
team-owned runtime values. It intentionally stores only procedure and env-var
names in git. Do not commit webhook URLs, Cloudflare tokens, zone ids, tunnel
credentials, DSNs, or backup data.

## Scope

- Off-host PostgreSQL backup target verification.
- Team alert webhook verification.
- Cloudflare edge rate limiting for paid public contest routes.
- Cold-standby plan to reduce single-Mac recovery risk.

## Required Ignored Runtime Values

Keep these env names in an ignored env file such as `runtime/onprem-api.env` or
in the team secret store. The values are intentionally omitted here:

```text
LALA_ONPREM_OFFSITE_BACKUP_DIR
LALA_ONPREM_ALERT_WEBHOOK_URL
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ZONE_ID
LALA_ONPREM_STANDBY_HOST
```

## Off-Host Backup

Verify the backup target before attaching it to the daily backup LaunchAgent:

```bash
scripts/unix/verify_onprem_offsite_backup.sh \
  --offsite-dir "$LALA_ONPREM_OFFSITE_BACKUP_DIR"

scripts/unix/verify_onprem_offsite_backup.sh \
  --offsite-dir "$LALA_ONPREM_OFFSITE_BACKUP_DIR" \
  --apply \
  --confirm VERIFY_OFFSITE_BACKUP
```

The script rejects repository paths and, by default, rejects targets that appear
to be on the same filesystem as the repository. That same-filesystem guard can
be bypassed only for a temporary rehearsal:

```bash
scripts/unix/verify_onprem_offsite_backup.sh \
  --offsite-dir "$LALA_ONPREM_OFFSITE_BACKUP_DIR" \
  --allow-same-filesystem \
  --apply \
  --confirm VERIFY_OFFSITE_BACKUP
```

After the target passes verification, reinstall the backup LaunchAgent:

```bash
scripts/unix/install_onprem_backup_launchd_macos.sh \
  --offsite-dir "$LALA_ONPREM_OFFSITE_BACKUP_DIR" \
  --require-offsite \
  --apply \
  --confirm INSTALL_BACKUP_LAUNCHD
```

## Alert Webhook

Send a safe test payload before wiring the monitor to team alerts:

```bash
scripts/unix/test_onprem_alert_webhook.sh

scripts/unix/test_onprem_alert_webhook.sh \
  --apply \
  --confirm TEST_ONPREM_ALERT_WEBHOOK
```

Then reinstall the monitor so failed checks post to the webhook env var:

```bash
scripts/unix/install_onprem_monitor_launchd_macos.sh \
  --require-data-freshness \
  --webhook-env-name LALA_ONPREM_ALERT_WEBHOOK_URL \
  --apply \
  --confirm INSTALL_MONITOR_LAUNCHD
```

## Cloudflare Edge Rate Limit

The API already has in-process rate limiting for the paid docent routes during
public contest access. Cloudflare should still enforce the first edge guard on:

- `POST /api/v1/docents/script`
- `POST /api/v1/docents/audio`

Review the plan:

```bash
scripts/unix/apply_cloudflare_edge_controls.sh
```

Apply through Cloudflare Rulesets API only after the token and zone id are set
in ignored env or process env:

```bash
scripts/unix/apply_cloudflare_edge_controls.sh \
  --requests-per-period 30 \
  --period-seconds 60 \
  --mitigation-timeout-seconds 600 \
  --apply \
  --confirm APPLY_CLOUDFLARE_EDGE_CONTROLS
```

The script creates or reuses the `http_ratelimit` phase entrypoint and adds a
single LALA paid docent route rule if it is not already present. It never prints
the Cloudflare token or zone id.

## Cold Standby

Until the team provisions a second always-on server, use cold standby as the
minimum recovery posture:

```bash
scripts/unix/plan_onprem_standby.sh
scripts/unix/plan_onprem_standby.sh \
  --target-os macos \
  --standby-host "$LALA_ONPREM_STANDBY_HOST" \
  --backup-source "$LALA_ONPREM_OFFSITE_BACKUP_DIR"
```

Readiness criteria for the standby host:

- Repo checked out at the approved branch or release commit.
- Docker PostgreSQL image built and extensions available.
- Latest off-host dump restored successfully.
- Restore drill passed on the standby host.
- Local `/readyz` reports DB-backed data, PostGIS configured, snapshot fallback
  disabled, live AI enabled, live speech enabled, and data freshness configured.
- Cloudflare Tunnel credentials remain disabled until an approved failover or a
  separate rehearsal hostname is used.

## Verification Bundle

Run these after changing any of the four areas:

```bash
git diff --check
bash -n scripts/unix/verify_onprem_offsite_backup.sh \
  scripts/unix/test_onprem_alert_webhook.sh \
  scripts/unix/apply_cloudflare_edge_controls.sh \
  scripts/unix/plan_onprem_standby.sh
scripts/unix/check_onprem_runtime.sh \
  --require-live-ai \
  --require-live-speech \
  --require-data-freshness
```
