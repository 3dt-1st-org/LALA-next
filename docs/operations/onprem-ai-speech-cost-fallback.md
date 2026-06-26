# On-Premises AI and Speech Cost/Fallback Policy

Last updated: 2026-06-26 KST

The on-premises API can call live Azure OpenAI and Azure Speech through process
environment variables in ignored `runtime/onprem-api.env`. This keeps the
runtime independent of Azure Key Vault while preserving the same live feature
path for docent generation and audio.

## Model Policy

- Docent generation, docent QA, and judge-facing narrative quality paths use
  `gpt-5.4-mini`.
- Bulk review/mention processing can use `gpt-5.4-nano` for first-pass
  extraction, with `gpt-5.4-mini` reserved for low-confidence rechecks.
- Do not downgrade docent generation to the bulk model just to save cost.

## Runtime Flags

Normal contest/review runtime:

```dotenv
LALA_ENABLE_LIVE_AI=true
LALA_ENABLE_LIVE_SPEECH=true
KEY_VAULT_URL=
LALA_ALLOWED_KEY_VAULT_HOSTS=
LALA_PAID_ROUTE_RATE_LIMIT_ENABLED=true
LALA_DOCENT_SCRIPT_RATE_LIMIT_PER_MINUTE=60
LALA_DOCENT_AUDIO_RATE_LIMIT_PER_MINUTE=30
```

Cost or provider incident fallback:

```dotenv
LALA_ENABLE_LIVE_AI=false
LALA_ENABLE_LIVE_SPEECH=false
```

After changing either flag, restart the API:

```bash
launchctl kickstart -k gui/$UID/cloud.lala-next.api
```

## Smoke Checks

Live mode:

```bash
scripts/unix/check_onprem_runtime.sh \
  --require-live-ai \
  --require-live-speech

scripts/unix/smoke_api.sh \
  --base-url https://api.lala-next.cloud \
  --paid-dependency
```

Fallback mode:

```bash
curl -fsS https://api.lala-next.cloud/readyz
scripts/unix/smoke_api_matrix.sh \
  --base-url https://api.lala-next.cloud \
  --profile deploy
```

Fallback mode must remain DB-backed. It may disable live script generation or
speech, but it must not switch normal place/weather/recommendation reads to mock
or demo data.

## Operational Limits

- Keep a daily note of paid smoke usage during the contest window.
- If API latency or error rate rises, disable live speech first; it is more
  bandwidth-heavy and easier to communicate as temporarily unavailable.
- If the LLM provider returns repeated overloads or quota errors, pause live
  generation and use cached docent scripts until the provider recovers.
- If a cost threshold is agreed by the team, record the threshold outside the
  repository and review it before enabling broad public traffic.
- Keep Cloudflare WAF/rate limiting as the preferred edge control. The API's
  in-process paid route rate limit is only the first guardrail.

## Recovery

1. Restore the live AI/Speech env values in ignored runtime secret storage.
2. Set both live flags to `true`.
3. Restart `cloud.lala-next.api`.
4. Run `check_onprem_runtime.sh` with both live requirements.
5. Run one paid smoke and one browser/mobile docent/audio check.
