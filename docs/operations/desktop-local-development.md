# Desktop local development

This runner uses the existing PostgreSQL 16/PostGIS/pgvector Docker image and
canonical SQL. It does not connect to the operational RDS database or import
production data. Place/weather/docent seed records are development fixtures,
not current travel information. The API uses database reads, not snapshot fallback.

From the repository root on Windows, with Docker Desktop's Linux engine running:

```powershell
.venv\Scripts\python.exe scripts/local_dev.py setup
.venv\Scripts\python.exe scripts/local_dev.py serve
```

In a second terminal:

```powershell
.venv\Scripts\python.exe scripts/local_dev.py check
```

- API: `http://127.0.0.1:8080`
- Allowed browser origins: `http://127.0.0.1:8765`, `http://localhost:8765`
- DB binds only to loopback, port `55433`.
- Container: `lala-next-desktop-dev-postgres`
- Dedicated persistent volume: `lala-next-desktop-dev-postgres-data`
- Random local credentials: ignored `runtime/desktop-dev/database.json`.
  Keep this file to reuse the volume; do not publish or print it.
- Setup applies canonical SQL, seeds a new DB and calculates fixture scores.
  Existing place tables are not reseeded. If first-time initialization fails
  after schema creation, investigate before retrying seed/reset operations.
- No repo `.env` or inherited provider credentials are loaded. AWS/Key Vault
  lookup and live AI/Speech are disabled. No cloud account deletion credentials
  are supplied.

The existing seed includes Suwon locations. Select Suwon manually to inspect
fixture results; a real location elsewhere may correctly return no nearby places.
Browser geolocation and map rendering are separate from database readiness.
Map rendering still needs the configured provider's public key and allowed origin.

Optional authentication: public Flutter settings can be stored in the ignored
`runtime/desktop-dev/flutter-public.json` and supplied at Flutter build time with
`--dart-define-from-file`. The API runner reads only `LOGTO_ENDPOINT` and
`LOGTO_API_AUDIENCE` from that file. Register the web callback
`http://127.0.0.1:8765/auth-callback.html` and logout URI
`http://127.0.0.1:8765/` in the intended Logto application. Never put server
secrets in that file. Logto login contacts the configured external tenant;
local API account records and saved data use the dedicated local DB.

## Web preview assets

Build into a fresh output directory before switching the preview server to it.
Do not rebuild directly into the directory being served. On a OneDrive workspace,
prefer a local output directory outside the synchronized workspace. After building,
run this check before starting the static server:

```powershell
.venv\Scripts\python.exe scripts/verify_flutter_web_assets.py <web-output-directory>
```

This checks the generated font manifest, every referenced font (including icon
fonts), the application entrypoints, authentication callback and onboarding illustrations. A successful
Flutter compile alone is insufficient if generated static files are missing.
