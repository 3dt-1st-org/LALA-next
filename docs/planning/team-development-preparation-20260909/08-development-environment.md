# 공용 개발 API와 개발 환경 준비표

상태: **공용 개발 API 우선 확정 / 개발 Azure 런타임 인수 대기**. 준비 조사 뒤 사용자의 별도 지시로 main CI와 운영 EC2 API 자동 배포를 실행·확인했다. 개발 전용 API·DB의 현재 가동·분리 상태는 여전히 인수되지 않았다.

## 1. 확인한 사실과 한계

조사일 2026-09-09, 갱신일 2026-09-10. GitHub 배포 설정과 현재 Azure CLI 접근 범위를 추가로 대조했다. 계정·구독·리소스 ID·주소 원문·시크릿 값은 공개 문서에 싣지 않는다.

| 조사 | 확인 사실 | 판단 한계 |
|---|---|---|
| 저장소·운영 문서 검색 | 확정된 공용 개발 전용 API 주소를 찾지 못함 | 다른 비공개 안내나 별도 계정까지 조사한 것은 아님 |
| AWS us-east-1 EC2 메타데이터 | Name에 lala/LALA가 포함된 인스턴스 1개, running | 조회한 이름·환경 태그로 dev/prod 구분 불가 |
| 같은 계정·리전 RDS 메타데이터 | 식별자에 lala가 포함된 PostgreSQL 인스턴스 1개, available | DB 내부의 개발 데이터베이스·계정 분리는 미확인 |
| GitHub environment dev | 실제 존재, protection rule count 0 | 현재 개발 API의 가동·접근을 보장하지 않음 |
| Azure Dev Deploy 이력 | 2026-06-23 성공, dev SHA 9989e987b47f7e4d62d53e1d439aba1e6f6c7f8e | 과거 성공이며 현재 API·DB·후보 계약 호환성은 미검증 |
| GitHub dev OIDC 설정 | workflow가 요구하는 OIDC·구독·resource group·CORS 값이 등록됨. 기본값을 쓰는 선택 항목 2개는 미등록 | 값의 존재만 확인. 권한 유효성·현재 리소스 상태는 보장하지 않음 |
| GitHub dev 비밀 metadata | 등록 2개, 필수 PostgreSQL 관리자 비밀 이름 존재 | 값 조회·유효성·회전 상태는 확인하지 않음 |
| 현재 Azure CLI 접근 | 로그인된 enabled 구독 1개가 GitHub dev의 배포 구독과 불일치 | 이 로그인으로 dev 리소스의 존재·상태를 판정할 수 없음 |
| Azure Resource Graph | 현재 로그인 구독에서 LALA 이름·기본 resource group과 일치하는 리소스 0개 | 배포 구독이 다르므로 “개발 환경 없음”의 증거가 아님 |
| 앱 설정 | 기본 API 주소가 운영 주소로 지정됨 | 실제 실행하지 않음 |
| API 시작 스크립트 | 기본 프로필 api, 기본 바인딩 0.0.0.0 | 단순 실행을 안전한 로컬 검사로 안내하면 안 됨 |
| EC2 배포 workflow | main의 CI 성공 후 origin/main을 배포하는 구성. 후속 지시 뒤 `e64ed058` 배포 성공 확인 | 서버 내부의 SQL head와 Flutter 앱 배포는 확인하지 않음 |
| 운영 API 후속 확인 | main `e64ed058` CI와 EC2 자동 배포 성공, `/healthz`·`/readyz` HTTP 200·DB-backed | 개발 환경 인수 또는 Flutter 앱 배포를 뜻하지 않음. SQL 068 적용 수준은 미확인 |

사용한 읽기 전용 호출은 AWS STS·EC2·RDS metadata, GitHub environment·deployment·workflow metadata, Azure account metadata와 Azure Resource Graph다. 다른 계정·구독·리전·태그 없는 리소스·호스트 내부를 포괄하지 않는다. **개발 환경이 없다는 결론이 아니라 현재 권한으로 가동 상태를 확인하지 못한 상태**다.

보충 인계의 단서를 GitHub API와 저장소 파일로 재확인했다. [과거 Azure 배포 실행](https://github.com/3dt-1st-org/LALA-next/actions/runs/28034229769), [개발 배포 문서](../../operations/azure-dev-deployment.md), [workflow](../../../.github/workflows/azure-dev-deploy.yml), infra/azure/를 개발 환경의 추가 출발 자료로 사용한다. 오래된 Azure 개발 환경과 AWS 운영을 하나의 현재 환경으로 합쳐 설명하지 않는다.

dev workflow에는 경로 필터가 있는 dev push와 workflow_dispatch가 있고 live AI·Speech의 기본 활성 표현이 있다. dev를 무조건 안전한 검사용 push 대상으로 사용하지 않는다. 과거 Azure Key Vault 배포와 현재 후보 api/worker의 AWS Secrets Manager 계약의 호환성도 인수 항목이다. 이번에는 Resource Graph로 **접근 중인 구독의 metadata만** 조회했고, 배포 구독의 리소스·Key Vault 비밀·DB 내용은 조회하지 않았다.

### 2026-09-10 판정

GitHub 설정은 “다시 배포할 수 있는 구성 흔적”이며, 현재 사용할 공용 개발 환경의 인수 증거는 아니다. 마지막 GitHub deployment는 2026-06-23의 `dev 9989e987` 성공으로 끝나고 environment URL도 기록되지 않았다. 그 이후의 Container App 상태, API 이미지 SHA, PostgreSQL readiness, 적용 SQL 수준은 미확인이다.

따라서 G-03의 현재 상태는 **구성 확인 / 접근 차단 / 가동 미검증**이다. 기술 리드가 다음 둘 중 하나를 제공해야 다음 단계로 넘어간다.

1. GitHub `dev`와 같은 Azure 구독의 읽기 권한을 제공해 이 문서의 조회 절차를 재실행한다.
2. 운영 비밀을 제외한 현재 상태 보고서를 제공한다. 보고서에는 조사 시각, 앱·API SHA, Container App 상태, DB·PostGIS readiness, 정적 snapshot fallback 상태, 적용 SQL head, 개발 API URL 전달 경로를 포함한다.

인수 담당자는 올바른 구독에서 `scripts/unix/verify_azure_resources.sh`와 `scripts/unix/verify_db_resources.sh`의 check-only 결과를 먼저 남긴다. 그다음 명시적으로 전달된 개발 주소의 `/healthz`와 `/readyz`를 확인한다. `readyz`에서 정상 데이터 경로가 DB-backed이고 DB·PostGIS가 configured이며 static snapshot fallback이 disabled인 경우에만 앱 통합 검사를 시작한다. 이 검사는 유료 AI·Speech 호출이나 배포를 포함하지 않는다.

## 2. 인수할 환경 카드

| 항목 | 현재 값 또는 결정할 내용 | 주 담당 |
|---|---|---|
| 공용 개발 API URL·접근 방식 | [접근 차단] GitHub dev 설정은 있으나 현재 배포 구독 읽기 권한·environment URL 없음. 운영 API를 대체값으로 쓰지 않음 | 기술 리드 |
| API 프로세스·DB·권한의 운영 분리 | [미검증] Container App·DB·Key Vault·배포 구독의 현재 상태와 운영 분리 증거 | 기술 리드 |
| 앱 SHA / API SHA / 적용 SQL 수준 | 제품 코드 기준 `e64ed058`; 운영 API 자동 배포 확인. 개발 API·Flutter 빌드 SHA와 SQL head는 [확인 필요] | 기술 리드 + 백엔드 |
| 공개 조회·인증 테스트 경로 | 장소 조회, 저장 계정 API, 인증 callback·CORS 등록 | 백엔드 + 프론트 |
| 개발 계정 | 게스트 경로 + 서로 다른 Logto 시험 계정 A/B. 자격증명은 비공개 전달 | 백엔드 + 기술 리드 |
| 비밀 backend·프로필·공개 allowlist | registry·승인된 region/prefix/mapping·IAM·존재 metadata를 순서대로 확인 | 기술 리드 |
| 개발 데이터 | 안정적인 장소 ID, 정상·빈 결과·장소 누락 사례, 사용자별 저장 상태 | 백엔드 + DB |
| 데이터 준비·초기화 | 비운영 대상, 소유자, 복구·초기화 범위와 실행 절차 | DB·인프라 |
| 실환경 인수 기록 | 앱/API SHA, 검사 일시, 플랫폼·언어, 성공·실패, 담당 역할 | 기능 담당 |
| 비용·자원 구성 | 별도 환경이 없다면 구성안·예상 비용·운영자 검토부터 작성 | 기술 리드 |

확인 요청은 위 카드의 빈칸을 한 번에 모아 기술 리드가 정리한다. 환경 생성, 실제 IAM 변경, DB 초기화는 인수 카드가 채워진 뒤 별도 작업이다.

## 3. 선택 전 두 코드 기준과 버전

| 항목 | main 9e312bb4 | 후보 8aa184e3 | 준비 규칙 |
|---|---|---|---|
| Python / 주요 CI | 3.13 | 3.13 | uv.lock 유지. 팀의 실제 patch 버전은 환경 인수 때 기록 |
| Dart SDK 제약 | ^3.12.0 | ^3.12.0 | 이 제약을 만족하는 Flutter SDK로 확인 |
| Flutter CI | stable 채널, 정확 버전 미고정 | 같음 | 성공한 빌드의 정확 버전으로 고정안 작성. 최신 버전 임의 업그레이드 안 함 |
| flutter_riverpod / riverpod lock | 2.6.1 / 2.6.1 | 같음 | 사용 여부 결정과 패키지 업그레이드는 별도 |
| go_router lock | 14.8.1 | 같음 | 구조 예제에서 라우팅 체계 교체 안 함 |
| Logto Dart SDK lock | 3.0.0 | 같음 | 기존 SDK·gateway 유지 |
| 추가 후보 의존성 | 기기 TTS·open-map asset 추가 없음 | flutter_tts·open-map asset 추가 | 선택한 코드 기준에 맞춰 준비 |

근거는 각 SHA의 .python-version, .github/workflows/ci.yml, 앱 pubspec.yaml·pubspec.lock이다. 코드상 저장 API·SavedPlacesPage·TripLibraryRemote는 두 기준에서 동일하다. TripLibraryStore에는 후보의 로딩 Future zone 보완이 있다. 자세한 계약은 [구조 예제](09-mvvm-and-api-contracts.md)를 본다.

## 4. 역할별 접근

| 역할 | 필요한 기본 접근 | 추가 접근이 필요한 경우 |
|---|---|---|
| 프론트 | 코드·SDK, 공개 빌드 설정, 공용 개발 API, 시험 계정 | 지도·Logto의 개발 origin/callback 등록 요청 |
| 백엔드 | API 코드·검사, 개발 데이터 계약, 시험 계정 | 개발 서비스 로그·개발 DB는 맡은 범위로 |
| DB·인프라·기술 리드 | 환경 메타데이터·개발 배포·DB 구조 관리 | 운영 변경은 목적·대상·승인이 있는 별도 작업 |
| PM·데이터 분석 | 실행 가능한 검수 빌드, 피드백·집계 결과 | 원시 개인정보·운영 비밀을 기본 접근으로 주지 않음 |

SSM Run Command/Session Manager는 접속·명령 실행, SSM Parameter Store는 공개 빌드 설정의 승인된 mapping, Secrets Manager는 서버 런타임 비밀 관리에 쓰인다. 세 용도와 권한을 구분한다. 프론트엔드 전원에게 로컬 API·DB 설치를 요구하지 않는다.

## 5. 설정과 데이터 전달

공개 빌드 설정은 LALA_API_BASE_URL, LALA_BUILD_SHA, NAVER_MAP_CLIENT_ID, 후보의 LALA_OPEN_MAP_STYLE_URL처럼 클라이언트에서 공개되는 용도를 확인한 항목만 전달한다. Logto endpoint·client ID·callback도 개발 등록값을 담당자가 확인한다.

DB_DSN, 서버 Naver Search 비밀, AWS 자격증명, AI·Speech 키, 서버 API 키·bearer token은 앱 빌드나 Git 문서에 넣지 않는다. 기존 앱이 지원하는 LALA_API_BEARER_TOKEN·LALA_IOS_API_KEY를 팀 공통 빌드 값으로 배포하지 않는다. 환경 파일 전체를 전달하거나 로그에 출력하지 않는다.

fixture는 단위·widget·오류 상태 검사에만 사용한다. 공용 API나 DB가 준비되지 않은 상태에서 fixture 성공을 통합 검증 통과로 보고하지 않는다.

서버 api/worker 프로필은 AWS Secrets Manager 경로를 사용한다. ci는 제공된 환경값만 사용하며 local은 환경값 우선·AWS 명시 opt-in이다. dotenv 로딩은 명시 local 조건을 확인한다. 근거는 [런타임 계약](../../operations/aws-secrets-manager-runtime-contract.md)과 후보 core/runtime_secrets.py다.

Flutter 공개 설정 wrapper는 이미 설정된 값을 먼저 채택하는 경로가 있고, 승인된 map ID에 operator-supplied Parameter Store mapping → Secrets Manager → 신뢰된 로컬 파일 fallback을 지원한다. 항상 SSM이 최우선이라고 일반화하지 않는다. 항목의 부재(absent), 접근 거부(denied), 일시 불가(unavailable), 형식 오류(invalid)를 분리하며 권한·리전 차이를 비밀 누락으로 단정하지 않는다.

사용자 인계에 기존 로컬 환경 파일도 있다는 단서가 있다. 이번에는 값을 열거나 새 키 발급·재입력을 요구하지 않았다. AI 경로는 Standard OpenAI이며 Azure OpenAI로 바꾸지 않는다. Azure Speech는 별도 선택적 음성 의존성이다. 설정 확인을 위한 유료 호출은 하지 않는다.

## 6. 실행 명령의 목적 구분

아래는 준비한 명령 예시이며 앱·API를 이번에 실행한 결과가 아니다. 저장소 루트에서 실행한다.

### 검사 전 의존성·hook 준비

~~~bash
uv sync --extra dev
uv run pre-commit install
~~~

의존성 설치와 hook 설치는 로컬 변경이다. pre-commit에는 자동 수정 hook이 있으므로 전체 실행 전 diff를 확인한다.

### 운영 비밀 없이 API 계약 검사

상속된 DB·클라우드·인증 설정을 전달하지 않는 subprocess 환경을 사용한다. 저장소 루트에서 uv sync 후 실행한다.

~~~bash
python3 - <<'PY'
import os
import subprocess
from pathlib import Path

runner = Path(".venv/Scripts/python.exe" if os.name == "nt" else ".venv/bin/python")
allowed = ("PATH", "HOME", "USERPROFILE", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "TMPDIR")
check_env = {key: os.environ[key] for key in allowed if key in os.environ}
check_env.update(LALA_RUNTIME_PROFILE="ci", AWS_EC2_METADATA_DISABLED="true")
subprocess.run(
    [str(runner), "-m", "pytest",
     "apps/api/tests/test_openapi_contract.py",
     "apps/api/tests/test_openapi_compat.py",
     "apps/api/tests/test_canonical_sql.py",
     "apps/api/tests/test_planning_endpoints.py",
     "apps/api/tests/test_planning_repository.py"],
    env=check_env, check=True,
)
PY
~~~

이 검사는 주입된 저장소·fixture를 사용한다. 실 Logto·DB·네트워크 인수 검사는 아니다. Windows에서는 같은 Python 내용을 파일 또는 Python 입력으로 실행한다.

### 소스 수정 없는 정적 검사

~~~bash
uv run ruff check .
uv run ruff format --check .
~~~

Flutter 앱 디렉터리에서 의존성을 준비한 뒤 아래를 실행한다.

~~~bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
~~~

SDK가 없거나 의존성이 준비되지 않았다면 미실행이다. 기존 verify wrapper의 formatter·SDK 생략 동작과 구분한다.

### 공용 개발 API로 앱 실행

아래 shell 변수에는 인수 카드에서 확인한 **공개 개발 주소**만 넣는다. 사용자별 비밀을 포함하지 않는다.

~~~bash
: "${LALA_TEAM_DEV_API_URL:?개발 전용 API 주소를 먼저 확인하세요}"
flutter run --dart-define=LALA_API_BASE_URL="$LALA_TEAM_DEV_API_URL" \
  --dart-define=LALA_BUILD_SHA="$(git rev-parse HEAD)"
~~~

팀원이 Windows라면 같은 두 dart-define 값을 PowerShell 인자로 전달한다. 실행 명령만으로 origin·인증·지도 구성이 완료되지는 않는다. 해당 플랫폼의 개발 등록값은 인수 카드와 함께 전달한다.

기존 scripts/unix/flutter_with_build_env.sh를 사용할 때도 승인된 개발 주소를 --api-base-url로 반드시 명시한다. wrapper 기본 주소 역시 운영이며, 공개 설정 조회와 로컬 파일 fallback이 있을 수 있어 준비 문서 검사를 위해 실행하지 않는다. 실제 빌드 때만 담당자가 공개 allowlist·지역·mapping과 비공개 전달 범위를 확인한다.

### 백엔드 담당자의 선택적 로컬 서버

운영 비밀이 없는 별도 checkout과 검토된 로컬 개발 설정에서만 다음 명령을 쓴다.

~~~bash
scripts/unix/start_api.sh --runtime-profile local --host-name 127.0.0.1 --port 8080
~~~

local 프로필은 dotenv를 읽을 수 있다. 기본 .env를 무조건 복사하거나 기존 운영 .env를 불러오지 않는다. 서버 구동, 실제 DB 적용, live AI·Speech는 check-only와 별개다.

## 7. 장애와 개발 기준 선택

- 공용 API 장애 시: 프론트는 fixture 기반 표시·상태 검사, 백엔드는 단위·계약 검사까지 진행한다. 저장·동기화·지도·음성 통합 결과는 대기한다.
- 화면 자료와 독립적으로 후보 통합 추천을 채택해 제품 코드 기준을 main `e64ed058`로 고정했다. 화면 자료 수령 후에는 최종 MVP 범위에 비춰 노출 항목을 다시 확인한다.
- 과거 로컬의 5개 커밋은 일괄 cherry-pick하지 않았다. 원래 문서 브랜치도 제품 코드 기준으로 사용하지 않는다.
- 70개 추가 커밋 전체가 실증 범위가 되는 것은 아니다. 보류 기능은 보존하되 실증 완료 범위와 분리한다.
- 후속 병합·배포 전에는 필수 리뷰·CI·검증 SHA·DB 호환성·readiness·복구 담당을 합의한다. 운영 주소를 개발 API의 대체값으로 사용하지 않는다.
