# 핵심 데이터 사전

기준 `765570a21ff5ab5207c627d3659e8051be6dbd98`. 핵심 11개 테이블의 업무 의미를 풀고 나머지 테이블은 [전체 참고표](08-full-schema-reference.md)에 수록하였다. **컬럼·DEFAULT·CHECK는 코드 정의**, 실제 DB 대조 범위는 [01 문서](01-baseline-and-db-comparison.md)를 따른다.

키 열의 PK/UNIQUE/FK 표시는 해당 컬럼이 그 제약에 참여한다는 뜻이다. 복합 키의 각 열이 단독으로 유일하다는 뜻이 아니다. 특히 `identity.users`의 UNIQUE는 `(issuer, subject)` 한 쌍이며, 정확한 열 조합은 [전체 제약 목록](08-full-schema-reference.md)에서 확인한다.

## 식별자·시간·완료의 의미

| 항목 | 현재 의미 | 주의할 해석 |
|---|---|---|
| identity.users.id / (issuer, subject) | 내부 UUID PK / 사용자 소유 테이블이 참조하는 복합 UNIQUE | subject 하나만으로 계정을 합치지 않음 |
| travel.places.id / place_id | 내부 UUID / 외부 노출 text 식별자 | 같은 이름의 장소라도 ID를 임의 통합하지 않음 |
| plan_date | 클라이언트가 보내는 여행 날짜 | SQL 주석은 UTC day, tripLibraryDateKey는 기기 달력 날짜: 시간대 규칙 결정 필요 |
| created_at / updated_at | 최초 생성 / 마지막 상태 갱신 | 변경 이력 전체가 아님. now() DEFAULT는 UPDATE 자동 트리거 아님 |
| revision / expected_revision | 낙관적 동시 수정 제어 / 클라이언트가 읽은 버전 | timestamp로 대체하지 않음. 신규 저장 expected_revision=0, 충돌 409 |
| 저장 성공 | 기기 반영·기기 영속화·서버 승인 단계가 있음 | DB 스키마 존재 또는 화면 토글만으로 세 단계 성공을 합치지 않음 |


## identity.users

Logto 식별자와 LALA 서비스 계정 연결. 계정 provision/탈퇴 서비스; GET /me·GET /me/preferences도 provision으로 쓸 수 있음. 기본 취향·저장·일정·방문 소유 FK의 참조점.

[SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `id` | `uuid` | 불가 | `gen_random_uuid()` | PK | LALA 계정 행의 내부 UUID. 소유 테이블의 복합 인증 식별자와 구분 |
| `issuer` | `text` | 불가 | 없음 | UNIQUE | 검증한 인증 발급자. 소유 범위의 절반 |
| `subject` | `text` | 불가 | 없음 | UNIQUE | 발급자 내 사용자 식별자. issuer와 함께 사용 |
| `status` | `text` | 불가 | `'active'` | — | active/deleting: 계정 정상·탈퇴 처리 중 |
| `created_at` | `timestamptz` | 불가 | `now()` | — | 행 최초 생성 시각. upsert 시 보존 |
| `last_seen_at` | `timestamptz` | 불가 | `now()` | — | 계정 provision의 마지막 시각. 매 사용자 행동의 이력 아님 |
| `deletion_requested_at` | `timestamptz` | 허용 | 없음 | — | 탈퇴 처리 시작 시각; 미요청 NULL |

## identity.deleted_users

탈퇴한 식별자의 digest·처리 시각 보관. 탈퇴 오케스트레이션. 다른 사용자 테이블과 FK 없음. 보관 기간·운영 삭제 정책은 팀 확인.

[SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L13) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `identity_digest` | `bytea` | 불가 | 없음 | UNIQUE | 삭제 식별자의 32바이트 digest; 평문 identity 보관 테이블 아님 |
| `deleted_at` | `timestamptz` | 불가 | `now()` | — | 탈퇴 식별자 기록 생성 시각 |

## profile.user_travel_preferences

계정 기본 취향·제약·음성 설정. GET/PUT /api/v1/me/preferences · S-52~55/57. 계정 삭제 시 owner FK CASCADE.

[SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `issuer` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 검증한 인증 발급자. 소유 범위의 절반 |
| `subject` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 발급자 내 사용자 식별자. issuer와 함께 사용 |
| `schema_version` | `integer` | 불가 | `1` | — | 저장 문서 구조 버전. SQL 번호와 별개 |
| `revision` | `bigint` | 불가 | `1` | — | 동시 수정 제어 버전. PUT의 expected_revision과 비교 |
| `payload` | `jsonb` | 불가 | 없음 | — | 검증된 JSON 문서. 아래 내부 항목 참조 |
| `created_at` | `timestamptz` | 불가 | `now()` | — | 행 최초 생성 시각. upsert 시 보존 |
| `updated_at` | `timestamptz` | 불가 | `now()` | — | 마지막 갱신 시각. API/작업 코드가 갱신하며 DEFAULT now()는 자동 갱신 트리거가 아님 |

## travel.places

장소 기본 정보와 공개 place_id. 수집/보강 작업 → GET /api/v1/places · S-04/05/10/11/12/15. UUID id와 공개 place_id는 별개.

[SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `id` | `uuid` | 불가 | `gen_random_uuid()` | PK | 행 내부 UUID. 공개 장소 식별자와 구분 |
| `place_id` | `text` | 불가 | 없음 | UNIQUE | 공개 장소 식별자 text. 실제 FK 여부는 키 열 참조 |
| `name_ko` | `text` | 불가 | 없음 | — | 한국어 장소명 |
| `name_en` | `text` | 허용 | 없음 | — | 영문 장소명; 미제공 가능 |
| `category` | `text` | 불가 | 없음 | — | 장소 분류: attraction/restaurant/event/culture_venue |
| `address_ko` | `text` | 허용 | 없음 | — | 한국어 주소 |
| `address_en` | `text` | 허용 | 없음 | — | 영문 주소 |
| `image_url` | `text` | 허용 | 없음 | — | 이미지 참조 주소 |
| `region_name_ko` | `text` | 허용 | 없음 | — | 한국어 지역명 |
| `region_name_en` | `text` | 허용 | 없음 | — | 영문 지역명 |
| `province_code` | `text` | 허용 | 없음 | — | 상위 행정구역 코드 |
| `city_code` | `text` | 허용 | 없음 | — | 하위 행정구역 코드 |
| `lat` | `double precision` | 불가 | 없음 | — | 장소 위도 |
| `lng` | `double precision` | 불가 | 없음 | — | 장소 경도 |
| `is_indoor` | `boolean` | 허용 | 없음 | — | 실내 여부. NULL은 미확인 |
| `primary_source` | `text` | 불가 | `'canonical'` | — | 기본 데이터 출처 코드 |
| `source_record_id` | `text` | 허용 | 없음 | — | 상위 출처의 레코드 식별자 |
| `updated_at` | `timestamptz` | 불가 | `now()` | — | 마지막 갱신 시각. API/작업 코드가 갱신하며 DEFAULT now()는 자동 갱신 트리거가 아님 |

## travel.place_enrichments

번역·실내 여부 등 장소 보강 이력. 보강 작업 결과. travel.places(place_id) FK; 삭제 기본 NO ACTION. 최신 보강을 어떻게 조회에 반영하는지는 서비스별 계약.

[SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `id` | `uuid` | 불가 | `gen_random_uuid()` | PK | 행 내부 UUID. 공개 장소 식별자와 구분 |
| `place_id` | `text` | 불가 | 없음 | FK → travel.places(place_id) | 공개 장소 식별자 text. 실제 FK 여부는 키 열 참조 |
| `enrichment_type` | `text` | 불가 | 없음 | — | 보강 항목/유형 |
| `name_en` | `text` | 허용 | 없음 | — | 영문 장소명; 미제공 가능 |
| `address_en` | `text` | 허용 | 없음 | — | 영문 주소 |
| `region_name_en` | `text` | 허용 | 없음 | — | 영문 지역명 |
| `is_indoor` | `boolean` | 허용 | 없음 | — | 실내 여부. NULL은 미확인 |
| `attributes` | `jsonb` | 불가 | `CAST('{}' AS jsonb)` | — | 보강 세부 속성. 고정된 전체 JSON 스키마는 SQL에 없음 |
| `confidence` | `numeric(5, 4)` | 허용 | 없음 | — | 보강 신뢰도 numeric(5,4); SQL 범위 CHECK는 없음 |
| `source_method` | `text` | 불가 | 없음 | — | 콘텐츠 생성·수집 방법 |
| `model_name` | `text` | 허용 | 없음 | — | 생성에 사용한 모델명; 없는 경우 NULL |
| `prompt_version` | `text` | 허용 | 없음 | — | 보강 프롬프트 버전 |
| `generated_at` | `timestamptz` | 불가 | `now()` | — | 콘텐츠 생성 또는 보강 시각 |

## planning.user_saved_places

계정별 저장 장소 현재 집합. GET/PUT/DELETE /api/v1/me/saved-places · S-12/23. 소유 계정 삭제 CASCADE; 장소 FK 없음.

[SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `issuer` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 검증한 인증 발급자. 소유 범위의 절반 |
| `subject` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 발급자 내 사용자 식별자. issuer와 함께 사용 |
| `place_id` | `text` | 불가 | 없음 | PK | 공개 장소 식별자 text. 실제 FK 여부는 키 열 참조 |
| `source` | `text` | 불가 | `'public_mvp_snapshot'` | — | 저장 장소 출처 표기. 서버 기본 public_mvp_snapshot, 현재 앱 adapter는 db |
| `saved_at` | `timestamptz` | 불가 | `now()` | — | 현재 저장 행 생성 시각. 반복 PUT은 보존, 해제 후 재저장은 새 시각 |

## planning.user_plans

계정·날짜별 저장 일정. GET 목록·GET/PUT/DELETE 날짜 경로 · S-20/24. 계정 삭제 CASCADE. API의 일정 삭제는 같은 날짜 방문·override를 코드에서 먼저 삭제.

[SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `issuer` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 검증한 인증 발급자. 소유 범위의 절반 |
| `subject` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 발급자 내 사용자 식별자. issuer와 함께 사용 |
| `plan_date` | `date` | 불가 | 없음 | PK | 클라이언트가 지정하는 여행 날짜. 사용자·날짜가 일정 키 |
| `schema_version` | `integer` | 불가 | 없음 | — | 저장 문서 구조 버전. SQL 번호와 별개 |
| `envelope` | `jsonb` | 불가 | 없음 | — | 저장 요청 plan 객체. DB에는 날짜별 현재 사본 한 개; 내부 필드 엄격 검증 없음 |
| `created_at` | `timestamptz` | 불가 | `now()` | — | 행 최초 생성 시각. upsert 시 보존 |
| `updated_at` | `timestamptz` | 불가 | `now()` | — | 마지막 갱신 시각. API/작업 코드가 갱신하며 DEFAULT now()는 자동 갱신 트리거가 아님 |

현재 저장 요청은 `plan: dict[str, Any]`를 받아 객체를 저장한다. 읽기는 schema_version과 객체 여부를 검사하나 slots의 모든 내부 의미를 강제하지 않는다. 일정 1개/날짜 모델, 내부 검증, 덮어쓰기·삭제 규칙은 B08/B11 검토 대상이다.

## planning.trip_preference_overrides

날짜별 여행 설정 덮어쓰기. GET/PUT/DELETE /api/v1/me/plans/{plan_date}/preferences · S-22. 소유 계정 FK만 있고 user_plans 날짜 FK는 없음.

[SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `issuer` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 검증한 인증 발급자. 소유 범위의 절반 |
| `subject` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 발급자 내 사용자 식별자. issuer와 함께 사용 |
| `plan_date` | `date` | 불가 | 없음 | PK | 클라이언트가 지정하는 여행 날짜. 사용자·날짜가 일정 키 |
| `schema_version` | `integer` | 불가 | `1` | — | 저장 문서 구조 버전. SQL 번호와 별개 |
| `revision` | `bigint` | 불가 | `1` | — | 동시 수정 제어 버전. PUT의 expected_revision과 비교 |
| `payload` | `jsonb` | 불가 | 없음 | — | 검증된 JSON 문서. 아래 내부 항목 참조 |
| `created_at` | `timestamptz` | 불가 | `now()` | — | 행 최초 생성 시각. upsert 시 보존 |
| `updated_at` | `timestamptz` | 불가 | `now()` | — | 마지막 갱신 시각. API/작업 코드가 갱신하며 DEFAULT now()는 자동 갱신 트리거가 아님 |

## planning.slot_visits

일정 날짜·슬롯별 방문 결과. GET/PUT /api/v1/me/plans/{plan_date}/visits… · S-25. 사용자 입력 결과이며 GPS 도착 증거가 아님. 계정 FK만 있고 plan/place FK 없음.

[SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `issuer` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 검증한 인증 발급자. 소유 범위의 절반 |
| `subject` | `text` | 불가 | 없음 | FK → identity.users(issuer,subject); PK | 발급자 내 사용자 식별자. issuer와 함께 사용 |
| `plan_date` | `date` | 불가 | 없음 | PK | 클라이언트가 지정하는 여행 날짜. 사용자·날짜가 일정 키 |
| `slot_period` | `text` | 불가 | 없음 | PK | morning/lunch/afternoon/dinner 중 하나 |
| `place_id` | `text` | 허용 | 없음 | — | 공개 장소 식별자 text. 실제 FK 여부는 키 열 참조 |
| `status` | `text` | 불가 | `'planned'` | — | planned/visited/not_visited의 현재 결과 |
| `visited_at` | `timestamptz` | 허용 | 없음 | — | visited 기록 요청 시각. 반복 확인·수정 시 갱신; 실제 도착 시각 자동 측정 아님 |
| `created_at` | `timestamptz` | 불가 | `now()` | — | 행 최초 생성 시각. upsert 시 보존 |
| `updated_at` | `timestamptz` | 불가 | `now()` | — | 마지막 갱신 시각. API/작업 코드가 갱신하며 DEFAULT now()는 자동 갱신 트리거가 아님 |
| `reason_code` | `text` | 허용 | 없음 | — | 미방문 이유: closed/weather/crowded/time/transport/changed_mind/other |
| `use_for_recommendations` | `boolean` | 불가 | `FALSE` | — | 방문 결과를 추천에 활용하도록 선택한 값. planned에서는 false |
| `confirmed_at` | `timestamptz` | 허용 | 없음 | — | visited/not_visited 결과 확인 요청 시각; planned로 되돌리면 NULL |

`reason_code`는 not_visited일 때만 허용한다. planned의 추천 활용 동의는 false다. 반복 visited 요청도 `visited_at`·`confirmed_at`을 갱신하므로 최초 방문 시각·시도 횟수를 복원할 수 없다.

## travel.docent_scripts

장소·언어·모드별 도슨트 원고 캐시. POST /api/v1/docents/script에서 조건부 캐시 조회. generate_script의 정상 생성 반환 경로는 DB 캐시 쓰기를 호출하지 않음. 캐시 행 수를 요청·재생 횟수로 쓰지 않음.

[SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) · DB 공통 컬럼·키 대조

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `id` | `uuid` | 불가 | `gen_random_uuid()` | PK | 행 내부 UUID. 공개 장소 식별자와 구분 |
| `place_id` | `text` | 불가 | 없음 | UNIQUE | 공개 장소 식별자 text. 실제 FK 여부는 키 열 참조 |
| `category` | `text` | 불가 | 없음 | UNIQUE | 장소 분류: attraction/restaurant/event/culture_venue |
| `language` | `text` | 불가 | 없음 | UNIQUE | 도슨트 콘텐츠 언어; API 정규화 ko/en |
| `mode` | `text` | 불가 | 없음 | UNIQUE | 도슨트 모드. 코드의 normalize_docent_mode와 대조 |
| `script` | `text` | 불가 | 없음 | — | 원고 텍스트. 재생 이력 아님 |
| `source_method` | `text` | 불가 | 없음 | — | 콘텐츠 생성·수집 방법 |
| `generated_at` | `timestamptz` | 불가 | `now()` | — | 콘텐츠 생성 또는 보강 시각 |
| `expires_at` | `timestamptz` | 허용 | 없음 | — | 캐시 만료 시각; NULL이면 만료값 없음 |

## rag.knowledge_chunks

장소·문화·집계 근거와 임베딩. RAG 인덱싱 작업 → 도슨트 근거 검색. place_id NULL 허용 FK. 계정별 듣기 기록이 아님. 실제 DB에는 별도 embedding_generation 컬럼이 있음.

[SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) · 공통 컬럼·키 일치 / DB 추가 컬럼 1개

| 컬럼 | DB 타입 | NULL | 기본값 | 키 | 서비스상 의미 |
|---|---|---|---|---|---|
| `id` | `uuid` | 불가 | `gen_random_uuid()` | PK | 행 내부 UUID. 공개 장소 식별자와 구분 |
| `source_type` | `text` | 불가 | 없음 | UNIQUE | place_profile/culture_event/community_post/place_mention/weather_context |
| `source_id` | `text` | 불가 | 없음 | UNIQUE | 출처 안의 식별자; source_type과 UNIQUE |
| `source_table` | `text` | 불가 | 없음 | — | 출처 테이블명 문자열. 이 문자열 자체가 FK는 아님 |
| `place_id` | `text` | 허용 | 없음 | FK → travel.places(place_id) | 공개 장소 식별자 text. 실제 FK 여부는 키 열 참조 |
| `title_ko` | `text` | 허용 | 없음 | — | 근거 제목 |
| `body_ko` | `text` | 불가 | 없음 | — | 한국어 근거 내용 |
| `body_en` | `text` | 허용 | 없음 | — | 영문 근거 내용; 없을 수 있음 |
| `metadata` | `jsonb` | 불가 | `CAST('{}' AS jsonb)` | — | 출처·검색 보조 정보. 생성 코드별 확장 객체 |
| `embedding` | `vector(1536)` | 허용 | 없음 | — | 1536차원 벡터. 미생성 NULL |
| `embedding_model` | `text` | 허용 | 없음 | — | 임베딩 모델명 |
| `embedding_method` | `text` | 불가 | `'local_hash'` | — | 임베딩 방법, 기본 local_hash. 실제 제공자 사용은 실행 설정 별도 |
| `content_sha256` | `text` | 불가 | 없음 | — | 내용 변경 감지 hash |
| `last_embedded_at` | `timestamptz` | 허용 | 없음 | — | 마지막 임베딩 시각 |
| `updated_at` | `timestamptz` | 불가 | `now()` | — | 마지막 갱신 시각. API/작업 코드가 갱신하며 DEFAULT now()는 자동 갱신 트리거가 아님 |

실제 DB 추가 항목: `embedding_generation integer NOT NULL DEFAULT 0`. canonical 기본 구조와 분리해 [차이 D-04](01-baseline-and-db-comparison.md)에 기록하였다.

## JSON: 기본 취향 payload

[preferences.py](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/api/app/schemas/preferences.py)에서 선언한 값이다. `extra=forbid`; 알 수 없는 항목을 조용히 보관하지 않는다. 표의 기본값은 API/Pydantic 기본값이며 DB가 JSON 내부 기본값을 채우는 것은 아니다.

`payload.version = 1`. `soft`, `hard`, `locale` 객체는 생략 시 API 기본 객체가 들어간다.

| JSON 경로 | 타입·허용 값 | API 기본값 | 의미 |
|---|---|---|---|
| soft.pace | string: relaxed, balanced, packed | "balanced" | 하루 일정 밀도 |
| soft.crowd_tolerance | string: quiet, balanced, popular | "balanced" | 혼잡 선호 |
| soft.walking_band | string: short, medium, long | "medium" | 도보 거리 선호 |
| soft.interests | 배열 [string: localFood, cafe, history, arts, nature, walk, night, shopping, market, festival, handsOn, photography] · 최대 5개 | [] | 관심 주제 |
| soft.travel_styles | 배열 [string: famous, hiddenLocal, residentFavorite, newPlaces, revisit, spontaneous] · 최대 3개 | [] | 장소 선택 스타일 |
| soft.indoor_outdoor | string: indoor, balanced, outdoor | "balanced" | 실내/실외 선호 |
| soft.weather_sensitivity | string: low, medium, high | "medium" | 날씨 민감도 |
| soft.food_cuisines | 배열 [string: korean, streetFood, cafeDessert, marketFood, worldCuisine] · 최대 4개 | [] | 음식 종류 선호 |
| soft.food_adventure | string: familiar, balanced, adventurous | "balanced" | 익숙한/새로운 음식 선호 |
| soft.companions | 배열 [string: solo, partner, friends, family, children, senior, pet] | ["solo"] | 동행 유형 |
| soft.transport_modes | 배열 [string: walk, transit, taxi, car, bicycle] | ["transit", "walk"] | 이동 수단 |
| soft.rest_frequency | string: low, balanced, frequent | "balanced" | 휴식 빈도 |
| soft.max_one_way_minutes | integer: 15, 30, 60, 90 | 30 | 선호 편도 이동 상한(분) |
| soft.max_transfers | integer: 0, 1, 2, 3 | 2 | 환승 횟수 상한 |
| soft.budget_band | string: value, balanced, special | "balanced" | 예산대 선호 |
| soft.day_rhythm | string: morning, daytime, night | "daytime" | 활동 시간대 |
| soft.exclude_closing_soon | boolean | true | 마감 임박 제외 선호 |
| soft.docent_depth | string: short, standard, deep | "standard" | 도슨트 해설 깊이 |
| soft.spice_level | string: mild, medium, spicy / null | null | 식당 요청용 맵기. 미선택 null |
| soft.order_requests | 배열 [string: staffRecommendation, smallPortion, quietTable, takeout] · 최대 4개 | [] | 식당 주문/좌석 요청 |
| hard.dietary_modes | 배열 [string: vegetarian, vegan, halal, kosher] · 최대 4개 | [] | 본인이 지정한 식이 조건 |
| hard.allergens | 배열 [string: nuts, shellfish, dairy, eggs, gluten, soy] · 최대 6개 | [] | 본인이 지정한 알레르겐 |
| hard.avoid_ingredients | string · 최대 120자 | "" | 피할 식재료 문자열; trim·최대 120자 |
| hard.avoid_stairs | boolean | false | 계단 회피 |
| hard.wheelchair_access | boolean | false | 휠체어 접근 조건 |
| hard.stroller_access | boolean | false | 유모차 접근 조건 |
| hard.verified_accessibility_only | boolean | false | 확인된 접근성 정보만 사용 선호 |
| hard.max_wait_minutes | integer: 10, 20, 40, 60 | 20 | 대기 시간 상한(분) |
| locale.docent_autoplay | boolean | false | 자동 도슨트 선호 |
| locale.place_name_mode | string: localized, localizedWithKorean, korean | "localizedWithKorean" | 장소 이름 표시 방식 |
| locale.narration_speed | number: 0.8, 1.0, 1.2 | 1.0 | 음성 배속 |
| locale.continue_narration | boolean | true | 해설 이어 듣기 |
| locale.pronunciation_help | boolean | false | 발음 도움 표시 |

목록 중복은 거부한다. 식이·알레르기·접근성 값과 식당 요청용 spice_level/order_requests는 공개 일정 생성의 preference_context로 보내지 않는다. `locale`에는 콘텐츠 언어·국가 필드가 없다. [화면 연결표](04-screen-api-data-mapping.md)의 국가/언어 안건과 연결한다.

## JSON: 여행별 override payload

[planning.py](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/api/app/schemas/planning.py)의 계약. version=1, 아래 항목은 전부 생략/null이면 기본 취향을 따른다. PUT은 `exclude_none=True`로 저장한다.

| 항목 | 타입·허용 값 | 기본값 | 의미 |
|---|---|---|---|
| version | 고정 1 | 1 | 문서 구조 버전 |
| companions | 배열 [string: solo, partner, friends, family, children, senior, pet] / null | null | 동행 유형 |
| pace | string: relaxed, balanced, packed / null | null | 하루 일정 밀도 |
| crowd_tolerance | string: quiet, balanced, popular / null | null | 혼잡 선호 |
| walking_band | string: short, medium, long / null | null | 도보 거리 선호 |
| indoor_outdoor | string: indoor, balanced, outdoor / null | null | 실내/실외 선호 |
| weather_sensitivity | string: low, medium, high / null | null | 날씨 민감도 |
| transport_modes | 배열 [string: walk, transit, taxi, car, bicycle] / null | null | 이동 수단 |
| max_wait_minutes | integer: 10, 20, 40, 60 / null | null | 대기 시간 상한(분) |
| budget_band | string: value, balanced, special / null | null | 예산대 선호 |
| day_rhythm | string: morning, daytime, night / null | null | 활동 시간대 |
| exclude_closing_soon | boolean / null | null | 마감 임박 제외 선호 |

식이·알레르기·계단/휠체어/유모차 조건은 override 필드에 없다. `max_wait_minutes`는 기본 payload의 hard 영역에 있지만 날짜별 override에는 허용되어 있으므로, “hard 객체 전체가 절대로 override되지 않는다”라고 일반화하지 않는다.

## JSON: 저장 일정 envelope

DB `schema_version=1`과 별도로 `envelope`에는 클라이언트가 보낸 plan 객체가 들어간다. 아래는 현재 앱 encoder의 알려진 구조이며, 서버가 이 내부 필드를 모두 필수 검사한다는 뜻이 아니다.

| 경로 | 현재 앱 직렬화 형태 | 의미·검토점 |
|---|---|---|
| language | string | 요청/표시 언어 코드 |
| center.lat / center.lng | number | 일정 중심 좌표. 온보딩의 현 위치 미저장 정책과는 다른 저장 경계 |
| radius_m | integer | 탐색 반경 |
| weather | object | temp/icon/dust/forecast/outdoor_status/source 등 날씨 스냅샷 |
| slots | array<object> | 보통 4개 시간대. 서버 SavePlanRequest가 개수·내부 의미를 강제하지 않음 |
| slots[].period / title | string / string | morning/lunch/afternoon/dinner와 화면 제목 |
| slots[].place | object, 장소 없으면 앱 encoder 생략 | place_id/name/category/lat/lng/address/source 및 선택적인 출처·점수·신선도 |
| slots[].weather_hint / start_time | 선택 string | 날씨 안내·예상 시작 시각 |
| slots[].stay_duration_minutes / travel_time_from_previous_minutes | 선택 integer | 체류·이동 분. 실측 또는 공인 경로 시간이라고 단정하지 않음 |
| slots[].opening_hours_valid / estimated_opening_hours | 선택 boolean/string | 카테고리 기반 추정 운영시간. 실제 영업 확인과 구분 |
| slots[].indoor_outdoor / recommendation_reason | 선택 string | 실내/실외와 추천 설명 |
| slots[].local_franchise_confidence | 선택 number | 미확인 값은 null/생략 |
| slots[].swappable_alternatives | array<place> | 교체 장소 후보 |
| slots[].unavailable_reason | 선택 string | 장소를 배정하지 못한 이유 |
| source / request_hash / cache_key | string | 출처·요청 내용의 결정적 식별자. 사용자·행동 이벤트 ID가 아님 |

API 생성 응답의 `preference_effects`와 flag 조건부 `closure_state`, `closing_soon`, `forecast_window`, `air_quality_bad`, `travel_time_authority_minutes`는 현재 앱 encoder에 없다. 생성 응답 전체가 저장·복원된다고 단정하지 않고 왕복 보존 범위를 검증한다.

근거: [planner_service.py](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/api/app/services/planner_service.py), [앱 plan encoder](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/flutter_app/lib/core/persistence/cross_tab_preferences.dart), [PlanningRepository](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/api/app/services/planning_repository.py).

## 게스트·기기 저장과 계정 저장

| 영역 | 기기 저장 | 계정 연결·현재 동작 |
|---|---|---|
| 온보딩 | lala.onboarding.v1.*: 완료·UI 언어·여행 유형·수동 지역 ID | 국가/새 여행 목적의 서버 저장 계약은 없음. 이 저장소는 현 위치 좌표를 영속화하지 않음 |
| 저장 장소 | lala.v5.savedPlaces / SavedPlaceStore | 계정 연결 때 remoteSaved와 localSaved의 합집합. 해제 실패 후 재연결 검증 필요 |
| 일정 | lala.crosstab.v1.*의 plan envelope | 현재 일정 저장 + 날짜별 과거 일정 API. 원격 성공과 기기 저장 성공을 구분 |
| 취향 | lala.travel_preferences.v1 + updated_at 키 | revision 기반 계정 동기화. 로컬 timestamp는 원격 revision 대체가 아님 |
| 여행 설정·방문 | lala.trip_library.v1 | 날짜별 override와 방문 피드백. 방문 place_id는 세션 메모리만 보유하여 재시작 재전송 시 null 가능 |
| 위치 추천 설정 | privacy settings의 기기 선택값 | OS 권한 상태·법적 동의 이력과 동일하지 않음 |

계정 연동은 authenticated && accountSyncStatus.ready 뒤에 시작한다. disconnect는 원격 연결·목록을 분리하지만 저장 ID 전체를 지우는 정책을 뜻하지 않는다. epoch 방어가 있는 부분과 대기 쓰기·로컬 합집합 정책을 함께 검증한다. 사용자 A의 상태가 B에게 전송되지 않는지, 로그아웃 후 무엇을 남길지는 [검증표](07-review-and-validation.md)에서 다룬다.

근거: [앱 계정 연결](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/flutter_app/lib/app/lala_app.dart), [TripLibraryStore](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/flutter_app/lib/features/trip_library/data/trip_library_store.dart), [기기 저장](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/flutter_app/lib/core/persistence/action_preferences.dart), [기본 취향 저장](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/flutter_app/lib/features/preferences/data/travel_preferences_store.dart).
