# LALA-next — Copilot 커스텀 지시 (자동 로드)

이 파일은 GitHub Copilot이 이 repo에서 작업할 때 자동으로 읽는다.
상세한 운영 플레이북은 `docs/operations/copilot-cli-operations.md` 와
`docs/operations/onprem-runbook-docker-macos.md` 를 본다.

## repo 개요
LALA-next = Flutter Web 클라이언트 + FastAPI(API) + Docker PostgreSQL(postgis/pgvector).
운영 런타임: `api.lala-next.cloud` = Cloudflare Tunnel → macOS LaunchAgent(FastAPI, `127.0.0.1:8080`) → Docker PostgreSQL(localhost 바인딩). 단일 Mac 호스트.

## 운영 작업 필수 규칙 (HARD RULES)
1. **읽기 전용 먼저.** 상태 파악 없이 변경하지 않는다 (`docker ps`, `curl /readyz`, `launchctl list`, 로그 `tail`).
2. **기존 `scripts/unix/*.sh` 를 먼저 사용.** 같은 일을 재발명하지 않는다.
3. **상태 변경은 plan → apply 2단계.** 모든 운영 스크립트는 plan(읽기 전용) 우선 출력 → 사용자 확인 후 `--apply --confirm <TOKEN>`.
4. **`runtime/` 은 절대 git 커밋 금지** (전체 gitignore: env / 백업 덤프 / 로그 / cloudflared 자격증명). `git add` 전 `git check-ignore` 확인.
5. **시크릿 노출 금지.** DSN·비밀번호·API 토큰·webhook URL·tunnel 자격증명을 출력/로그/커밋/PR/이슈에 노출하지 않는다. 항상 env-var **이름**으로만.
6. **정상 데이터 경로는 항상 DB-backed.** mock/demo/snapshot 폴백으로 대체하지 않는다.
7. **외부 포트 노출 금지.** `127.0.0.1` 바인딩을 유지한다.
8. **변경 후 반드시 검증:** `scripts/unix/check_onprem_runtime.sh` + local·public `/readyz`.

## 핵심 사실
- 판단은 `/healthz` 가 아니라 **`/readyz`** 로 (healthz는 ok인데 DB가 죽어 있을 수 있음).
- 정상 상태 = `mode.overall=db-backed`, `db/postgis=configured`, `static_snapshot_fallback=disabled`.
- LaunchAgent 6종: `cloud.lala-next.{api, cloudflared, docker-autostart, backup, monitor, log-rotation}`.
  `docker-autostart`(`docker info || open -a Docker`, 로그인+5분 watchdog)는 **재부팅 후 DB 자동 복구의 핵심 — 제거 금지**.

## 대표적 장애 패턴 (Triage)
Mac 재부팅 후 Docker Desktop이 안 올라오면 → `/healthz=ok` 인데 `/readyz=degraded`, 백업·모니터가 매 틱 실패.
→ `docker info` 확인 → `open -a Docker` → Postgres는 `restart: unless-stopped` 로 자동 복구 → `/readyz` 가 db-backed 로 회복 확인 → `data_freshness=stale` 이면 날씨 갱신(`plan_weather_observation_refresh.sh --apply --confirm APPLY_WEATHER_OBSERVATION_REFRESH`).

## 핸드오프 인수 조건
public `/readyz` = `db-backed` + `postgis=configured` + `static_snapshot_fallback=disabled`. 셋 모두 아니면 인수 불가.

## 산출물 규칙
- 커밋/푸시/PR/머지는 **사용자가 요청할 때만**. 커밋 메시지 관례: `chore: ...`.
- **red CI 는 머지하지 않는다.** PR 전 로컬 검증 + CI green 확인.
- 새 LaunchAgent/스크립트를 만들면 `docs/operations/onprem-runbook-docker-macos.md` 의 Tracked files 와 해당 절에도 반영한다.
- 사용자가 한국어면 한국어로 응답한다.
