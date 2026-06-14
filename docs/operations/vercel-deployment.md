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

Production environment variables currently required for the public MVP:

```text
LALA_PUBLIC_DEMO_MODE=true
CORS_ALLOW_ORIGINS=https://lala-next.cloud,https://www.lala-next.cloud,https://lala-next.vercel.app
LALA_ENABLE_LIVE_AI=false
LALA_ENABLE_LIVE_SPEECH=false
```

The public MVP intentionally leaves DB, live AI, live speech, and OAuth/JWT
rollouts disabled. `/readyz` should therefore report `client_auth=public-demo`
and `mode.overall=skeleton`.

Deploy the API:

```bash
vercel deploy --prod --yes --force --format json
```

Smoke the API:

```bash
curl -fsS https://api.lala-next.cloud/healthz
curl -fsS https://api.lala-next.cloud/readyz
curl -fsS https://api.lala-next.cloud/api/v1/places
```

## Frontend

Build Flutter web against the custom API domain:

```bash
flutter build web --release --dart-define LALA_API_BASE_URL=https://api.lala-next.cloud
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

## DNS

Gabia currently hosts DNS for `lala-next.cloud`. Vercel is configured in
external-DNS mode, so changing nameservers is not required for this MVP.

Current public records:

```text
@    A    76.76.21.21
www  A    76.76.21.21
api  A    76.76.21.21
```

After changing DNS, verify Vercel status:

```bash
vercel api /v6/domains/api.lala-next.cloud/config --raw
```

The response should include `misconfigured:false`.
