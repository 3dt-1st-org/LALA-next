# SQLAlchemy·Alembic 점진 전환안

상태: **김건동 초안 완료 / 박진희 공동 검토·팀 확정 대기**

## 확인된 현재 상태

- 팀은 FastAPI ORM에 SQLAlchemy, DB 마이그레이션에 Alembic을 사용하기로 결정했다.
- 현재 `pyproject.toml`과 lockfile에는 SQLAlchemy·Alembic이 없고, API repository와 작업 도구는 주로 `psycopg2`와 명시적 SQL을 사용한다.
- 현재 공식 구조 이력은 `sql/canonical/`의 순서가 고정된 18개 SQL이다.
- 코드 기준과 실제 DB에는 SQL 068의 미적용 구조와 `rag.knowledge_chunks.embedding_generation` 차이가 있다.
- 운영 PostgreSQL은 15.18이고 로컬 compose는 PostgreSQL 16이다.

## 권고안

**기존 canonical SQL을 동결된 기준선으로 보존하고, 검증된 기준선 이후의 새 변경부터 Alembic으로 관리한다. SQLAlchemy repository 전환은 기능 단위로 점진 진행한다.**

이 방식을 권하는 이유는 기존 18개 SQL과 실제 DB의 차이를 숨기지 않으면서도 새 변경 이력을 한 도구로 모을 수 있기 때문이다. 현재 raw SQL repository를 한 번에 바꾸면 API 계약과 동시성 처리가 함께 달라질 위험이 크다.

## 단계별 적용

| 단계 | 작업 | 산출물·완료 조건 |
|---|---|---|
| 0. 기준선 동결 | canonical 18개 파일·hash·기준 SHA와 실제 DB 차이를 기록 | PR #209의 구조 대조표를 팀이 수락 |
| 1. 환경 결정 | PostgreSQL 15 기준 유지 또는 16 승격 선택, 확장 버전 기록 | 로컬·CI·스테이징의 버전 조합 확정 |
| 2. 차이 판정 | SQL 068과 RAG 추가 컬럼을 적용·보류·운영 전용 중 하나로 결정 | 자동 삭제 없이 각 차이의 처리표 확정 |
| 3. Alembic 도입 | dependency, `alembic.ini`, 환경 설정, baseline revision 추가 | 시크릿을 파일에 넣지 않고 로컬·CI에서 revision 확인 |
| 4. 기존 DB stamp | 실제 구조가 승인된 기준선과 일치할 때만 baseline revision을 stamp | stamp 전 구조 검증 결과와 담당 승인 기록 |
| 5. 새 변경 | baseline 이후의 구조 변경을 Alembic revision으로 작성 | 빈 DB upgrade, 기존 DB upgrade, downgrade/복구 판단 통과 |
| 6. ORM 점진 전환 | 신규 repository부터 SQLAlchemy 2.x session·model 도입 | 기능별 API 계약·트랜잭션·동시성 검사 유지 |

## 새 DB와 기존 DB의 재현 절차

### 빈 로컬·CI DB

1. PostgreSQL·PostGIS·pgvector 버전을 준비한다.
2. 동결된 canonical 18개 SQL을 순서대로 적용한다.
3. 합의한 SQL 068·RAG 차이 처리안을 적용한다.
4. 구조 검증을 통과하면 Alembic baseline revision을 stamp한다.
5. `alembic upgrade head`를 실행한다.
6. 필요한 로컬 전용 seed를 적용하고 repository 통합 검사를 실행한다.

### 기존 스테이징·운영 DB

1. catalog를 읽기 전용으로 추출해 기준선과 비교한다.
2. 예기치 않은 차이가 있으면 stamp·upgrade를 중단한다.
3. 백업·복구 연습, lock·statement timeout, 예상 SQL을 검토한다.
4. 승인된 창에서 baseline stamp 또는 revision 적용을 수행한다.
5. 적용 SHA·revision·검증 결과를 배포 기록에 남긴다.

`alembic stamp`는 DB 구조를 만들어 주지 않는다. 구조가 맞다는 검증 없이 기존 DB를 최신 revision으로 표시하면 안 된다. `--autogenerate` 결과도 운영 차이를 근거로 테이블·컬럼을 자동 삭제하는 명령으로 사용하지 않는다.

## SQLAlchemy 책임 경계

| 영역 | 전환 원칙 |
|---|---|
| View/API schema | 공개 요청·응답 계약 유지. ORM 객체를 직접 반환하지 않음 |
| Service | 업무 순서·오류 의미 유지. session 생명주기를 화면/API 계약과 섞지 않음 |
| Repository | 기능 단위로 raw SQL 또는 SQLAlchemy 구현을 선택하고 트랜잭션 경계를 명시 |
| Model/metadata | 새 마이그레이션의 의도와 일치. 운영 DB를 자동 반영 대상으로 취급하지 않음 |
| Alembic | 구조 이력만 담당. seed·사용자 데이터·비밀값을 revision에 넣지 않음 |

우선 전환 후보는 계정 소유 관계가 단순하고 테스트가 있는 `planning.user_saved_places`다. `expected_revision`을 사용하는 취향·일정별 override와 배치·RAG 경로는 동시성·성능 검증 뒤 전환한다.

## 팀이 확정할 질문

| 질문 | 권고 | 결정 담당 |
|---|---|---|
| 기준 PostgreSQL | 운영과 같은 15 계열로 로컬·CI를 먼저 맞춤 | 김건동·박진희 |
| canonical 18개 처리 | 삭제·재작성 없이 동결 baseline으로 보존 | 김건동·박진희 |
| SQL 068 | 보류 기능이지만 구조 적용 여부를 별도 결정. 실제 DB에 없다는 사실을 숨기지 않음 | 세 개발자 |
| RAG 추가 컬럼 | operator-pending 정의의 공식 편입 여부 결정 | 김건동·박진희 |
| 첫 ORM 전환 | 저장 장소 repository부터 작은 PR로 시작 | 박진희·김건동 |
| downgrade | 데이터 손실 revision은 자동 downgrade 대신 백업 복구 절차 사용 | 기술 리드 |

A-06은 전환 초안까지 작성했다. 박진희의 환경 조사와 함께 PostgreSQL 버전·기준선·첫 전환 repository를 확인한 뒤 구현 PR로 분리한다.
