# 백엔드 API 운영 준비도 점검 및 승인 후 수정 결과

- 기준일: 2026-09-15, 코드: `765570a21ff5ab5207c627d3659e8051be6dbd98`.
- 범위: FastAPI HTTP 작업 55개, WebSocket 경로 1개, 연결된 인증·DB·외부 서비스·실행 설정.
- 상태: **사용자 승인 후 주요 결함 수정 및 로컬 검증 완료**. 최초 진단은 아래 1~6절에 보존하고, 수정 결과와 잔여 위험은 7절에 기록했다.
- 수행: 최초 진단은 주 에이전트가 직접 수행했다. 승인 후 GUI에서 추적 가능한 Orca 워커 3개로 작업을 분리했고, 비용 제어 후속 작업은 기존 세션을 재사용했다. 각 작업 완료와 세션 해제를 확인했다. 모델은 사용자 설정 기본값을 사용했으며 특정 저가 모델이나 절감액을 주장하지 않는다.
- 프로젝트 루트 및 상위 경로에 실제 `AGENTS.md`는 없었다. `AGENTS.example.md`는 예제라는 점을 구분하고 현재 사용자 지시를 적용했다.

## 1. 최초 진단 판정

**현재 코드 그대로 일반 사용자를 받는 운영 서비스로 확대하는 것은 권장하지 않는다.** 인증·사용자별 데이터 분리·정식 스키마·일부 충돌 제어는 갖췄지만, 정상 작성 요청의 실패와 재시도 중복 저장이 실제 DB에서 재현된다. 유료 기능의 비용 제한, 탈퇴 상태 반영, WebSocket 실행 의존성, 장애 시 요청 처리에도 보완이 필요하다.

이는 실제 운영 서버 침해나 비용 피해가 발생했다는 판단은 아니다. 운영 서버·외부 계정·클라우드 DB에는 접근하지 않았다. 저장소의 실행 경로와 격리한 로컬 환경에 대한 판단이며, 배포된 프록시 규칙·DB 파라미터가 일부 위험을 완화할 가능성은 별도로 남아 있다.

### 우선 처리할 항목

| ID | 우선순위 | 문제 | 근거 수준 |
|---|---|---|---|
| F01 | P1 | 게시글·채팅 작성 실패, 댓글은 저장 후 500으로 재시도 중복 | 실제 DB 재현 |
| F02 | P1 | 고정 의존성 설치 환경에 WebSocket 서버 구현이 없음 | 설치 환경 및 실제 HTTP Upgrade 재현 |
| F03 | P1 | 유료 기능 제한 누락, IP 헤더 변경으로 요청 제한 우회 | 로컬 API 재현, 외부 호출 없음 |
| F04 | P1 | 음성 입력·일정 저장 본문의 크기 제한 부족 | 1 MiB 입력 검증 및 DB 저장 재현 |
| F05 | P1 | 탈퇴 진행 중 개인 일정·로컬 제보 쓰기 허용 | 실제 DB 재현 |
| F06 | P2 | 첫 인증 이후 `/me` 호출 순서에 의존하는 쓰기 API | 실제 DB 재현 |
| F07 | P1 | 로컬 제보 중복 방지가 프로세스 메모리에만 존재 | DB 유지·메모리 초기화 재현 |
| F08 | P1 | 채팅 async 경로의 동기 DB 호출과 느린 수신자 대기 | 구조 확인 |
| F09 | P1 | 연결 풀·실행 시간 제한 없이 DB 연결/쿼리 수행 | 구조 확인 및 DB 기본값 확인 |
| F10 | P2 | DB 장애에도 readiness HTTP 200, 예외 500의 지표 누락 | 실제 API 재현 |
| F11 | P1 | CORS가 실제 PUT·PATCH·중복 방지 헤더를 차단 | preflight 3종 재현 |
| F12 | P2 | 정상 도슨트 생성 경로의 캐시 재사용·중복 생성 방지 부재 | 구조 확인 |
| F13 | P2 | 외부 계정 삭제와 로컬 정리 사이 실패 복구 작업 부재 | 구조 확인, 외부 삭제 미실행 |
| F14 | P2 | 목록 조회량·깊은 페이지·동시 일정 저장 제어 부족 | 구조 확인 |
| F15 | P2 | DB 통합 검증·실행 환경 재현성의 공백 | CI·Dockerfile·로컬 테스트 확인 |

P1은 해당 기능을 일반 운영에 노출하기 전에 해결할 항목이다. P2는 출시 범위·트래픽·클라이언트 계약을 정하고 보완할 항목이다. 개인정보의 무인증 대량 유출이나 임의 SQL 실행은 이번 점검에서 재현하지 않았다.

## 2. 상세 발견 사항

### F01. 실제 SQL 결과 키 불일치로 정상 쓰기 실패 [P1]

- 위치: `apps/api/app/services/community_service.py:520`, `community_service.py:320`, `apps/api/app/services/community_chat_service.py:609`.
- 세 곳 모두 `SELECT id AS author_user_id`로 조회한 `RealDictCursor` 결과에서 `identity_row["id"]`를 읽는다. 실제 결과 키는 `author_user_id`이며 `KeyError('id')`가 발생한다.
- 게시글 작성은 트랜잭션 내부에서 실패하여 롤백되고 `503 COMMUNITY_DB_UNAVAILABLE`을 반환한다. `Idempotency-Key`가 있는 경로도 같은 작성자 조회를 사용한다. 동일 키 4개 동시 요청도 모두 503이었다.
- 채팅 메시지 작성도 같은 문제가 있어 정상 소유자의 REST 전송이 503이었다. WebSocket 메시지 저장 역시 같은 서비스에 도달한다.
- **댓글은 더 위험하다.** INSERT 트랜잭션을 먼저 끝내고 별도 조회 후 응답 구성에서 실패한다. 동일 댓글을 두 번 요청했을 때 두 요청 모두 500이었지만 실제 댓글 행은 두 개 생겼다.
- 수정: 열 이름을 일치시키고 작성·작성자 조회·응답 데이터 확보를 하나의 트랜잭션으로 정리한다. 댓글 재시도 계약도 명확히 한다.
- 완료 기준: 실제 PostgreSQL에서 게시글·댓글·채팅 작성 성공, 실패 시 롤백, 같은 중복 방지 키의 병렬 재시도 결과가 한 행·동일 응답, 다른 본문은 409.

### F02. WebSocket 서버 의존성 누락 [P1]

- 위치: `pyproject.toml:22`, `Dockerfile:22`, `infra/azure/api.Dockerfile:16`.
- 의존성은 `uvicorn` 기본 패키지이며 `uv.lock`에는 `websockets`나 `wsproto`가 없다.
- `uv sync --extra dev --frozen`으로 만든 새 환경에서 `uvicorn.protocols.websockets.auto.AutoWebSocketsProtocol`은 `None`이었다.
- 실제 로컬 Uvicorn에 WebSocket Upgrade 요청을 보냈을 때 404를 반환했다. 이 환경에서는 WebSocket 핸들러의 인증 절차에 도달하지 못한다.
- `TestClient`의 WebSocket 테스트가 통과하는 것만으로 실제 서버의 전송 계층 의존성을 검증할 수 없다.
- 수정: WebSocket 구현을 명시적 런타임 의존성으로 추가하고 잠금 파일을 갱신한다. 배포와 같은 Uvicorn 실행으로 로컬 WS smoke test를 추가한다.
- 완료 기준: 유효한 로컬 발급 ticket으로 실제 101 Upgrade 및 메시지 교환, ticket 재사용·타인 room ticket 거부.

### F03. 요청 제한이 비용·남용 방어 경계를 충족하지 못함 [P1]

- 위치: `apps/api/app/core/rate_limit.py:24`, `:50`, `:150`; `apps/api/app/routers/v1.py:222`.
- 도슨트 제한은 `guest_access_enabled`가 false면 바로 반환한다. 일반 OAuth 운영 모드에서는 설정한 분당 제한을 적용하지 않는다.
- 로컬에서 음성 제한을 분당 1로 설정했다. 게스트 모드가 꺼진 상태의 3회 요청은 모두 음성 비활성화 응답 503까지 도달했다. 게스트 모드를 켜면 두 번째 요청이 429였다. 실제 음성 서비스는 호출하지 않았다.
- `CF-Connecting-IP`, `X-Forwarded-For`를 요청 송신자가 신뢰된 프록시인지 확인하지 않고 사용한다. 사용자 키도 `actor + IP`의 조합이므로 같은 계정이 IP를 바꾸면 새 제한 창을 얻는다.
- 동일 계정의 제보 생성 10회 뒤 429를 확인하고, `CF-Connecting-IP`만 변경한 12회 추가 생성은 모두 200이었다.
- `_windows`는 프로세스별 전역 dict이며 사용하지 않는 키를 삭제하지 않는다. 워커 수 증가·재시작으로 제한이 분산/초기화되고, 서로 다른 헤더 값은 메모리도 늘린다.
- `scripts/unix/apply_cloudflare_edge_controls.sh:96`에는 도슨트용 edge 제한 생성 코드가 있다. **실제 적용 여부와 origin 우회 차단은 확인하지 않았다.** 적용됐더라도 계정별 누적 비용 상한을 대신하지는 않는다.
- 수정: 인증 모드와 무관한 계정별 제한, 별도의 신뢰 가능한 IP 제한, 전체 동시 실행 및 일별 비용 예산, TTL 정리, 여러 프로세스가 공유하는 원자적 저장소를 둔다. 초기 규모에서는 기존 PostgreSQL을 활용하는 방안부터 비교하고 Redis 도입을 전제하지 않는다.
- 완료 기준: 헤더 변경·워커 변경·재시작으로 사용자 한도가 초기화되지 않으며, 예산 초과 시 외부 호출 진입 전에 거부한다.

### F04. 요청 본문·유료 처리 입력의 크기 제한 부족 [P1]

- 위치: `apps/api/app/schemas/docent.py:11`, `:97`; `apps/api/app/schemas/planning.py:9`, `:16`; `apps/api/app/main.py:29`.
- `DocentAudioRequest.script`에 최대 길이가 없다. 도슨트 이름·주소 등 여러 문자열도 길이 상한이 없다.
- `SavePlanRequest.plan`은 내부 형식·크기 제한이 없는 `dict[str, Any]`이고 API는 이를 그대로 DB에 저장한다. 1 MiB 임의 문자열을 담은 일정 저장이 200이었다. 같은 크기의 음성 문자열도 모델 검증을 통과했다.
- 앱 차원의 HTTP body byte limit이 없다. 개별 필드 검증만 추가해도 JSON 파싱 전 메모리 사용과 큰 미지정 필드까지 통제할 수 있는 것은 아니다.
- 수정: 프록시 및 ASGI 수신 단계의 전체 바이트 제한, 실제 사용량에 맞는 텍스트 길이·배열 길이·일정 스키마·계정별 저장량 한도를 추가한다. 음성 입력은 서버가 발급한 script 식별자로 참조하는 방식도 비교한다.
- 완료 기준: 과대/깊은/잘못된 본문이 DB 저장이나 유료 서비스 진입 전에 413/422로 거부된다.

### F05. 탈퇴 상태 적용 범위가 일관되지 않음 [P1]

- 위치: `apps/api/app/core/auth.py:124`, `apps/api/app/routers/v1.py:296`, `apps/api/app/routers/local_signals.py:202`, `apps/api/app/services/identity_repository.py:96`.
- `require_logto_identity`는 발급자·JWT identity를 확인하지만 로컬 사용자의 `active/deleting` 상태를 검사하지 않는다.
- `/me` 및 계정 선호도 경로는 provisioning을 거쳐 deleting을 거부한다. 개인 일정과 로컬 제보 경로는 이 검사를 거치지 않는다. FK는 identity 행의 존재만 확인한다.
- 로컬 계정을 deleting으로 바꾼 뒤 `/me`는 409였지만 저장 장소 PUT 및 제보 POST는 200이었다.
- 채팅 메시지의 `_ACTIVE_ACTOR_SQL`과 전달 시 권한 재확인은 좋은 선례다. 이 보호가 다른 사용자 쓰기 전체에 적용돼 있지는 않다.
- 수정: 공통 active-account 권한 경계를 정의하고, 동시 탈퇴와 쓰기의 경쟁까지 막도록 상태 확인과 쓰기를 같은 트랜잭션/잠금 정책으로 묶는다. 조회 허용 범위도 명시한다.
- 완료 기준: deleting/deleted 계정의 모든 보호된 쓰기 거부, 탈퇴와 병렬 쓰기 후 잔존 데이터·계정 재생성 없음.

### F06. 사용자 쓰기가 `/me` 선행 호출에 의존 [P2]

- 위치: `apps/api/app/routers/v1.py:309`, `apps/api/app/routers/community.py:84`, `sql/canonical/064_planning_action_tables.sql:23`.
- 유효한 JWT로 처음 저장 API를 호출해도 로컬 identity 행을 만들지 않는다. FK 위반이 개인 저장에서는 처리되지 않은 500, 커뮤니티에서는 503으로 보인다.
- 새 로컬 JWT의 저장 장소 PUT은 500이었다. 같은 사용자가 `/me`를 호출한 뒤에는 정상 저장된다.
- 클라이언트 시작 순서, 재로그인, 직접 API 사용에 따라 정상 사용자가 실패한다. 운영 DB 장애로 분류하는 것도 부정확하다.
- 수정: F05의 공통 계정 확인 단계에 원자적 최초 provisioning을 포함하거나, 미등록 계정에 대한 명시적 응답과 클라이언트 초기화 계약을 둔다.
- 완료 기준: 첫 사용자 요청 순서에 의존하는 500/503이 사라지고 동시 최초 요청에서도 identity가 한 개만 생긴다.

### F07. 로컬 제보 중복 방지가 재시작·수평 확장에 취약 [P1]

- 위치: `apps/api/app/services/local_signals_service.py:756`, `:1008`, `:1064`; `apps/api/app/routers/local_signals.py:67`.
- 중복 방지 결과를 `_IDEMPOTENCY_STORE` 메모리에 저장한다. DB 트랜잭션과 원자적으로 묶이지 않고 TTL·용량 제한도 없다.
- 같은 계정·키·본문으로 제보를 만든 뒤 이 메모리만 비우고 재전송하면 서로 다른 두 제보가 생성됐다. 서버 재시작이나 별도 워커 처리에서 생기는 문제를 모사한 것이다.
- 제출은 기존 상태가 draft인지 먼저 확인하고 replay를 조회한다. 첫 제출 200 이후 같은 제출 재시도는 409였다.
- 헤더가 없을 때는 본문 해시를 키로 사용하므로 같은 내용의 별도 생성과 재시도의 의도도 구분하기 어렵다.
- 수정: 기존 `community.idempotency_keys` 패턴을 검토해 제보·댓글 작성과 결과 저장을 하나의 DB 트랜잭션으로 처리한다. TTL, key 길이, replay 시 현재 권한, 제출 상태 전이를 함께 정의한다.
- 완료 기준: 재시작·서로 다른 프로세스·동시 요청에서 한 번만 변경되고, 제출 재시도는 원 응답을 반환하며, 만료 키가 정리된다. 기능 플래그가 꺼진 배포에서는 활성화 전 해결한다.

### F08. 채팅이 이벤트 루프와 수신자 속도에 직접 종속 [P1]

- 위치: `apps/api/app/routers/community_chat.py:510`, `:579`, `:680`, `:169`, `:289`.
- async REST handler와 WS handler가 동기 psycopg2 서비스의 `create_message`, `claim_ws_ticket`을 직접 호출한다. DB 연결·잠금 대기 동안 같은 프로세스의 이벤트 루프가 멈출 수 있다.
- broadcast는 연결들을 순회하며 `send_json`을 순차 await하고 개별 전송 deadline이 없다. 느린 수신자가 뒤쪽 수신자와 REST 응답을 지연시킬 수 있다.
- 전달 권한 재검증은 `asyncio.to_thread`를 사용하지만 actor마다 별도 DB 연결을 생성한다. 200명 room의 한 메시지가 최대 200개의 권한 조회를 유발한다.
- 수정: 동기 DB 호출을 제한된 실행 풀로 이동하거나 비동기 DB 계층으로 통일한다. 권한 확인은 batch query로 묶고 outbound queue 크기·send deadline·느린 연결 종료를 둔다.
- 완료 기준: DB 지연·느린 수신자 조건에서도 다른 room 및 health 요청의 지연이 정한 목표 이내다. F02 해결 후 실제 Uvicorn/WS 부하 검증이 필요하다.

### F09. DB 연결 수·쿼리 대기시간이 앱에서 제한되지 않음 [P1]

- 위치: `apps/api/app/services/db_repository.py:37`, `:352`; `planning_repository.py:58`; `identity_repository.py:138`; 각 커뮤니티 repository `_cursor`.
- 대부분의 연산마다 새 psycopg2 연결을 만든다. 연결 풀의 크기·획득 timeout·동시 요청 상한이 공통 계층으로 관리되지 않는다.
- `connect_timeout=3`은 연결 수립 제한이다. 실행 중인 쿼리나 잠금 대기 제한이 아니다. 임시 DB에서 `SHOW statement_timeout`, `SHOW lock_timeout` 모두 `0`이었다.
- canonical SQL 실행 도구의 `SET LOCAL` timeout은 해당 마이그레이션 트랜잭션에만 적용된다. 서비스 요청의 보호로 해석하면 안 된다.
- readiness/metrics도 여러 DB 연결을 매번 열고, 채팅의 fanout 조회가 추가로 연결 수를 늘린다.
- 수정: 공통 DB 연결 소유권·트랜잭션·bounded pool을 마련하고 query/lock/pool-wait timeout을 명시한다. 프로세스 수 × pool 크기 + 배치 + 모니터링 연결이 DB 예산을 넘지 않게 한다.
- 완료 기준: 지연·잠금·연결 고갈에 대해 유한 시간 내 503/적절한 오류, pool 반환·rollback 확인. 실제 운영 DB의 기존 역할별 timeout/PgBouncer 유무는 별도 확인 대상이다.

### F10. readiness HTTP 상태와 오류 관측이 불완전 [P2]

- 위치: `apps/api/app/routers/health.py:27`, `:33`; `apps/api/app/main.py:55`; `apps/api/app/services/planning_repository.py:50`.
- `/readyz`는 degraded여도 항상 success envelope와 HTTP 200을 반환한다. 연결이 거부되는 로컬 DB 주소로 바꿔 `200 + data.status=degraded`를 재현했다. HTTP 코드만 보는 health checker는 장애를 놓친다.
- `/metrics`는 인증 없이 readiness 전체 검사를 실행한다. 공개 호출량이 DB 조회로 전환되며 runtime 구성 정보도 노출한다. 비밀 값 유출은 관찰하지 않았다.
- 개인 계획 repository의 예외는 API 오류로 매핑되지 않는다. DB 장애 시 500에 `X-Request-ID`가 없었고 해당 500은 앱의 route metrics에도 없었다. middleware가 `call_next` 이후에만 지표를 기록하기 때문이다.
- 수정: liveness와 readiness를 분리하고 필수 의존성 장애에 503을 반환한다. readiness 결과를 짧게 캐싱하고 metrics 접근을 운영 네트워크로 제한한다. 일반 오류의 안전한 응답·서버 로그·지표를 모든 종료 경로에 보장한다.
- 완료 기준: 장애 주입 시 health checker가 실패를 감지하며 5xx 수, correlation ID, 원인 로그가 일치한다.

### F11. CORS 계약이 실제 API와 불일치 [P1]

- 위치: `apps/api/app/main.py:49`.
- 허용 method에 PUT/PATCH가 없고 header에 `Idempotency-Key`가 없다. 허용 origin의 브라우저에서도 정상 계약을 이용할 수 없다.
- PUT, PATCH, POST + `Idempotency-Key`의 preflight가 각각 400이었다.
- 영향: 계정 선호도·저장 장소·일정·방문·제보 수정/반응/저장, 중복 방지 헤더를 사용하는 게시글·제보·채팅 작성.
- 수정: 실제 사용하는 method/header 및 브라우저가 읽어야 하는 응답 header를 명시적으로 허용한다. 무조건 wildcard로 확대하지 않는다.
- 완료 기준: 허용 origin의 실제 계약 preflight 성공, 비허용 origin 거부. 같은 origin 또는 native-only 구성에서는 영향이 다르다.

### F12. 도슨트의 정상 생성 경로에서 캐시가 비용을 줄이지 못함 [P2]

- 위치: `apps/api/app/services/docent_service.py:75`, `:123`, `:144`, `:1052`; `db_repository.py:1098`.
- script 캐시 조회는 score/grounding/request context가 모두 없을 때만 실행된다. 일반적인 유효 context 요청은 매번 생성 경로로 진행한다.
- `generate_script`에서 `save_docent_script_cache`를 호출하지 않는다. response의 hash/TTL만으로 서버 캐시가 구현된 것은 아니다. hybrid에서는 캐시 판단 전에 embedding/rerank 경로도 진행한다.
- 음성은 `synthesize_docent_audio`를 바로 호출하며 서버 측 동일 요청 합치기·음성 캐시가 없다.
- 수정: 검증된 context·모델·voice·버전을 포함한 키로 결과 캐시, 동시에 같은 요청이 오면 한 번만 생성하는 제어를 둔다. 사용자별 context를 잘못 공유하지 않도록 한다.
- 완료 기준: 외부 client 대역을 사용해 동일 입력 반복·동시 요청의 호출 수가 1임을 검증하고, 모델/근거 변경 시 캐시가 무효화된다. 실제 유료 호출은 승인 전 계속 금지한다.

### F13. 계정 삭제 중간 실패에 대한 서버 복구 작업 부재 [P2]

- 위치: `apps/api/app/routers/v1.py:161`, `apps/api/app/services/logto_management.py:54`, `identity_repository.py:109`.
- 순서는 로컬 deleting 표시 → 외부 Logto 삭제 → 로컬 삭제/tombstone이다. 여러 외부 요청 사이 또는 마지막 DB 단계에서 실패할 수 있다.
- 외부 사용자가 이미 삭제된 후 로컬 정리에 실패하면 클라이언트가 새 인증을 얻어 재시도하기 어려울 수 있다. 저장소에서 pending deletion을 다시 처리하는 durable job/재조정 루프를 찾지 못했다.
- 수정: 삭제 요청과 단계별 진행 상태를 DB에 기록하고, 재시도 가능한 복구 작업과 운영자 재처리 경로를 마련한다. F05의 권한 차단은 삭제 시작 시점부터 적용한다.
- 완료 기준: 외부 429/timeout, 외부 삭제 성공 후 DB 장애, 프로세스 종료를 대역으로 주입하여 최종 정리까지 수렴한다. **실제 Logto 삭제는 실행하지 않았다.**

### F14. 데이터 증가·동시 사용자 편집에 대한 제한 부족 [P2]

- 위치: `apps/api/app/services/planning_repository.py:70`, `:128`, `:199`; `community_service.py:88`; `community_chat_service.py:84`; `db_repository.py:214`.
- 저장 장소 목록은 LIMIT 없이 전체를 읽고, 저장량 상한도 없다. 일정 목록은 요약을 만들기 위해 원본 JSON envelope를 읽는다. F04와 결합하면 작은 목록 요청도 커진다.
- 커뮤니티·채팅 목록은 전체 COUNT + 제한 없는 OFFSET이다. 응답 개수 제한이 DB 작업량까지 제한하지는 않는다.
- viewport 기능이 켜지면 places는 반경 대신 사각형을 사용하며 면적 상한은 없다. 전 세계 bounds도 값 범위상 가능하다. 결과 100개 제한 전에 후보·점수·정렬 비용이 발생할 수 있다.
- 날짜별 일정 저장은 revision 없는 last-write-wins이다. 계정/여행 선호도의 충돌 보호와 달리 다른 기기의 오래된 일정 저장이 최신 편집을 덮어쓸 수 있다.
- 수정: 계정별 quota, cursor pagination, 필요한 필드만 조회, viewport 면적 제한, 실제 데이터 규모의 EXPLAIN 분석을 적용한다. 일정 충돌 정책을 클라이언트와 함께 정한다.
- 완료 기준: 예상 데이터 크기에서 쿼리 계획·p95 목표 검증, 오래된 일정 수정 충돌을 명시적으로 처리한다. 현재 성능 장애가 이미 발생한다는 주장은 아니다.

### F15. 통합 테스트·배포 재현성의 공백 [P2]

- 위치: `.github/workflows/ci.yml:23`, `apps/api/tests/test_planning_endpoints.py:18`, `Dockerfile:2`, `:16`, `infra/azure/api.Dockerfile:16`.
- 기존 테스트는 DB 대역 중심이며 CI에 실제 PostgreSQL 서비스가 없다. F01의 잘못된 dict 키를 단위 테스트가 놓쳤다.
- 루트 Docker는 Python 3.11, CI/Azure Docker는 3.13이다. 두 Dockerfile의 설치는 frozen lock 동기화가 아니며 dependency lower-bound를 다시 해석한다. 이번 검증은 Python 3.13.12 + frozen lock 기준이다.
- 로컬 전체 테스트 실패 32개는 `core.autocrlf=true`로 셸 스크립트가 CRLF checkout된 문제였다. `git ls-files --eol`은 index LF / worktree CRLF를 보여준다. **커밋에 CRLF가 들어 있다는 판단이나 CI가 동일하게 실패한다는 판단은 하지 않는다.**
- 수정: 실제 DB 통합 테스트와 Uvicorn transport test를 CI에 추가하고, 실행 Python/lock 사용을 통일한다. 셸 파일의 LF 정책은 `.gitattributes` 등 저장소 단위로 고정하는 방안을 검토한다.
- 완료 기준: 깨끗한 설치에서 실제 스키마 적용·핵심 쓰기·재시도·권한·WS 검증이 실행된다. 32개 환경 실패의 재검증도 별도로 완료한다.

## 3. API별 점검표

경로의 공통 prefix는 `/api/v1`이다. C는 `require_client_auth`, O는 OAuth identity, L은 현재 Logto issuer identity를 뜻한다. C는 설정에 따라 guest/static/OAuth를 허용하며 L/O만으로 로컬 active 상태를 보장하지 않는다. 모든 DB 경로에는 공통으로 F09/F10을 고려해야 한다. 각 행의 ID는 추가로 해당 API에 직접 연결된 문제다.

`DB 확인`은 로컬 실제 DB에 대한 해당 동작 또는 오류 경로를 실행했다는 뜻이다. `구조만`은 해당 외부 동작을 실행하지 않았다는 뜻이다. 200 확인을 모든 권한·모든 입력 검증 완료로 해석하면 안 된다.

### 운영·계정·추천·일정: 25개

| Method | 경로 | 인증 | 로컬 결과 / 직접 관련 위험 |
|---|---|---|---|
| GET | `/healthz` | 없음 | 실제 HTTP 200. liveness 용도 |
| GET | `/readyz` | 없음 | DB 정상/장애 실행, 장애에도 200. F10 |
| GET | `/metrics` | 없음 | 200. 외부 공개 시 조회 남용 및 상세 구성 노출. F10 |
| GET | `/me` | L | 최초 생성 200, deleting 409, deleted 410 확인 |
| DELETE | `/me` | L | 외부 삭제 구조만. 로컬 cascade/tombstone 별도 확인. F05/F13 |
| GET | `/me/preferences` | L | DB 확인, 반환 데이터 사용자 기준 필터 |
| PUT | `/me/preferences` | L | 200, stale revision 409 확인. F11 |
| GET | `/places` | C | 실제 HTTP + DB 확인, 좌표/반경/limit 상한 존재. F14 |
| GET | `/weather` | C | 외부 key 없는 로컬 경로 200. 외부 경로는 구조만. F03/F09 및 4절 |
| POST | `/docents/script` | C | rule-based 경로 200. 유료 경로는 구조만. F03/F04/F12 |
| POST | `/docents/audio` | C | disabled 503 및 제한 조건 재현, 실제 합성 없음. F03/F04/F12 |
| POST | `/plans/daily` | C | 실제 DB와 키 없는 날씨 경로 200. 날씨 의존 비용/지연은 4절 |
| GET | `/plans/intervention` | C | 실제 DB와 키 없는 날씨 경로 200. F03/F09 |
| GET | `/me/saved-places` | L | 타인 저장 목록 미노출, DB 장애 500. F05/F10/F14 |
| PUT | `/me/saved-places/{place_id}` | L | 최초 사용자 500, provisioning 후 200, deleting도 200. F04/F05/F06/F11 |
| DELETE | `/me/saved-places/{place_id}` | L | DB 확인. F05. DELETE 자체는 현재 CORS 허용 |
| GET | `/me/plans` | L | DB 확인. 원본 envelope 조회·요약. F05/F14 |
| PUT | `/me/plans/{plan_date}` | L | 저장 200, 1 MiB 임의 JSON도 200. F04/F05/F06/F11/F14 |
| GET | `/me/plans/{plan_date}` | L | 타인 일정 null 확인. F05 |
| DELETE | `/me/plans/{plan_date}` | L | DB 확인, 방문·override 삭제와 같은 트랜잭션. F05 |
| GET | `/me/plans/{plan_date}/preferences` | L | DB 확인. F05 |
| PUT | `/me/plans/{plan_date}/preferences` | L | 동일 초기 revision 동시 요청 결과 200/409. F05/F06/F11 |
| DELETE | `/me/plans/{plan_date}/preferences` | L | DB 확인. F05 |
| GET | `/me/plans/{plan_date}/visits` | L | DB 확인, 사용자+날짜 필터. F05 |
| PUT | `/me/plans/{plan_date}/visits/{slot_period}` | L | DB 확인, slot/status vocabulary 검증 존재. F05/F06/F11 |

### 커뮤니티: 9개

| Method | 경로 | 인증 | 로컬 결과 / 직접 관련 위험 |
|---|---|---|---|
| GET | `/community/posts` | C | DB 확인. 전체 COUNT/deep OFFSET. F14 |
| POST | `/community/posts` | O | 일반·중복 방지 작성 모두 503. F01/F03/F06/F11 |
| GET | `/community/posts/{post_id}` | C | DB fixture 게시글 200 |
| GET | `/community/posts/{post_id}/comments` | C | DB 확인. 전체 COUNT/deep OFFSET. F14 |
| POST | `/community/posts/{post_id}/comments` | O | 같은 요청 2번 모두 500, DB 댓글 2행. F01/F03/F06 |
| POST | `/community/posts/{post_id}/like` | O | DB 확인. toggle은 재전송 시 원래 상태로 뒤집힐 수 있어 클라이언트 자동 재시도 주의. F03 |
| GET | `/community/follows` | O | DB 확인, 본인 목록 필터. F14 |
| POST | `/community/follows` | O | DB 확인. like와 같은 toggle 재시도 계약, 동시 insert 충돌 처리 점검 필요. F03 |
| POST | `/community/posts/{post_id}/reports` | O | 타인 글 신고 200, 자기 글 신고 422 확인. bounded reason 및 중복 DB 제약 존재. F03 |

### 채팅: HTTP 6개 + WebSocket 1개

| Method | 경로 | 인증 | 로컬 결과 / 직접 관련 위험 |
|---|---|---|---|
| GET | `/community/chat/rooms` | C | DB 확인, private room 접근 조건 존재. F14 |
| POST | `/community/chat/rooms` | O | private room 생성 200. F03/F06 |
| POST | `/community/chat/rooms/{room_id}/members` | O + owner | 소유자의 멤버 추가 후 해당 사용자 읽기 200. F03 |
| GET | `/community/chat/rooms/{room_id}/messages` | C + room 접근 | private room 타인 404, 허용 멤버 200. F14 |
| POST | `/community/chat/rooms/{room_id}/messages` | O + active/room | 정상 소유자 작성 503. F01/F03/F08/F11 |
| POST | `/community/chat/rooms/{room_id}/ws-ticket` | O + active/room | 타인 404, 소유자 ticket 발급, DB claim 4개 동시 시 1개만 성공. F03 |
| WS | `/community/chat/rooms/{room_id}/ws` | 단회 ticket + origin + room | 실제 Upgrade 404, 서버 WS 모듈 없음. F02/F03/F08. 앱 내부 frame/idle/연결 수 제한은 존재 |

### 로컬 제보: 15개

READ/WRITE 기능 플래그를 로컬 테스트에서만 활성화했다. 공개 fixture는 테스트 DB에서만 published/approved/public으로 전환했다. 운영 moderation은 수행하지 않았다.

| Method | 경로 | 인증 | 로컬 결과 / 직접 관련 위험 |
|---|---|---|---|
| GET | `/community/signals` | C + read flag | DB 확인, cursor와 limit 존재. F03 |
| POST | `/community/signals` | L + write flag | draft 200, 재시작 모사 후 중복, deleting도 200. F03/F05/F06/F07/F11 |
| GET | `/community/signals/aggregates` | C + 별도 flag | aggregate flag off의 unavailable 결과 확인. 활성 aggregate query는 구조/기존 테스트 기준 |
| GET | `/community/signals/{signal_id}` | C + read flag | private draft 404, published fixture 200 |
| PATCH | `/community/signals/{signal_id}` | L + owner | 본인 수정 200, 타인 403. F03/F05/F07/F11 |
| DELETE | `/community/signals/{signal_id}` | L + owner | soft delete DB 확인. F03/F05/F07 |
| GET | `/community/places/{place_id}/signals` | C + read flag | DB 확인, place filter |
| GET | `/community/signals/{signal_id}/comments` | C + read flag | DB 확인, 공개 상태 필터 |
| POST | `/community/signals/{signal_id}/comments` | L + write flag | DB 확인, 제출 상태로 작성. F03/F05/F06/F07/F11 |
| POST | `/community/signals/{signal_id}/submit` | L + owner | 첫 제출 200, 재시도 409. F03/F05/F07/F11 |
| PUT | `/community/signals/{signal_id}/reactions/{reaction_type}` | L + write flag | DB 확인, 명시적 active 동작. F03/F05/F11 |
| DELETE | `/community/signals/{signal_id}/reactions/{reaction_type}` | L + write flag | DB 확인. F03/F05 |
| PUT | `/community/signals/{signal_id}/save` | L + write flag | DB 확인. F03/F05/F11 |
| DELETE | `/community/signals/{signal_id}/save` | L + write flag | DB 확인. F03/F05 |
| POST | `/community/signals/{signal_id}/reports` | L + write flag | bounded reason 신고 200. F03/F05/F07/F11 |

자동 생성된 `/docs`, `/redoc`, `/openapi.json`, `/docs/oauth2-redirect`는 위 55개 업무/운영 operation과 별개다. 스키마 공개 자체를 보안 결함으로 판단하지 않았고 운영 노출 정책은 별도로 선택하면 된다.

## 4. 외부 API 구조 점검

| 외부 연결 | 실제 사용 경로 | 현재 보호 | 보완 사항 |
|---|---|---|---|
| OpenAI 도슨트 | script, hybrid rerank/embedding | 명시적 enable flag, chat timeout 5초, retry 0, 출력 토큰 상한 | F03/F04/F12. 한 요청의 embedding·rerank·generation 전체 비용/시간 예산 필요 |
| Azure Speech | audio | enable flag, 요청 timeout 20초, SSML escape | 입력 길이·음성 캐시·동시 실행/일일 문자 예산. 외부 응답을 메모리에 전부 수신 |
| KMA/AirKorea | weather, daily plan, intervention | 각 요청 timeout 3초/8초, 성공 응답의 프로세스 캐시 20분 | 요청별 thread pool 생성, 캐시 miss 동시 호출 합치기·negative cache·전체 quota 부재. 키만 있으면 live 호출 가능하며 AI flag로 제어되지 않음 |
| Logto JWKS | OAuth 검증 | RS256, issuer/audience/exp/sub 검증, JWKS cache, fetch timeout 5초 | 미확인 kid 요청 급증 시 refresh 제어·전체 인증 요청 제한 검토. 이번에는 로컬 RSA 키만 사용 |
| Logto Management | 계정 삭제 | timeout 5초, ID URL escape, 일부 404를 완료로 취급 | F13. 전체 삭제 workflow deadline 및 durable recovery |
| Naver/공공 데이터 수집 | 수집·배치 서비스 | 별도 명령/guard 및 일부 timeout 존재 | 공개 HTTP router의 직접 사용자 입력 URL fetch로 확인되지는 않음. 배치 대량 실행 비용·재시도·스케줄은 별도 부하 검증 필요 |
| AWS Secrets Manager/Key Vault | 설정 조회 | runtime profile/secret contract 및 cache helper 존재 | 이번 테스트는 ci profile, clean environment. 실제 권한·회전·장애 동작은 검증하지 않음 |

근거: `services/ai_service.py:67`, `:106`, `:188`, `:490`; `services/speech_service.py:94`; `services/weather_service.py:189`, `:209`, `:367`; `core/jwt_auth.py:34`, `:83`; `services/logto_management.py:54`.

날씨 `force`는 현재 provider cache를 단순히 우회하는 구현이 아니므로, `force=true`만으로 캐시를 무력화한다고 판단하지 않았다. `/places`는 live 날씨 호출 대신 DB 날씨 조회를 사용한다. public API와 worker 배치를 혼동하지 않도록 구분했다.

## 5. 검증 결과와 한계

### 수행 환경

- macOS/ARM host, Python 3.13.12, `uv sync --extra dev --frozen`.
- 이미지: 저장소 `infra/local-postgres/Dockerfile`로 만든 `lala-audit-postgres:20260915`. PostgreSQL 16 계열 + PostGIS + pgvector, amd64 에뮬레이션.
- 임시 컨테이너: `lala-audit-db-20260915`, DB: `lala_audit`, host binding: `127.0.0.1:55439`.
- DB data directory는 tmpfs. 기존 컨테이너/볼륨/외부 DB는 사용하지 않았다. internal-only Docker network에서는 Desktop의 port 연결이 거부돼 로컬 bridge 연결을 추가한 후 테스트했다.
- `env -i`로 환경을 정리하고 테스트 전용 값을 주입했다. Python 시작 시 `sitecustomize.py`로 비-loopback DNS/socket 연결을 차단했다. 이 차단은 Python 계층이며 OS 전체 방화벽이라는 뜻은 아니다. libpq는 별도 로컬 DSN으로 고정했다.
- 실제 JWT signature/issuer/audience/expiry 검증을 유지하고 JWKS 키 획득만 로컬 RSA 공개키로 대체했다. 인증 dependency 전체를 우회하지 않았다.
- 외부 AI·Speech·라우팅 flag를 끄고 공공 데이터/클라우드 비밀 값을 주입하지 않았다. 패키지·Docker 이미지 다운로드는 수행했지만 서비스 외부 API 호출은 수행하지 않았다.
- 정리 완료: 테스트 Uvicorn을 정상 종료했고 임시 DB 컨테이너와 전용 Docker network를 삭제했다. tmpfs의 합성 데이터도 폐기됐다. 재현용 이미지·로컬 가상환경·진단 자료는 남겨 두었다.

### 결과

| 검증 | 결과 | 해석 |
|---|---|---|
| 정식 canonical SQL 18개 적용 | 성공 | 빈 로컬 DB에서 최신 스키마 생성 가능 |
| 기존 백엔드 전체 테스트 | 2,596 passed / 32 failed, 43.51초 | 32개는 로컬 CRLF 셸 실행 실패. 제품 코드 수정으로 숨기지 않음 |
| 추가 로컬 DB/구조 진단 | 27 passed, 12.01초 | **결함이 존재함을 assert하는 진단도 포함. 운영 합격 테스트 27개라는 뜻이 아님** |
| 실제 Uvicorn health / places | HTTP 200 / 200, places source=db | TestClient 밖의 HTTP 서버 실행 확인 |
| 실제 Uvicorn WebSocket Upgrade | 404, WS 구현 None | F02 재현 |
| 장소 조회 짧은 burst | 60회, 동시 12, 전부 200 | p50 400.2ms / p95 485.3ms / max 524.6ms |

burst는 테스트 장소 1개와 소수의 합성 계정/커뮤니티 데이터를 가진 에뮬레이션 DB에서 수행했다. 운영 규모의 지연·처리량 수치로 전용할 수 없다. sustained load, 장시간 soak, 실제 데이터 분포, 다중 API 프로세스, DB failover, 실제 cloud network, 모바일 E2E, 실제 외부 provider 응답은 검증하지 않았다. 목표 동시 사용자·RPS·p95·데이터량을 정한 뒤 별도 성능 합격선을 적용해야 한다.

### 정상 확인한 보호

- 서명 없는 익명 요청은 보호 API에서 401.
- 개인 저장 장소·일정에 타 사용자 데이터가 반환되지 않음.
- 선호도의 stale revision 409, 여행 override 최초 동시 쓰기 200/409.
- 다른 사용자의 private chat 접근/ticket 발급 404, 단회 ticket 동시 claim은 한 개만 성공.
- 다른 사용자의 draft 수정 403, 비공개 제보 상세 읽기 404.
- 로컬 계정 최종 삭제 시 saved places cascade 제거, tombstone 이후 `/me` 410.
- 주요 SQL은 bind parameter를 사용한다. 제보 PATCH의 SQL column 구성은 `extra=forbid` schema에서 온 필드 집합이라는 보호가 있어 임의 SQL 주입으로 단정하지 않았다.

### 로컬 재현 자료

통합 보고서는 이 파일 하나다. 진단 코드와 로그는 Git에서 제외된 `artifacts/tmp/backend-api-audit-20260915/`에 보관했다. 이를 정식 회귀 테스트로 그대로 채택하면 안 된다. F01 등의 현재 결함을 관찰하도록 만든 assert는 수정 단계에서 정상 계약 assert로 바꿔야 한다.

- `test_live_db.py`: 27개 진단 및 로컬 JWT/합성 fixture.
- `sitecustomize.py`: Python 비-loopback 연결 차단.
- `lala-audit-unit.log`: 기존 전체 테스트 결과.
- `lala-audit-db.log`: 최종 진단 결과.

기존 진단 코드는 과거 관찰 기록으로만 유지한다. 수정 후 재현은 아래 정식 runner를 사용한다. 컨테이너 이름·사용자·비밀번호·DB 이름은 실행 시 생성하고 포트는 Docker가 배정한다. 설정은 환경변수로 주입하며 출력하거나 저장소에 기록하지 않는다. TCP SQL 성공을 확인한 뒤 migration을 시작하고 종료 시 임시 DB를 제거한다.

```bash
uv run --frozen python -m apps.api.app.tools.test_postgres_regressions
```

사용자가 별도로 생성한 폐기 가능한 로컬 DB는 공통 `TEST_DB_DSN`으로 선택할 수 있다. 파일 주입은 `apps/api/tests/.env.example`를 참고하여 Git에서 제외된 `.env.test.local`에 값을 두고 `TEST_DB_ENV_FILE`로 명시한다. 자동으로 개발용 `.env`나 앱 `DB_DSN`을 읽지 않는다. 테스트는 테이블 정리를 수행하므로 공유·개발 데이터 DB를 지정하면 안 된다.

## 6. 승인 후 리팩토링안

새 서비스나 광범위한 아키텍처 교체부터 시작하지 않는다. 현재 FastAPI/PostgreSQL 구조 안에서 실제 결함을 수정하고, 공통 계층의 변경이 필요한 부분만 공유한다. 계약 변경은 Flutter client 영향도와 함께 검증한다.

| 순서 | 작업 묶음 | 범위 | 완료 증거 |
|---|---|---|---|
| 1 | 실제 쓰기·브라우저·WS 복구 | F01/F02/F11, 실제 DB 회귀 테스트 기반 | 정상 작성/댓글 재시도/실제 WS/CORS 통과 |
| 2 | 계정 상태와 삭제 복구 | F05/F06/F13 | 최초 사용자, 삭제 경쟁, 외부 실패 대역 테스트 |
| 3 | 비용·입력·중복 방지 | F03/F04/F07/F12 | 외부 호출 0회 테스트 환경에서 한도·재시작·동시성 검증 |
| 4 | DB·채팅·관측 안정화 | F08/F09/F10 | DB 잠금/연결 고갈/느린 WS 수신자/오류 지표 검증 |
| 5 | 조회량·배포 검증 마무리 | F14/F15 | 운영 예상 데이터 규모 query plan 및 재현 가능한 CI |

### 워커 운영 방식

- 사용자 확인 후 Orca의 GUI에서 추적 가능한 워커 세션을 사용한다. 생성 전 `orca-cli`와 orchestration 스킬의 실제 지침·지원 모델을 확인한다.
- 우선 독립적인 작업 묶음 1~2개만 실행한다. 단순 SQL 키/CORS/의존성 수정은 비용이 낮은 코딩 워커, 계정 경쟁·공통 DB·중복 방지는 테스트 범위가 좁은 작업으로 나눠 배정한다. 모델 이름과 비용은 실행 시 확인하며 지금 가정하지 않는다.
- 주 에이전트가 작업 분해·실패 재현·diff 검토·DB 통합 검증을 담당한다. 공통 인증/DB 파일을 여러 워커가 동시에 수정하지 않게 순서를 둔다.
- 각 워커에는 관련 F-ID, 파일, 금지된 외부 호출, 통과 기준만 전달한다. 전체 저장소를 반복 분석시키지 않는다. 실패 원인이 복잡할 때만 상위 모델로 확대한다.
- 모든 워커의 완료 상태를 GUI 세션과 결과로 끝까지 확인한다. 수정 결과 검증 후에 다음 묶음으로 이동한다.
- 운영 DB 마이그레이션·배포·실제 유료 API 호출은 이 로컬 리팩토링 범위에 포함하지 않는다.

**승인 요청 범위:** 위 순서에 따라 우선 P1 결함을 수정하고, 그 수정에 필수적인 P2 항목과 실제 DB 회귀 테스트를 함께 추가한다. 새로운 인프라 비용이 필요한 선택이나 클라이언트 계약의 큰 변경은 구체안을 제시한 뒤 결정한다.

## 7. 승인 후 수정 결과

사용자의 “진행해” 승인에 따라 P1과 이에 필요한 P2를 수정했다. 운영 DB 적용, 배포, 커밋·푸시, 외부 유료 API 호출은 하지 않았다. 기본 FastAPI/PostgreSQL 구조를 유지했다.

| 항목 | 수정 내용 | 검증과 제한 |
|---|---|---|
| F01 | 게시글·댓글·채팅 SQL 별칭 수정, 댓글 응답 생성까지 동일 트랜잭션 | 실제 작성 및 응답 생성 실패 시 롤백 |
| F02 | WebSocket 런타임 의존성 잠금, Docker Python 3.13·frozen 설치 | 실제 로컬 Uvicorn Upgrade와 echo; 채팅 계약은 별도 서비스/ASGI 테스트 |
| F03 | 모든 인증 모드 유료 제한, actor 기반 공유 DB window, 일일 요청·단위 예산, 생성 동시성 제한 | 다중 프로세스·재시작·헤더 위조·동시 한도; no-DB 모드는 프로세스별 제한 |
| F04 | 실제 HTTP 본문 256 KiB, 음성 12,000자, 계획 JSON 128 KiB·깊이·노드 수 제한 | chunked 본문 및 스키마 경계 |
| F05/F06 | 인증 시 최초 사용자 생성, 저장소 트랜잭션 내 활성 계정 확인과 삭제 직렬화 | 최초 HTTP 계획 저장, 삭제 중 409·삭제 후 410, 실제 advisory-lock 경쟁 |
| F07 | Local Signals 멱등 응답을 DB와 변경 트랜잭션에 저장 | 동시 재시도·별도 인터프리터 재시작·submit 응답 재사용 |
| F08 | 채팅 DB 작업 스레드 분리·용량 제한, 권한 일괄 조회, 수신자별 송신 제한·fanout pending 상한 | 이벤트 루프 반응성·취소 시 슬롯 보존·느린 수신자 격리 |
| F09 | 주요 API 저장소 공통 bounded pool, 연결 대기·statement·lock timeout, 오류 세션 폐기 | 실제 풀 고갈·연결 재사용·롤백·쿼리 취소 |
| F10 | degraded readyz HTTP 503, 2초 probe cache, 500 안전 응답·상관 ID·지표, 운영 metrics 접근 제한 | 상태·캐시·비신뢰 peer·500 카운터 테스트 |
| F11 | CORS PUT/PATCH 및 Idempotency-Key 허용 | 브라우저 preflight·413 CORS 검증 |
| F12 | script/audio 버전별 DB cache·single-flight, 생성자 session lock·복구 lease | 다중 프로세스 중복 생성 억제·재시작 cache·락 정리 실패 시 물리 연결 폐기 |
| F13 | 탈퇴 durable job, 외부/로컬 단계 기록, 재처리 CLI | 외부 호출은 mock; 외부 실패·단계 기록 실패·최종 삭제 실패 복구 |
| F14 | 보류 | 조회량 quota·깊은 offset·대규모 query plan·계획 충돌 계약은 별도 설계 필요 |
| F15 | canonical 069~071 등록, 로컬 PostgreSQL CI job, Docker frozen lock, shell LF, macOS Bash 빈 배열 수정 | 로컬 테스트 통과; 실제 CI 실행과 배포 이미지 빌드는 미수행 |

### 운영 설정 및 적용 조건

- 정식 SQL 21개 baseline에 `069_identity_deletion_jobs.sql`, `070_community_durability.sql`, `071_api_cost_controls.sql`을 추가했다. 운영은 백업·스테이징 적용·롤백 계획 확인 후 배포해야 한다. 앱보다 먼저 스키마가 필요하다.
- 풀 기본값은 프로세스별 최대 8개, 대기 1초, statement 5초, lock 1초다. `LALA_DB_POOL_SIZE`, `LALA_DB_POOL_WAIT_MS`, `LALA_DB_STATEMENT_TIMEOUT_MS`, `LALA_DB_LOCK_TIMEOUT_MS`로 조절한다. 전체 프로세스 수를 곱해 PostgreSQL 연결 예산을 산정해야 한다.
- 유료 기본값: `LALA_PAID_DAILY_REQUEST_LIMIT=200`, `LALA_PAID_DAILY_UNIT_LIMIT=200000`, `LALA_PAID_GLOBAL_CONCURRENCY=4`, `LALA_PAID_CACHE_TTL_SEC=3600`, `LALA_PAID_MEMORY_MAX_ENTRIES=256`. 단위는 원화/정확한 토큰이 아닌 보수적 입력량 대용치다. 실패한 외부 시도도 예산을 소비한다. cache hit는 HTTP 한도만 소비한다.
- 운영은 DB 설정을 필수로 유지해야 프로세스 간 제한이 공유된다. 공용 guest는 신뢰된 ASGI peer 기준이므로 프록시 전달 설정과 edge 제한이 별도로 필요하다. 일일 예산은 actor별이며 서비스 전체 월 과금 상한을 대신하지 않는다.
- 운영 `/metrics`는 loopback 또는 `LALA_METRICS_TOKEN` Bearer 인증을 요구한다. 모니터링 scraper와 프록시 네트워크 경계를 함께 설정해야 한다.
- 탈퇴 복구 명령은 `python -m apps.api.app.services.identity_service --reconcile-deletions --limit 100`이다. 실제 실행은 외부 계정 삭제를 수행하므로 이번에는 실행하지 않았고 관리 클라이언트를 대역으로 검증했다. 운영 스케줄러 등록·재시도 실패 경보는 배포 담당 작업으로 남긴다.

### 검증 범위와 잔여 위험

- 최종 전체 API suite: **2,685 passed, 21 skipped**. opt-in 로컬 DB 통합 suite: **78 passed**로 DB 관련 skip을 별도 해소했다. 4개 경고는 TestClient/httpx 및 Uvicorn의 legacy WebSocket API 사용에 관한 deprecation이다. 변경 Python의 Ruff 및 `git diff --check`도 통과했다.
- 새 회귀 테스트: `test_identity_lifecycle.py`, `test_community_production_regressions.py`, `test_paid_cost_controls.py`, `test_production_runtime.py`. opt-in DB 변수는 loopback DSN만 허용한다. CI는 동일 이미지로 임시 DB를 생성하고 종료 시 제거한다.
- 테스트는 깨끗한 환경과 `PYTHONPATH=apps/api/tests/network_guard:.`에서 실행했다. Python 비-loopback socket/DNS를 차단했으며, C 확장·별도 실행 파일까지 차단하는 OS 방화벽이라고 주장하지 않는다. DB 목적지는 모두 임시 Docker의 `127.0.0.1:55439`였다.
- OpenAI/Speech/Logto 등 실제 외부 통신·요금·응답 품질·운영 JWKS 장애·실제 제공자 idempotency는 검증하지 않았다. 제공자 성공 후 cache commit 전에 프로세스가 죽으면 재시도 비용이 발생할 수 있다.
- 실제 사용자 규모의 장시간 부하, 대규모 query plan, ingress body-read deadline/slowloris, DB 백업 복구·failover, 운영 스케줄러와 경보는 별도 검증이 필요하다. Docker 요청 동시성 상한은 64이며 비-Docker 실행 경로는 ingress/실행 옵션을 확인해야 한다.
- 결론: 최초에 재현된 주요 P1 결함은 수정했고 로컬 회귀 검증을 추가했다. 다만 **지금 바로 무제한 운영 확대 가능**이라는 판정은 아니다. F14와 위 배포·부하 검증을 거친 제한적 출시가 적절하다.
