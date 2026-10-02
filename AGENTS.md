# LALA-next 공통 작업 지침

이 파일은 저장소에서 추적하는 팀 공통 기준이다. Codex, Claude, Copilot 등 도구별
진입 문서는 이 파일의 규칙을 우선 참조한다. 개인 경로, 계정 정보, 권한, 비밀값,
로컬 실행 메모는 이 파일에 추가하지 않는다.

## 작업 시작

- 먼저 `README.md`, `git status`, 현재 브랜치와 관련 문서를 확인한다.
- 코드의 현재 사실은 작업 브랜치와 `origin/main`의 코드·테스트·계약으로 확인한다.
  과거 문서의 SHA, 화면, 운영 환경을 현재 상태로 간주하지 않는다.
- 기존 dirty 파일과 추적되지 않은 산출물을 보존한다. 범위 밖 변경은 되돌리거나
  덮어쓰지 않는다.
- 브랜치 이름에 `codex`를 넣지 않는다. `feature/`, `fix/`, `docs/`, `chore/` 또는
  사용자가 지정한 이름을 사용한다. `main`에 직접 커밋하지 않는다.

## 프로젝트와 주요 경로

LALA-next는 FastAPI, PostgreSQL/PostGIS/pgvector, Flutter로 구성된 로컬 여행·체험
추천 플랫폼이다.

- `apps/api/`: FastAPI API
- `apps/flutter_app/`: Flutter 앱
- `apps/workers/`: 배치·파이프라인 워커
- `clients/flutter/`, `clients/flutter_generated/`: Dart API 클라이언트와 생성 코드
- `sql/canonical/`: 정식 SQL 마이그레이션
- `scripts/unix/`, `scripts/windows/`: 실행·운영·검증 스크립트
- `docs/operations/`: 현재 운영 계약과 인계 문서

API를 변경할 때는 서버 스키마, OpenAPI, 생성 Dart 패키지, 수동 adapter와 DB
호환성을 함께 검토한다. 생성 코드와 adapter를 중복이라는 이유로 삭제하지 않는다.
인증은 `lib/auth/`의 Logto SDK 경계를 유지하며 직접 토큰 관리로 대체하지 않는다.
지도·위치의 web/native/stub 조건부 구현과 데이터 출처 표시를 보존한다.

## 비밀·환경·API 경계

비밀 작업의 상세 기준은 다음 두 문서가 단일 기준이다.

- `docs/operations/aws-secrets-manager-runtime-contract.md`
- `docs/operations/aws-secrets-manager-team-handoff.md`

충돌이 있으면 런타임 계약과 현재 코드의 `apps/api/app/core/runtime_secrets.py`를
우선 확인한다.

### 런타임 프로필

- `api`와 `worker`는 프로세스 IAM 역할과 AWS Secrets Manager만 사용한다. 운영
  런타임에 개발자 dotenv나 개인 AWS 자격증명을 복사하지 않는다.
- `ci`는 명시적으로 주입된 테스트 환경값만 사용한다. AWS나 dotenv를 조회하지
  않는다.
- `local`만 명시적인 로컬 dotenv를 사용할 수 있다. 로컬에서 AWS 비밀을 읽는
  동작은 `LALA_LOCAL_USE_AWS_SECRETS`를 통한 명시적 opt-in이다.
- 필수 비밀이 없거나 접근이 거부되거나 형식이 잘못되면 fail closed한다. 필요한
  논리 이름만 보고하고 중단하며 값을 추측하거나 mock·snapshot으로 통합 검사를
  통과시키지 않는다.

### AWS 서비스와 클라이언트 설정

- SSM Session Manager/Run Command는 접속과 명령 실행에 사용한다.
- SSM Parameter Store는 승인된 공개 빌드 설정의 mapping에 사용한다.
- Secrets Manager는 서버 API·worker 런타임 비밀에 사용한다.
- Flutter에는 클라이언트에서 공개되는 값만 전달한다. 예: 승인된 개발 API URL,
  `LALA_BUILD_SHA`, URL 제한이 적용된 지도 client ID, 공개 Logto endpoint/client ID.
- `DB_DSN`, AWS 자격증명, AI·Speech 키, 서버용 NAVER Search 비밀, Logto 관리
  자격증명, API bearer token과 서버 API 키를 Flutter 빌드, Dart define, Git 문서에
  넣지 않는다.

### 취급 규칙

- 비밀값, 전체 DSN, 토큰, 전체 환경 파일, 정밀 위치와 개인정보를 stdout/stderr,
  로그, 클립보드, 셸 명령 인자, 커밋, PR, 이슈, 스크린샷, 채팅, 인계 문서 또는
  산출물에 노출하지 않는다. 필요한 경우 환경변수나 논리 비밀의 **이름만** 쓴다.
- 운영 `.env`를 worktree, 개발자 PC 간, 시뮬레이터, CI 또는 앱 artifact로 복사하지
  않는다.
- 비밀 동기화와 운영 변경은 값 없는 inventory/plan을 먼저 검토하고, 대상과 영향이
  확인된 뒤 별도의 명시적 apply 단계로 실행한다.
- 노출이 의심되면 문서나 Git에서 지우는 것으로 끝내지 않는다. 공급자 자격증명을
  폐기·회전하고 로컬 사본과 CI·접근 로그를 확인한다.
- 실시간 비밀 조회, IAM 변경, DB 쓰기, 배포, 유료 AI·음성 호출은 해당 작업에 대한
  사용자의 명시적 지시가 있을 때만 수행한다.

## 개발과 검증

```bash
uv sync --extra dev
uv run pytest apps/api/tests
uv run ruff check .
uv run ruff format --check .
cd apps/flutter_app && flutter analyze && flutter test
```

- 커밋 전 `uv run pre-commit run --all-files`를 실행한다. hook이 파일을 수정할 수
  있으므로 먼저 작업 범위와 diff를 확인한다.
- 검사 목적이면 formatter의 쓰기 모드를 사용하지 않는다. SDK나 외부 환경이 없어
  건너뛴 검사를 통과로 보고하지 않는다.
- 운영 비밀 없는 단위·계약 검사는 `ci` 프로필 또는 상속 환경을 제거한 별도
  subprocess에서 실행한다.
- 앱·API 실행, 실기기 검사, DB-backed 통합 검사와 문서·정적 검사를 구분해 보고한다.
- 공개 개발 API URL을 명시적으로 확인하기 전에는 운영 API 주소를 개발 환경의
  대체값으로 사용하지 않는다.

## 협업과 보고

- 커밋은 conventional commit 형식을 사용하고 관련 변경만 작은 단위로 묶는다.
- 라우터·테마는 프론트엔드, API·OpenAPI는 백엔드, 공유 상태·SQL·환경은 기술
  리드와 관련 역할이 함께 리뷰한다.
- 확인된 사실, 제안, 미결정 사항을 구분한다. 코드 테스트, 문서 검수, 실환경 검증의
  증거를 서로 대신 사용하지 않는다.
- 회의 원문, 개인 일정, 계정 정보, 대형 원본 파일을 공개 저장소에 복제하지 않는다.
