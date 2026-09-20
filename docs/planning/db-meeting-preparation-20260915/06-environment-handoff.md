# 개발 환경과 협업 가이드 인계

상태: **개발·검증 순서와 DB 도구 결정 / 환경 구성·인계 대기**. 진희님이 조사한 로컬 → CI → 스테이징 → 운영 구분에 LALA의 실제 구성과 차이를 대응하였다. 클라우드 생성·설정 변경·배포는 수행하지 않았다.

## 9월 15일 회의 결정

1. 로컬에서 담당 기능을 검사하고, CI에서 통합 검사를 거쳐 스테이징에서 사용자 관점의 QA를 한 뒤 프로덕션으로 배포한다.
2. FastAPI 백엔드의 ORM은 SQLAlchemy, DB 마이그레이션은 Alembic을 사용한다.
3. 운영 DB는 개발 시험 대상으로 사용하지 않는다. 로컬·CI는 격리된 비운영 DB와 seed를 사용한다.
4. 개발 API 주소·시험 계정·적용 DB 구조·승격 조건은 아직 인계되지 않았으므로 구현 착수 전에 담당과 완료 조건을 정한다.

SQLAlchemy·Alembic 선택은 확정했지만, 현재 canonical SQL 21개를 Alembic의 최초 기준선으로 삼을지 마이그레이션 이력으로 옮길지는 정하지 않았다. 운영 DB의 확인된 차이를 자동으로 삭제하거나 역변경하지 않는다.

## 현재 환경표

| 층 | 9/15 확인한 사실 | 준비 상태·해야 할 일 | 담당·리뷰 제안 |
|---|---|---|---|
| 코드 기준 | DB 조사는 main `765570a2`, dev는 `9989e987` 기준. 현재 main은 PR #210·#212 병합 뒤 `41468b01` | SQL 069~071이 추가됐으므로 현재 main 기준 구조 대조를 다시 실행. ERD 기준 SHA를 계속 명시 | 건동·진희 |
| 로컬 DB 구성 | compose.local.yml: PostgreSQL 16 + PostGIS/vector, loopback 포트 기본 55432 | 구성 존재. 이 PC의 .env DB 연결은 connection refused. 이번에 DB를 시작/생성하지 않음 | 건동 / 진희 |
| 운영 DB | AWS RDS PostgreSQL 15.18, PostGIS 3.4.6, vector 0.8.2 | 구조 조회 완료. 068 차이와 RAG 추가 구조 확인 | 건동 / 진희 |
| 기존 로컬 Azure 설정 | .env.local의 PostgreSQL 주소 DNS 미확인 | 사용할 개발 주소로 인증하지 않음. 파일은 보존 | 건동 |
| 공용 개발 구성 | GitHub environment dev 존재. 마지막 배포 2026-06-23, dev SHA `9989e987`, 과거 성공 | 현재 API URL·가동 상태·앱/API/SQL 조합 미확정 | 건동 / 진희 |
| Azure 접근 | CLI에서 보이는 구독 1개가 GitHub dev 배포 구독과 다름 | 해당 개발 환경의 현재 리소스를 이 권한으로 확인하지 못함. “개발 환경 없음”으로 결론내리지 않음 | 건동 |
| CI | Python 3.13 API·wrapper·pre-commit, Flutter, 일회용 PostgreSQL 회귀 job | canonical SQL 적용과 지정 4개 회귀 suite는 검사함. dev seed·전체 API DB 통합을 보장하는 것으로 확대 해석하지 않음 | 진희 / 건동·찬혜 |
| 서버 배포 | main의 CI 성공을 따라 EC2 deploy workflow 실행 구성 | 배포는 검사와 별도 단계. 현재 workflow는 origin/main을 다시 조회하므로 CI가 검사한 SHA와 배포 SHA 일치 확인 필요 | 건동 / 진희 |

GitHub dev environment의 보호 규칙 개수는 조회 시 0개였다. 이는 저장소 전체 branch protection이 없다는 뜻이 아니다. 실제 필수 검사·리뷰 설정은 팀 운영 절차를 확정할 때 별도로 확인한다.

## 팀에 제시할 환경 권고

1. **로컬/DB 통합 검사의 기준은 우선 현 운영 PostgreSQL 15 계열에 맞추는 안**을 제시한다. 현재 compose 16을 그대로 표준으로 확정하면 버전 차이를 안고 검증하게 된다. 운영 16 승격을 선택한다면 호환성·확장·복구 검토를 별도 계획한다. 이번에 이미지나 운영 버전을 바꾸지 않았다.
2. **프론트엔드 화면 작업은 mock·widget 검사와 공용 개발 API 연동을 중심으로 한다.** DB 담당·백엔드에게 필요한 로컬 DB를 모든 팀원의 필수 설치로 일괄 지정하지 않는다.
3. **현재 DB CI는 격리된 PostgreSQL에 canonical SQL을 적용하고 지정 회귀 suite를 실행한다.** dev seed와 전체 사용자 흐름 통합은 아직 포함하지 않는다. SQL 068·069~071과 operator-pending 차이를 현재 운영 DB와 다시 대조한 뒤 범위를 확장한다.
4. 공용 개발 API는 주소·담당·계정·데이터·적용 SQL·앱/API SHA 조합을 인수한 뒤 사용한다. 운영 API/DB를 개발 주소의 기본 대체값으로 쓰지 않는다.

## 설정·시크릿·접근 경계

| 항목 | 사용하는 곳 | 인계할 내용 |
|---|---|---|
| LALA_RUNTIME_PROFILE=local | 로컬 API | 명시한 개발 설정으로 실행. 단순 .env 파일명만으로 환경을 판별하지 않음 |
| LALA_LOCAL_ENV_FILE / DB_DSN | 로컬 API·DB 담당 | 확인한 비운영 대상 파일·연결 경로. 값은 개인/승인된 보안 경로로 전달 |
| LALA_RUNTIME_PROFILE=ci | CI | 운영 비밀을 사용하지 않는 검사 프로필 |
| api / worker 프로필 | 배포 서비스 | AWS Secrets Manager 계약. dotenv나 과거 Key Vault를 임의 대체 경로로 사용하지 않음 |
| AWS_REGION / LALA_AWS_SM_PREFIX | 운영 런타임 | 비밀을 찾을 위치·논리 이름. 앱 공개 빌드 설정과 구분 |
| LALA_API_BASE_URL | Flutter | 전달받은 공용 개발 API 주소를 명시. 프론트에 DB 접속 비밀 전달 불필요 |
| SSM Parameter Store | 공개 빌드 설정 | allowlist에 속하는 빌드 값. 서버 비밀과 구분 |
| SSM Run Command | 서버 운영 접근 | 이번에는 catalog SELECT 실행에만 사용. 배포·재시작 명령과 구분 |

현재 소스의 Python 요구는 >=3.11, CI는 3.13이다. Flutter CI는 stable 채널을 설치하며 정확 버전 고정은 없다. Dart SDK 제약·Python lockfile·Flutter lockfile을 함께 인수하고 성공한 개발 조합의 정확 버전을 기록한다. 최신 버전으로 임의 교체하지 않는다.

## 진희님 가이드와 대조할 표

| 가이드의 일반 설명 | LALA에 적용할 보정 | 확인 완료 조건 |
|---|---|---|
| 개발자별 docker compose DB | 구성은 존재하지만 현재 운영과 메이저 버전 차이. 담당 작업에 따라 DB 필요 여부 다름 | 재현 버전·확장·seed 범위 기록 |
| .env.local에 로컬 DB 주소 | 이 PC의 기존 .env.local은 과거 Azure 대상. runtime profile·명시 파일 경로로 통제 | 운영/과거 주소가 자동 선택되지 않음을 확인 |
| DATABASE_URL로 환경 전환 | 이 저장소의 논리 설정 이름은 DB_DSN, api/worker는 Secrets Manager | 실제 설정 이름과 프로필 우선순위 일치 |
| CI에서 PostgreSQL service container | service container 대신 도구가 일회용 Docker PostgreSQL을 생성·삭제 | canonical 적용·지정 회귀 범위와 dev seed·전체 통합의 차이를 기록 |
| migration 도구로 스키마 일치 | 신규 기준은 SQLAlchemy ORM + Alembic. 기존 canonical SQL과 guarded plan/apply 경로가 이미 존재 | 21개 파일과 operator-pending 차이의 기준선·이관·검증·복구 방법 합의 |
| PR merge 또는 배포 전 스테이징 검사 | main CI → EC2 배포 구성이 있고, Azure dev는 별도 과거 lane | 병합 전/후 검사 위치·기준 SHA·배포 승격 조건 명시 |

Prisma 등 일반 예시를 현재 Python API가 사용하는 migration 도구라고 소개하지 않는다. 기존 SQL canonicalization 문서의 Azure SSOT·8개 파일 목록도 과거 설명이므로, `765570a2`의 18개 파일 조사 결과와 현재 main의 21개 파일 manifest를 구분해 제공한다.

## 인수할 공용 개발 환경 카드

| 필드 | 현재 상태 | 완료 조건 |
|---|---|---|
| API 주소·접근 방법·담당 | 현재 주소 미확정 / 건동 확인 과제 | 팀에 전달된 명시적 개발 URL·인증/CORS·연락 담당 |
| API SHA·앱 SHA·DB 구조 | 개발 환경 미대조 | 셋의 조합과 적용 SQL manifest·차이 기록 |
| 시험 계정 A/B·게스트 | 실제 계정 미준비·미확인 | 계정별 격리와 역할 범위, 안전한 자격증명 전달 |
| 데이터·초기화 | 미결정 | 정상/빈 결과/장소 누락 fixture, 초기화 주체·비운영 범위 |
| 장애 시 가능한 검사 | 정적 분석·단위·widget/mock 검사 | 공용 API 없이 가능한 범위가 안내됨 |
| 장애 시 미루는 검사 | 인증·서버 저장·기기 간 동기화·외부 지도/음성 통합 | 완료로 표시하지 않고 실패/보류 사유 기록 |

근거: [compose.local.yml](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/compose.local.yml), [CI](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/.github/workflows/ci.yml), [EC2 deploy](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/.github/workflows/deploy.yml), [Azure dev deploy](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/.github/workflows/azure-dev-deploy.yml), [runtime secret 계약](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/api/app/core/runtime_secrets.py).
