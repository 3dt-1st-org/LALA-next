# LALA-next — AI 에이전트 지시서 (템플릿)

> **사용법**: `cp AGENTS.example.md AGENTS.md` 한 뒤, 아래 "로컬 노트" 영역에 본인 컨텍스트를 덧붙여 쓰세요.
> `AGENTS.md` 는 **.gitignore 로 커밋되지 않습니다** (각자 로컬 전용).
> **OpenAI Codex** 와 **Claude Code** 모두 루트의 `AGENTS.md` 를 네이티브로 읽습니다.

## 프로젝트 개요
LALA-next: 로컬 여행/체험 추천 플랫폼. FastAPI(Python) + PostgreSQL/PostGIS/pgvector + Flutter(iOS/Android/Web/macOS). 운영: AWS EC2 + RDS.

## 레포 구조
- `apps/api/` — FastAPI 백엔드 (`routers/v1.py`, `services/`, `schemas/`, `core/openapi.py`).
- `apps/flutter_app/` — Flutter 앱 (`lib/main.dart` 가 모놀리스; MVVM 재구성 진행 중).
- `apps/workers/` — 배치/파이프라인 워커.
- `clients/flutter/` — Dart API 클라이언트(현재 수제 → openapi-generator dart-dio 로 SSOT 전환 중).
- `sql/canonical/` — 정식 SQL 마이그레이션.
- `scripts/{unix,windows}/` — 운영/검증 스크립트.
- `.github/workflows/ci.yml` — CI (`api-tests` windows + `unix-verification` ubuntu).

## 자주 쓰는 명령
```bash
uv sync --extra dev                                       # 의존성 설치
uv run pytest apps/api/tests                              # 백엔드 테스트 (DB 불필요)
uv run ruff check . && uv run ruff format --check .       # 린트/포맷 검증
uv run pre-commit run --all-files                         # pre-commit 전체 검증
cd apps/flutter_app && flutter analyze && flutter test    # Flutter
```
> 주의: 메인 체크아웃에 `.env`(DB_DSN)가 있으면 일부 테스트가 임포트 시점 DB 연결로 행업. `.env` 를 임시 옮기거나 worktree(.env 없음)에서 실행.

## 보존 불변량 (절대 깨뜨리지 말 것)
- **지도 = 카카오맵** (MapLibre 아님). `kakao_map_view_{web,native,stub}.dart` 조건부 import 패턴 유지.
- **인증 = Logto SDK** (직접 토큰 관리 아님). `lib/auth/` (auth_controller, logto_auth_gateway) 경유.
- **위치 = Geolocator + browser_location 하이브리드**. `browser_location_{web,native,stub}.dart` 조건부 import 유지.
- 조건부 import 패턴: `export 'X_stub.dart' if (dart.library.html) 'X_web.dart' if (dart.library.io) 'X_native.dart';`
- 컴파일타임 환경변수: `String.fromEnvironment('LALA_BUILD_SHA')`.
- 테마: `ColorScheme.fromSeed`.

## 컨벤션
- **테스트**: `apps/api/tests/test_weather_service.py` 스타일 (`from __future__ import annotations`, pytest, `@parametrize`, 순수 헬퍼 직접 호출, 외부 의존 `monkeypatch`, DB 없이 녹색).
- **커밋**: conventional commits — `type(scope): 설명` (`feat(api):`, `test(api):`, `docs:`, `chore:` 등).
- **브랜치/PR**: 작업 브랜치 → 1~3커밋마다 push → 목표 달성 시 PR → merge. `main` 직접 커밋 금지.
- **pre-commit 의무**: 커밋 전 자동 실행(ruff/detect-secrets/hooks). 최초 `uv run pre-commit install` 로 활성화.

## 현재 진행 중인 대규모 작업
"구조·인프라 기반 다지기" — (A0) 엔지니어링 도구/CI/AGENTS, (B1) API 컨트랙트 SSOT(dart-dio), (C2/C3) Flutter MVVM 재구성(main.dart 해체).

---

## 로컬 노트 (본인 전용 — 이 아래에 자유롭게 기록, 커밋되지 않음)
<!-- 예: 자주 쓰는 테스트 서브셋, 로컬 API 엔드포인트, 개인 선호 등 -->
