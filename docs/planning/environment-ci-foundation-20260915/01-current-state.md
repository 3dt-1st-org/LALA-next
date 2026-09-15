# 01. 현재 구조와 목표의 차이

기준 SHA와 적용 상태는 [입구](README.md)를 따른다. 아래의 '현재'는 저장소에서 확인한 구성이다.
workflow가 존재한다는 사실만으로 원격 환경의 현재 가동이나 보호 규칙 적용을 확인한 것은 아니다.

## 코드와 실행 구성

| 영역 | 현재 근거 | 목표를 위해 필요한 일 |
|---|---|---|
| 백엔드 | [FastAPI 설정](../../../apps/api/app/core/config.py), [Python 의존성](../../../pyproject.toml) | 기존 Python·psycopg2 구조 유지 |
| 프론트 | [Flutter 앱](../../../apps/flutter_app/README.md), [API 주소 설정](../../../apps/flutter_app/lib/core/config/app_config.dart) | 기본 주소가 운영이므로 local/staging 빌드에서 주소를 필수 지정하도록 검증 |
| 로컬 DB | [Compose](../../../compose.local.yml), [bootstrap](../../../scripts/unix/bootstrap_local_mvp_db.sh) | 개인 Docker PostgreSQL 활용. CI에는 실행마다 새 DB·볼륨 |
| 스키마 | [canonical SQL](../../../sql/canonical), [실행기](../../../apps/api/app/services/canonical_sql.py) | 전체 SQL 재실행과 증분 migration 이력을 구분 |
| seed | [local-only seed](../../../sql/dev_reset/README.md) | 공유 staging용 데이터 준비 절차 별도 작성 |
| 비밀 접근 | [runtime registry](../../../apps/api/app/core/runtime_secrets.py) | 환경 이름과 프로세스 프로필을 분리하고 staging 비밀 저장소·권한 경계 지정 |
| API 데이터 | [장소](../../../apps/api/app/services/places_service.py), [날씨](../../../apps/api/app/services/weather_service.py) | 실제 DB 통합 검증 추가. 정적 snapshot 성공을 정상 DB 검증으로 세지 않음 |

`bootstrap_local_mvp_db.sh --all`은 DB 시작·스키마·seed·점수·RAG·정적 snapshot 파일 생성까지 수행한다.
CI의 최소 DB 검사에서는 스키마·seed 단계만 선택하고 저장소 snapshot을 다시 쓰지 않는다.
bootstrap은 자체적으로 루트 `.env`를 읽는다. `ci` 프로필만 설정했다고 모든 shell wrapper가 dotenv를 무시하는 것은 아니다.

## 기존 CI

근거: [ci.yml](../../../.github/workflows/ci.yml), [verify_repo.sh](../../../scripts/unix/verify_repo.sh),
[pre-commit 설정](../../../.pre-commit-config.yaml).

| 검사 | 현재 구성 | 필요한 보완 |
|---|---|---|
| Python 테스트 | Windows API tests, Unix verification에서 실행 | 유지, 실제 DB 검사는 별도 job으로 추가 |
| Ruff·비밀 탐지 | pre-commit에서 실행. Ruff는 자동 수정 모드 | CI에서는 변경 없이 검사하고 local과 동일 기준 유지 |
| 타입 검사 | mypy 의존성·설정 존재 | workflow에 명시 실행 없음. 기존 오류 조사 후 범위 확정 |
| Flutter analyze/test | 전용 job이 Flutter를 설치해 실행 | 유지. SDK 버전 고정과 format 검사 추가 |
| Flutter reference client | wrapper 호출, SDK 없으면 생략 가능 | Dart 설치를 보장한 명시 gate 추가 |
| Flutter 빌드 | 전용 job에는 analyze/test만 있음 | 웹 release build 필수화. Android/iOS 빌드 단계 추가 |
| DB | SQL 계획·안전 규칙 검사 | 실제 PostgreSQL/PostGIS/pgvector에서 생성·업그레이드·데이터 검증 없음 |
| OpenAPI | export, 과거 snapshot 기준 호환성 테스트 | PR base 또는 배포 계약과 비교. DTO 필드·타입 검사 보강 |
| 외부 API | 테스트 fixture·mock, worker plan/dry-run | 실제 연동 검사는 staging에서 별도 수행 |

[기존 OpenAPI 비교기](../../../apps/api/app/services/openapi_compat.py)는 경로·메서드·일부 parameter·응답 content type·인증 변경을 검사한다.
응답 DTO의 모든 필드·타입 변경을 재귀적으로 검증하는 도구는 아니다. 'export 성공 = 프론트 호환성 보장'으로 해석하지 않는다.

## 기존 배포

| 구성 | 현재 trigger와 대상 | 목표와의 차이 |
|---|---|---|
| [EC2 deploy](../../../.github/workflows/deploy.yml) | main의 CI 성공 후 운영 EC2 재시작 | staging 검수·운영 승인 단계 없음. CI SHA 대신 실행 시점 `origin/main`을 가져옴 |
| EC2 DB·health 검사 | SQL 적용 단계 없음. health 성공 후 readiness mode 출력 | migration 실패 시 배포 차단, 필수 readiness 항목 판정 필요 |
| [Azure dev deploy](../../../.github/workflows/azure-dev-deploy.yml) | dev push 일부 경로 또는 수동 실행 | 과거 개발 환경. 현재 AWS 전용 runtime secret 계약과 호환 확인 필요 |
| [배포 웹 smoke](../../../.github/workflows/deployed-web-smoke.yml) | dev push 또는 수동 실행, 운영 웹 주소 대상 | staging 배포 완료·동일 SHA에 연결된 검사가 아님 |
| [웹 배포 helper](../../../scripts/unix/deploy_flutter_web_vercel.sh) | 별도 빌드·배포 도구 | GitHub 밖의 자동 배포 설정과 프로젝트·도메인 mapping 인수 필요 |
| 앱 배포 | Android/iOS 소스 존재 | staging flavor·서명·내부 배포·승격 파이프라인 별도 구성 필요 |

[9월 10일 개발 환경 조사](../team-development-preparation-20260909/08-development-environment.md)는
Azure 개발 환경의 설정 흔적과 접근 제한을 기록한다. 그 기록을 오늘의 'staging 사용 가능'으로 바꾸어 적지 않는다.

## 전환 전 주의할 연결

- `LALA_RUNTIME_PROFILE=staging`은 현재 유효한 값이 아니다. API는 `api`, 배치는 `worker`를 사용한다.
- `LALA_WEATHER_MODE=mock` 같은 대화상의 예시 변수는 현재 구현되어 있지 않다.
- `LALA_ENABLE_LIVE_ROUTING=true`여도 [현재 Directions 함수](../../../apps/api/app/services/travel_time_service.py)는 실제 API를 호출하지 않는다.
- `main` 또는 `dev`를 단순 테스트용 push 대상으로 사용하기 전에 해당 배포 trigger를 전환해야 한다.
