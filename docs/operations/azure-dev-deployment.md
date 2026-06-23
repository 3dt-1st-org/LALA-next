# Azure Dev Deployment

LALA keeps the public Flutter Web app on its existing web hosting path for now,
while the shared backend and database move to Azure for team development.

## What Moves To Azure

- FastAPI backend: Azure Container Apps
- Shared PostgreSQL database: Azure Database for PostgreSQL Flexible Server
- Secret source: Azure Key Vault
- API image registry: Azure Container Registry
- Logs and telemetry: Log Analytics and Application Insights

## What Stays Outside Azure For Now

- Flutter Web public site deployment remains separate so the current
  `lala-next.cloud` flow can keep working while `api.lala-next.cloud` is moved.
- Mobile simulator and local development keep using local API overrides.
- Worker jobs remain dry-run contracts until the shared DB/API path is stable.

## Automatic Dev Deployment

The workflow at `.github/workflows/azure-dev-deploy.yml` deploys runtime changes
when commits land on the `dev` branch. It uses path filters for API code,
workers, Azure infrastructure, SQL, deployment smoke scripts, and dependency
files, so documentation-only changes do not rebuild the API image or update
Container Apps. It uses GitHub OIDC with `azure/login@v2`, so no long-lived
Azure credential JSON should be stored in GitHub.

Because the job uses GitHub Environment `dev`, the Entra federated credential
subject must be `repo:3dt-1st-org/LALA-next:environment:dev`.

Required GitHub Environment: `dev`

Variables:

- `AZURE_CLIENT_ID`
- `AZURE_DEPLOY_PRINCIPAL_OBJECT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `AZURE_LOCATION`
- `LALA_ENVIRONMENT_NAME`
- `POSTGRES_ADMIN_LOGIN`
- `CORS_ALLOW_ORIGINS`
- `LALA_PUBLIC_CONTEST_ACCESS` (defaults to `true` in the dev workflow during
  the public contest review window)

Secret:

- `AZURE_POSTGRES_ADMIN_PASSWORD`

## Runtime Secret Flow

The Bicep deployment writes the generated PostgreSQL connection string to Key
Vault as `db-dsn`. The API container receives only:

- `KEY_VAULT_URL`
- `LALA_ALLOWED_KEY_VAULT_HOSTS`
- `AZURE_CLIENT_ID`

The API then loads `DB_DSN`, `api-bearer-token`, and other runtime secrets
through managed identity. The deployment workflow may redeploy infrastructure
and the API image, but it does not read the database secret for schema
migration.

During the public contest review window, Azure dev sets
`LALA_PUBLIC_CONTEST_ACCESS=true` so reviewers can use the web app without
login or bundled static client credentials. This only opens the client-facing
API route family; the normal data path remains PostgreSQL plus Key Vault.

Azure dev, production, and review deployments keep
`LALA_STATIC_SNAPSHOT_FALLBACK=false`. The normal runtime path is PostgreSQL
plus Key Vault, populated by reviewed ingest, scoring, and RAG jobs. Bundled
static data should be treated only as an offline, read-only snapshot fallback
for DB outage handling or isolated local checks.

The GitHub `dev` environment must provide `AZURE_POSTGRES_ADMIN_PASSWORD`.
`AZURE_API_BEARER_TOKEN` is now optional for the contest window; if provided in
a later non-public transition, Bicep can still write it to Key Vault as
`api-bearer-token`. It should not be committed, printed, or copied into docs.

Weather fallback depends on the LALA runtime Key Vault secret
`public-data-service-key`. This is the public-data service key used for the
KMA ultra-short nowcast request and AirKorea 시도별 실시간 대기질 request when
`travel.weather_observations` has no fresh DB row for the map center. If
`/api/v1/weather` returns `source=unavailable`, check `/readyz` for
`public_data_service_key=configured` before investigating KMA/AirKorea response
quality or worker ingestion.

Current-location place recommendations require both `db=configured` and
`postgis=configured` in `/readyz`. `postgis=degraded` means the PostgreSQL
connection may exist, but the PostGIS extension or `travel.idx_places_geog_expr`
spatial index is missing, so the API should not be treated as a healthy
DB-backed runtime for radius-ranked map recommendations.

The deploy workflow also receives `AZURE_DEPLOY_PRINCIPAL_OBJECT_ID` so the
Bicep template can grant the GitHub OIDC service principal `AcrPush` and Key
Vault secret access without storing broad Azure credentials in GitHub.

After the Container App revision is updated, the workflow runs the same
secret-safe smoke scripts used by operators. `smoke_api.sh`
checks readiness and the primary client route family, and
`smoke_api_matrix.sh` checks broader category, language, coordinate, planner,
docent script, and docent audio variants against the custom API domain when it
is configured. In public contest mode these checks intentionally run without
auth headers; in a later credentialed mode they can still use process-local
smoke credentials without printing them.
If live Speech is disabled, the smoke expects `docents/audio` to return
`SPEECH_NOT_CONFIGURED` rather than fake audio bytes. When live Speech is
enabled, the same smoke requires an `audio/mpeg` response.

For the first local Azure CLI provisioning, `enableRoleAssignments=true` creates
the runtime RBAC bindings. The GitHub `dev` workflow passes
`enableRoleAssignments=false` so the deploy principal can redeploy app
configuration without needing broad role-assignment write permission.

## Safety Boundary

This deployment lane is for shared dev, not production.

- Public DB access is restricted to Azure services. Schema and seed-data changes
  are applied separately through reviewed SQL or guarded runbooks, not on every
  `dev` branch push.
- Production should use private networking, separate staging/prod resource
  groups, stricter database identities, backup policy review, and explicit
  DNS cutover planning.
- Live resource names and subscription identifiers must stay out of tracked
  Markdown. Put them in GitHub environment variables, Azure, or local runbooks.
