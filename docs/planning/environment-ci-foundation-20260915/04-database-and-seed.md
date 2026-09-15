# 04. DB migration과 seed

상태: **기존 SQL을 유지하는 단계적 도입안**. Alembic/SQLAlchemy는 현재 프로젝트 의존성에 없다.
이번 문서에서 migration 도구 도입이나 DB 적용을 완료했다고 보지 않는다.

## 역할을 나누기

| 구분 | 목적 | LALA 현재 / 제안 |
|---|---|---|
| 스키마 baseline | 새 DB에 테이블·뷰·확장 생성 | 기존 `sql/canonical` |
| migration | 이미 데이터가 있는 DB를 다음 버전으로 변경 | 기존 plan/apply 유지, 증분 이력 관리 도입 검토 |
| 개발 seed | 개발·테스트를 재현할 샘플 데이터 | `sql/dev_reset`, 개인 로컬·일회용 CI만 |
| staging QA 데이터 | PM이 검수할 계정·장소·정상/빈 상태 | 별도 명령·대상 검사·정해진 데이터 범위로 후속 구현 |
| 서비스 기준 데이터 | 기능상 필요한 코드·분류 등 | 버전 관리·중복 실행 가능한 data migration |
| 수집 데이터 | 날씨·장소·리뷰 등 실제 provider 데이터 | worker/ingest, schema migration과 별도 실행 |

개발 seed를 staging·production에 그대로 실행하지 않는다.
현재 [dev reset](../../../sql/dev_reset/README.md)은 localhost 제한이 있으므로 이를 풀어 공유 DB에 적용하는 방식도 사용하지 않는다.
staging QA는 합성 계정 데이터와 승인된 공개 데이터로 구성하고, 운영 사용자 데이터를 원본 복사하지 않는다.

## 먼저 기존 도구로 확보할 검사

[bootstrap](../../../scripts/unix/bootstrap_local_mvp_db.sh)은 다음 단계를 선택할 수 있다.
아래는 **로컬/일회용 CI DB에 쓰는 구현용 명령 예시이며 이번 작업에서 실행하지 않았다**.
필수 전제는 개발 전용 설정, `LALA_POSTGRES_PASSWORD`, Docker, Python 의존성이다.
CI에서는 깨끗한 checkout·일회용 volume을 사용하고 bootstrap의 `.env` 로딩도 고려한다.

```bash
scripts/unix/bootstrap_local_mvp_db.sh --start-compose --apply-canonical --apply-dev-reset
scripts/unix/verify_db_schema.sh
```

bootstrap이 내부에서 만든 `DB_DSN`은 부모 shell에 남지 않는다.
별도의 `verify_db_schema.sh`나 API 통합 테스트에는 **같은 임시 DB의 접속 설정을 따로 전달**해야 한다.
첫 명령의 canonical 적용 단계에는 schema 검증도 포함된다. `--all`의 snapshot 파일 생성은 이 최소 CI에서 제외한다.
현재 Compose는 고정 container 이름을 쓰므로 새 CI job은 작업별 격리·정리 또는 독립 runner를 보장한다.

## DB CI가 잡아야 할 문제

| 검사 | 입력과 동작 | 통과 기준 |
|---|---|---|
| 새 DB 생성 | 빈 PostgreSQL에 전체 schema·seed | 필수 확장·뷰·FK·unique·주요 query 정상 |
| 기존 DB 업그레이드 | PR base의 schema + 합성 기존 데이터 → PR의 변경 | 적용 성공, 기존 행·관계·기본값·권한 동작 보존 |
| 반복 적용 | 현재 runner 또는 migration 명령을 다시 실행 | SQL 재실행이 지원하는 범위에서 성공, seed 중복 없음, 적용 이력 일관 |
| API 연결 | 실제 DB로 장소 조회·저장·목록 재조회 | 사용자 A의 저장이 B에 나타나지 않음, 실제 SQL 성공 |
| 버전 혼용 | 새 schema에 이전 지원 API/앱 계약으로 요청 | 단계적 배포 중 기존 클라이언트도 동작 |
| 실패 처리 | 실패 migration·누락 확장 사례 | 실패를 성공 처리하지 않고 다음 배포 중단 |

현재 SQL runner는 canonical 폴더 전체를 정렬해 실행한다. '가장 큰 파일 번호'만으로
실제 적용 이력·파일 내용·checksum을 증명할 수 없다.
이력 도입 전에는 검증한 SHA의 SQL manifest·hash와 schema 검사 결과를 함께 기록한다.
[operator-pending SQL](../../../sql/operator-pending/README.md)은 canonical 실행 목록으로 자동 이동하지 않는다.

## Alembic을 선택한다면

Python 백엔드와 맞는 증분 migration 후보로 Alembic을 검토한다.
이를 위해 SQLAlchemy를 사용해도 기존 repository를 전부 ORM으로 바꿀 필요는 없다.
SQL-first revision으로 기존 SQL을 이어갈 수 있다. 구체 버전·의존성은 구현 PR에서 검증해 고정한다.

1. 현재 DB가 어떤 baseline과 일치하는지 schema·SQL hash로 먼저 확인한다. 불일치 상태에서 `stamp`로 적용 완료를 표시하지 않는다.
2. baseline과 최초 revision의 경계를 정하고 빈 DB 생성·기존 DB 전환을 모두 시험한다.
3. 전환 이후에는 적용된 revision을 수정하지 않고 새 revision으로 변경한다. 여러 개발자가 만든 head 충돌도 CI에서 검사한다.
4. 같은 환경에 canonical 전체 runner와 Alembic이 독립적으로 schema를 변경하지 않게 담당 경로를 하나로 정한다.
5. 확장·뷰·인덱스·data migration은 수동 검토한다. autogenerate 결과만으로 완성 판정하지 않는다.

초기 CI를 만들기 위해 Alembic부터 반드시 도입할 필요는 없다.
**먼저 기존 SQL의 실제 DB 검증을 확보하고, 증분 이력 도입을 별도 PR로 분리**하는 것이 이번 순서다.

## 세 개발자가 함께 바꿀 때

예: 장소에 `accessibility_note`를 추가한다면 DB 개발자가 nullable 컬럼을 추가하고,
백엔드는 기존 행의 null도 처리하며 응답 필드를 추가한다. 프론트는 값이 있을 때만 표시한다.
DB 확장 → 호환 API → 프론트 순서로 merge·배포하면 이전 앱과 함께 운영할 수 있다.
컬럼 삭제·필수화는 데이터 보강과 이전 버전 지원 종료를 확인한 다음 변경으로 나눈다.

DB 개발자는 schema·seed·업그레이드 검사를, 백엔드는 실제 query·트랜잭션을,
프론트는 응답 필드·빈 상태·구버전 호환을 검토한다. 환경의 DB 적용은 한 명의 배포 담당자가 직렬화한다.
API runtime DB 계정과 DDL용 migration 계정의 권한도 구분한다.
