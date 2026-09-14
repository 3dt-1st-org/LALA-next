# 기준 코드와 실제 DB 대조

## 기준 카드

| 항목 | 확인 결과 |
|---|---|
| 기준 코드 | `765570a21ff5ab5207c627d3659e8051be6dbd98` |
| 원격 main | 9/15 조회에서 기준 SHA와 일치 |
| 원격 dev | `9989e987b47f7e4d62d53e1d439aba1e6f6c7f8e`; main과 다른 과거 개발 기준 |
| 조사 체크아웃 | main 기준으로 분리한 문서 작업 브랜치. 기존 개인 체크아웃 보존 |
| canonical SQL | `000`~`068`에 해당하는 실제 파일 18개. 번호가 연속인 69개 파일이라는 뜻이 아님 |
| 정적 구조 | 스키마 12, 테이블 53, 컬럼 471, FK 49, 뷰 7, 명시적 CREATE INDEX 51 |
| DB 대상 | 현 배포 workflow의 LALA EC2가 사용하는 AWS Secrets Manager `db-dsn` 대상. RDS metadata의 대상 호스트와 일치 확인 |
| 실제 DB 확인 시각 | 2026-09-15 07:48:04 KST / 2026-09-14 22:48:04 UTC |
| DB 버전·확장 | PostgreSQL 15.18 / PostGIS 3.4.6 / vector 0.8.2 / pgcrypto 1.3 |
| 서버 체크아웃 SHA | 기준 SHA와 일치. 프로세스가 실제로 로드한 코드·앱 배포 SHA까지 증명하지 않음 |
| 조회 방법 | 기존 SSM 경로에서 catalog SELECT. REPEATABLE READ + READ ONLY, 연결·문장·잠금 timeout, 끝에서 ROLLBACK |
| 조회하지 않은 내용 | 사용자 행·사용 기록·좌표·토큰·취향 값. 인증 API·유료 AI·음성 API를 호출하지 않음 |

현재 DB 주소·계정·비밀번호·리소스 ID·명령 식별자는 공유 문서에 포함하지 않았다. 시크릿은 기존 DB 연결에만 사용했으며 출력·파일에 저장하지 않았다.

## 구조 차이

| ID | 코드의 기대 구조 | 실제 DB에서 확인한 것 | 영향·후속 조치 |
|---|---|---|---|
| D-01 | SQL 068의 `community.chat_room_members`, `community.idempotency_keys`, `community.chat_ws_tickets` | 세 테이블 없음 | 해당 채팅·재시도·티켓 기능의 DB 준비를 전제로 하면 안 됨. 기능 진입·적용 범위와 운영 이력을 검토 |
| D-02 | `community.chat_rooms.visibility`, `created_by_issuer`, `created_by_subject` | 세 컬럼 없음 | `chat_rooms_visibility_check`, `fk_chat_rooms_creator`도 없음 |
| D-03 | SQL 068에서 추가하는 명시적 인덱스 4개 | visibility/member/expiry 관련 네 인덱스 없음 | D-01·D-02와 함께 처리할 하나의 적용 차이. 독립 기능 장애 4건으로 세지 않음 |
| D-04 | canonical의 `rag.knowledge_chunks`에는 `embedding_generation` 없음 | `integer NOT NULL DEFAULT 0` 컬럼 존재 | 같은 정의가 `sql/operator-pending/064_rag_knowledge_retrieval_metadata.sql`에 있음. 적용 시점·주체는 미조회. 공용 재현 기준에 반영할지 검토 |
| D-05 | 로컬 compose는 PostgreSQL 16 이미지 | 현 RDS 15.18 | 현재 운영을 기준으로 로컬/CI 15 계열을 맞추는 안을 먼저 검토. 16 승격은 별도 호환성·운영 작업 |

SQL 068의 추가 구조가 없다는 사실은 확인했다. **DDL 실행 이력을 조회하지 않았으므로 “어느 실행이 실패했는지”는 확인하지 않았다.** DB에만 있는 컬럼도 자동 삭제·역변경하지 않는다. 보류 기능의 테이블은 전체 개요에 보존하고, 후속 사용·배포 전에 필요한 정합성 검토를 남긴다.

## 확인 범위별 판정

| 비교 | 결과 | 한계 |
|---|---|---|
| 테이블·뷰 이름 | 코드 53개 중 테이블 50개, 뷰 7개 전부 존재 | 같은 이름의 객체가 모든 동작을 만족한다는 뜻 아님 |
| 공통 컬럼 이름·타입·NULL 여부 | 447개 일치. 누락된 테이블의 21개 컬럼과 chat_rooms의 3개 컬럼은 제외 | DEFAULT 표현식의 전체 자동 동등성 검사 미실행 |
| 실제 테이블 컬럼 | 448개: 공통 447개 + RAG 추가 컬럼 1개 | 뷰 출력 컬럼 93개는 테이블 컬럼 수에서 제외 |
| PK·UNIQUE·FK | 공통 테이블에서 103개 키 정의 일치. FK의 참조 열·삭제 동작 포함 | 행 데이터의 계정 격리·실제 삭제 결과는 미실행 |
| 이름 있는 CHECK | 공통 테이블의 67개 이름·validated=true 확인 | 모든 CHECK 표현식의 의미가 같다는 자동 판정은 하지 않음 |
| SQL 066 방문 상태 | `not_visited`, 이유 코드, 피드백 형태 CHECK와 세 추가 컬럼 확인 | API 요청·응답·앱 상태 전이는 별도 검증 |
| 인덱스 | 명시적 인덱스 이름의 누락 4개 확인 | 인덱스 표현식·연산자 클래스·실행계획·성능 검증 미실행 |
| 데이터·권한·마이그레이션 | 미검증 | 사용자 행, 역할·RLS·GRANT, DDL 이력, 함수·트리거 전체 인벤토리는 조회 범위 밖 |

기계 판정은 [schema-db-comparison.json](assets/schema-db-comparison.json)에 있다. 이 결과를 “DB 전체 동등” 또는 “앱 통합 검증 완료”로 요약하지 않는다.

## 재현 방법과 근거

정적 추출은 DB 접속 없이 누적 CREATE/ALTER를 해석한다. 각 SQL 내용이 고정 SHA의 Git 객체와 동일한지 검사하고, 지원하지 않는 문장은 실패 처리한다.

```bash
uv run --no-project --with pglast==8.4 python docs/planning/db-meeting-preparation-20260915/tools/extract_schema.py
python docs/planning/db-meeting-preparation-20260915/tools/compare_catalog.py /private/path/to/db-metadata-rds.json
```

두 번째 명령은 별도로 수집한 catalog JSON을 읽는 비교 도구다. 연결·마이그레이션을 수행하지 않는다. 원격 metadata 원본은 로컬 조사 출력에 보관하며 Git에는 코드 구조·비식별 비교 결과만 관리한다.

- [고정 코드의 canonical SQL](https://github.com/3dt-1st-org/LALA-next/tree/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical)
- [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql)
- [RAG operator-pending SQL](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/operator-pending/064_rag_knowledge_retrieval_metadata.sql)
- [PostgreSQL READ ONLY 설명](https://www.postgresql.org/docs/15/sql-set-transaction.html), [제약 catalog](https://www.postgresql.org/docs/15/catalog-pg-constraint.html). READ ONLY와 조회문 제한을 함께 사용했으며 API 시작·ORM 초기화를 실행하지 않았다.
