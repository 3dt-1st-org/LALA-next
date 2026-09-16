# 첫 배포 DB 범위와 로컬 시험 데이터

상태: **김건동 준비안 작성 완료 / 로컬 DB 적용 검증 대기**

## 회의 근거와 완료 기준

9월 15일 회의에서 김건동은 첫 배포의 최소 기능에 필요한 DB를 먼저 정리하고, 각 개발자가 Docker DB에 적용할 임의 시험 데이터를 제공하기로 했다. 이 문서는 A-01의 완료 조건인 **포함·보류 DB와 seed 적용 범위 구분**을 기록한다.

첫 배포의 핵심 흐름은 `회원가입 → 장소 탐색·상세 → 저장 → 일정 저장·재열기 → 도슨트 → 방문 결과`다. 기존 보류 기능의 코드와 테이블은 삭제하지 않는다.

## DB 범위

| 구분 | 스키마·테이블 | 첫 배포에서 확인할 동작 | 판정 |
|---|---|---|---|
| 계정 기준 | `identity.users` | Logto `(issuer, subject)`와 LALA 데이터 소유자 연결, 계정 격리 | 포함 |
| 장소 | `travel.places` | 탐색·상세·일정·저장의 기준 장소 | 포함 |
| 장소 저장 | `planning.user_saved_places` | 저장·해제 반복, 정보 없는 장소 ID 처리, 계정 격리 | 포함 |
| 기본 취향 | `profile.user_travel_preferences` | `expected_revision` 충돌과 계정별 설정 | 포함 |
| 일정별 설정 | `planning.trip_preference_overrides` | 날짜별 override와 revision 충돌 | 포함 |
| 저장 일정 | `planning.user_plans` | 생성 결과 저장·재열기·목록·삭제 | 포함 |
| 방문 결과 | `planning.slot_visits` | 방문·미방문·사유·추천 반영 동의 | 포함 |
| 도슨트 캐시 | `travel.docent_scripts` | 원고 조회·언어·모드와 캐시 실패 시 대체 경로 | 포함 |
| 도슨트 근거 | `rag.knowledge_chunks` | 근거 검색이 필요한 도슨트 흐름 | 조건부 포함. 로컬 해시 인덱스는 별도 실행 |
| 날씨 | `travel.weather_observations` | 일정 표시용 고정 관측값과 외부 API 없는 화면 검사 | 보조 fixture만 포함. 날씨 재계획은 보류 |
| 행사 | `culture.events`, `travel.place_events` | 일정 카드의 행사 자료 | 보조 fixture. 핵심 완료 조건 아님 |
| Local Signals·리뷰·커뮤니티·채팅 | `community.*` | 기존 기능·테스트·복구 근거 보존 | 첫 배포 진입점 보류. 구조·코드 삭제 안 함 |
| 비용·배치·운영 | `economy.*`, `ops.*`, `analytics.*` | 데이터 파이프라인·운영 조사 | 서비스 핵심 흐름에서 제외. 담당 개발 시 선택 적용 |

## seed 파일과 적용 범위

| 파일 | 제공하는 시험 상태 | 첫 배포 기본 적용 |
|---|---|---|
| `010_seed_local_fixture_travel.sql` | 수원 장소 3개 | 적용 |
| `015_seed_local_fixture_account_planning.sql` | 합성 계정 A/B, 저장 장소와 정보 없는 장소 ID, 일정, 기본·일정별 취향, 방문·미방문 결과 | 적용 |
| `020_seed_local_fixture_weather_docent.sql` | 수원 날씨 1건과 한국어 도슨트 원고 1건 | 적용 |
| `025_seed_local_fixture_economy_culture.sql` | 카드 소비·문화 행사 | 필요할 때 선택 검증. 현재 도구는 전체 파일 일괄 적용 |
| `030_seed_local_fixture_worker_ops.sql` | 키워드·커뮤니티·운영 상태 | 필요할 때 선택 검증. 현재 도구는 전체 파일 일괄 적용 |

새 `015` fixture의 발급자는 `https://local-fixture.invalid`다. 실제 Logto 계정이 아니며 로그인할 수 없다. DB repository·격리·재적용 검증에만 사용한다. 앱 로그인부터 확인하는 통합 시험에는 별도의 승인된 개발 계정 A/B가 필요하다.

## 실행과 안전 경계

계획 확인은 DB에 연결하거나 변경하지 않는다.

```bash
uv run python -m apps.api.app.tools.plan_dev_reset --json
```

로컬 Docker DB를 새로 구성할 때만 기존 guarded bootstrap을 사용한다.

```bash
LALA_POSTGRES_PASSWORD='<local-only password>' \
  scripts/unix/bootstrap_local_mvp_db.sh \
  --start-compose \
  --apply-canonical \
  --apply-dev-reset
```

- `DB_DSN` host가 `localhost`, `127.0.0.1`, `::1`이 아니면 dev seed 적용을 거부한다.
- 공유·스테이징·운영 DB에는 `sql/dev_reset`을 적용하지 않는다.
- seed는 고정 시각과 합성 식별자를 사용하며 실제 사용자·취향·위치·자격증명을 포함하지 않는다.
- 현재 적용 도구는 파일 선택 기능이 없으므로 첫 배포 기본 3개만 적용하려면 후속 구현에서 profile 선택을 추가하거나, 전체 로컬 fixture를 허용할지 팀이 정한다.

## 검증 상태와 다음 완료 조건

| 확인 | 결과 |
|---|---|
| dev reset 계획 로드·시크릿 검사 | 완료 |
| 새 account/planning fixture SQL 적용 | 최소 동등 스키마의 일회용 PostgreSQL 16에서 완료 |
| fixture 재실행 가능성 | 두 번 적용 후 행 수 `2·2·1·1·1·2` 유지 확인 |
| 첫 배포 핵심·보조·보류 범위 | 구분 완료 |
| 전체 canonical 18개 + 전체 seed 적용 | 로컬 이미지의 플랫폼 불일치로 미검증 |
| 두 계정 격리·저장·일정·revision API 통합 | 미검증 |
| 승인된 Logto 개발 계정으로 앱 통합 | 계정·개발 API 인계 대기 |

A-01은 문서와 fixture 준비까지 완료했다. 실제 적용과 API 통합은 공용 개발 환경·PostgreSQL 기준 버전·개발 계정이 정해진 뒤 실행한다.
