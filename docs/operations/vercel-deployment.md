# Vercel MVP Deployment

LALA-next uses two Vercel projects for the public MVP:

- `lala-next`: Flutter web frontend.
- `lala-next-api`: FastAPI backend.

Python dependency management stays uv-based. The API deployment reads
`pyproject.toml`, `.python-version`, and `uv.lock`; Vercel's Python runtime then
installs required dependencies from the lockfile during the remote build.

## Backend

The backend entrypoint for Vercel is `api/index.py`, which imports the FastAPI
application from `apps.api.app.main`. The root `vercel.json` rewrites every
request to that function and uses `.vercelignore` as an allowlist so local docs,
artifacts, Flutter builds, virtual environments, and legacy imports are not
uploaded or exposed as static files.

Production environment variables for the legacy Vercel API fallback path:

```text
LALA_PUBLIC_DEMO_MODE=false
CORS_ALLOW_ORIGINS=https://lala-next.cloud,https://www.lala-next.cloud,https://lala-next.vercel.app
LALA_ENABLE_LIVE_AI=false
LALA_ENABLE_LIVE_SPEECH=false
```

The primary API runtime now lives on Azure Container Apps. For production,
review, and shared dev, keep `LALA_PUBLIC_DEMO_MODE=false`; the normal data path
is PostgreSQL plus Key Vault with reviewed ingest, scoring, and RAG jobs.
Bundled static data is only an offline, read-only snapshot fallback for DB
outage handling or isolated local checks.

Flutter web builds that call Azure directly need a client credential at build
time, such as `LALA_API_BEARER_TOKEN`, until OAuth or a backend-for-frontend
proxy replaces the static transition credential. Keep that value in deployment
secrets only; never place it in repo docs or examples.

Refresh the bundled snapshot from a canonical DB before a production demo:

```bash
scripts/unix/plan_place_ai_enrichment.sh --dry-run-ai --limit 20
ALLOW_AI_PLACE_ENRICHMENT_APPLY=1 \
  scripts/unix/plan_place_ai_enrichment.sh \
  --apply \
  --confirm APPLY_AI_PLACE_ENRICHMENT
scripts/unix/plan_place_score_batch.sh --preview --limit 20
scripts/unix/export_public_mvp_snapshot.sh --preview --limit 20
ALLOW_PUBLIC_MVP_SNAPSHOT_WRITE=1 \
  scripts/unix/export_public_mvp_snapshot.sh \
  --write \
  --confirm WRITE_PUBLIC_MVP_SNAPSHOT
```

Deploy the API:

```bash
vercel deploy --prod --yes --force --format json
```

Smoke the API:

```bash
curl -fsS https://api.lala-next.cloud/healthz
curl -fsS https://api.lala-next.cloud/readyz
curl -fsS 'https://api.lala-next.cloud/api/v1/places?lat=37.2636&lng=127.0286&radius_m=50000'
```

## Frontend

Build Flutter web against the custom API domain:

```bash
flutter build web --release \
  --dart-define LALA_API_BASE_URL=https://api.lala-next.cloud \
  --dart-define KAKAO_JAVASCRIPT_KEY="$KAKAO_JAVASCRIPT_KEY"
```

Deploy the built frontend to the `lala-next` Vercel project:

```bash
vercel deploy apps/flutter_app/build/web \
  --prod \
  --yes \
  --project lala-next \
  --scope geond \
  --local-config apps/flutter_app/build/web/vercel.json \
  --format json
```

Smoke the frontend:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://lala-next.cloud
curl -sS -o /dev/null -w '%{http_code}\n' https://www.lala-next.cloud
```

The production Flutter build should use the Azure-backed API base URL, the Kakao
Maps JavaScript key, and a 50 km default recommendation radius. Kakao Developers
must allow the deployed web domains, including `https://lala-next.cloud`,
`https://www.lala-next.cloud`, and any Vercel preview domain used for judging.

## DNS

Gabia currently hosts DNS for `lala-next.cloud`. Vercel is configured in
external-DNS mode, so changing nameservers is not required for this MVP.

Current public records:

```text
@          A      76.76.21.21
www        A      76.76.21.21
api        CNAME  <azure-container-app-fqdn>.
asuid.api  TXT    <azure-custom-domain-validation-id>
```

`@` and `www` stay on Vercel. `api.lala-next.cloud` belongs to Azure Container
Apps and should be verified with Azure hostname and certificate status, not
Vercel domain status.

If `@` or `www` records change, verify Vercel status:

```bash
vercel api /v6/domains/lala-next.cloud/config --raw
```

The response should include `misconfigured:false`.
