# 전체 스키마·테이블·컬럼 참고표

기준 `765570a21ff5ab5207c627d3659e8051be6dbd98`의 canonical SQL 18개를 누적 해석하였다. **53개 테이블·471개 컬럼·49개 FK·7개 뷰**다. DEFAULT·CHECK는 코드 정의이며 실제 DB의 전체 표현식 동등성 검증을 뜻하지 않는다. 업무 해설은 [핵심 데이터 사전](03-data-dictionary.md)을 함께 본다.

컬럼 표의 PK/UNIQUE/FK 표시는 제약 참여 여부다. 복합 키의 정확한 열 조합은 각 테이블 아래 제약 표를 따른다. 키의 일부인 컬럼에 단독 UNIQUE가 있다고 해석하지 않는다.

## 전체 테이블 목록

| 테이블 | 역할 | 컬럼 수 | DB 대조 | 생성 근거 |
|---|---|---|---|---|
| [identity.users](#identity-users) | Logto 식별자와 LALA 서비스 계정 연결 | 7 | DB 공통 컬럼·키 대조 | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) |
| [identity.deleted_users](#identity-deleted_users) | 탈퇴한 식별자의 digest·처리 시각 보관 | 2 | DB 공통 컬럼·키 대조 | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L13) |
| [travel.places](#travel-places) | 장소 기본 정보와 공개 place_id | 18 | DB 공통 컬럼·키 대조 | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| [travel.place_enrichments](#travel-place_enrichments) | 번역·실내 여부 등 장소 보강 이력 | 13 | DB 공통 컬럼·키 대조 | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| [travel.weather_observations](#travel-weather_observations) | 기상·대기질 관측 수집 | 13 | DB 공통 컬럼·키 대조 | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| [travel.docent_scripts](#travel-docent_scripts) | 장소·언어·모드별 도슨트 원고 캐시 | 9 | DB 공통 컬럼·키 대조 | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| [travel.place_events](#travel-place_events) | 장소에 연결되는 행사 정보 | 7 | DB 공통 컬럼·키 대조 | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35) |
| [community.keyword_watchlist](#community-keyword_watchlist) | 외부 수집 키워드·지역 | 4 | DB 공통 컬럼·키 대조 | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L3) |
| [community.ingest_runs](#community-ingest_runs) | 외부 수집 실행·집계 상태 | 17 | DB 공통 컬럼·키 대조 | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11) |
| [community.ingest_tasks](#community-ingest_tasks) | 실행별 키워드 작업 | 8 | DB 공통 컬럼·키 대조 | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |
| [community.posts](#community-posts) | 외부 제공자에서 수집한 게시물 | 10 | DB 공통 컬럼·키 대조 | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| [community.place_mentions_weekly](#community-place_mentions_weekly) | 장소별 주간 언급 집계 | 11 | DB 공통 컬럼·키 대조 | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| [ingest.source_files](#ingest-source_files) | 수집 원본 파일 출처 | 7 | DB 공통 컬럼·키 대조 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3) |
| [culture.events](#culture-events) | 문화 행사 카탈로그 | 14 | DB 공통 컬럼·키 대조 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| [economy.card_spending_area_monthly](#economy-card_spending_area_monthly) | 지역·업종별 월간 소비 통계 | 10 | DB 공통 컬럼·키 대조 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| [economy.card_spending_demographics](#economy-card_spending_demographics) | 인구 구간별 소비 통계 | 10 | DB 공통 컬럼·키 대조 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| [economy.franchise_brands](#economy-franchise_brands) | 프랜차이즈 브랜드 기준 | 13 | DB 공통 컬럼·키 대조 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| [economy.franchise_locations](#economy-franchise_locations) | 브랜드 점포 기준 | 14 | DB 공통 컬럼·키 대조 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| [analytics.place_business_identity](#analytics-place_business_identity) | 장소의 독립 상점·체인 분류 | 10 | DB 공통 컬럼·키 대조 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| [analytics.place_score_snapshots](#analytics-place_score_snapshots) | 추천 점수·산식·근거 스냅샷 | 13 | DB 공통 컬럼·키 대조 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| [rag.knowledge_chunks](#rag-knowledge_chunks) | 장소·문화·집계 근거와 임베딩 | 15 | 공통 컬럼·키 일치 / DB 추가 컬럼 1개 | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| [ops.job_runs](#ops-job_runs) | 배치 실행 상태·시간 | 7 | DB 공통 컬럼·키 대조 | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3) |
| [ops.dependency_checks](#ops-dependency_checks) | 의존 서비스 점검 기록 | 5 | DB 공통 컬럼·키 대조 | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L13) |
| [ops.daily_costs](#ops-daily_costs) | 자원별 일일 비용 기록 | 5 | DB 공통 컬럼·키 대조 | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21) |
| [community.user_posts](#community-user_posts) | 앱 사용자가 작성한 게시물 | 8 | DB 공통 컬럼·키 대조 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |
| [community.post_comments](#community-post_comments) | 사용자 게시물 댓글 | 7 | DB 공통 컬럼·키 대조 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31) |
| [community.post_likes](#community-post_likes) | 사용자 게시물 좋아요 | 4 | DB 공통 컬럼·키 대조 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52) |
| [community.user_follows](#community-user_follows) | 사용자 간 팔로우 | 5 | DB 공통 컬럼·키 대조 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68) |
| [community.chat_rooms](#community-chat_rooms) | 채팅방과 공개 범위·생성자 | 6 | DB에 기본 구조만 존재 / 068 차이 | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L10) |
| [community.chat_messages](#community-chat_messages) | 채팅 메시지 | 6 | DB 공통 컬럼·키 대조 | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19) |
| [ingest.review_sources](#ingest-review_sources) | 허용 출처·이용 조건 등록 | 10 | DB 공통 컬럼·키 대조 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| [ingest.review_ingest_receipts](#ingest-review_ingest_receipts) | 수집 중복·수정판 판정 영수증 | 7 | DB 공통 컬럼·키 대조 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114) |
| [community.ingest_quarantine](#community-ingest_quarantine) | 수집 자료 격리·검토 상태 | 14 | DB 공통 컬럼·키 대조 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| [community.local_signals](#community-local_signals) | 지역 신호 본문·공개·검토 상태 | 19 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| [community.local_signal_places](#community-local_signal_places) | 지역 신호와 장소 연결 | 5 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80) |
| [community.local_signal_routes](#community-local_signal_routes) | 지역 신호와 경로 스냅샷 연결 | 3 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L98) |
| [community.local_signal_translations](#community-local_signal_translations) | 신호 번역·검수·원문 hash | 11 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| [community.local_signal_reactions](#community-local_signal_reactions) | 신호 반응 | 5 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143) |
| [community.local_signal_comments](#community-local_signal_comments) | 신호 댓글·한 단계 답글 | 11 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| [community.local_signal_saves](#community-local_signal_saves) | 신호 저장 | 4 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192) |
| [community.local_signal_reports](#community-local_signal_reports) | 신호·댓글 신고 | 9 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| [community.local_signal_moderation_actions](#community-local_signal_moderation_actions) | 검토·정책 처리 기록 | 9 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| [community.local_signal_capabilities](#community-local_signal_capabilities) | 제한 공유 토큰 hash·만료 | 7 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273) |
| [community.local_signal_aggregate_eligibility](#community-local_signal_aggregate_eligibility) | 집계 활용 적격·동의 판정 | 11 | DB 공통 컬럼·키 대조 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| [planning.user_saved_places](#planning-user_saved_places) | 계정별 저장 장소 현재 집합 | 5 | DB 공통 컬럼·키 대조 | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20) |
| [planning.user_plans](#planning-user_plans) | 계정·날짜별 저장 일정 | 7 | DB 공통 컬럼·키 대조 | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) |
| [planning.slot_visits](#planning-slot_visits) | 일정 날짜·슬롯별 방문 결과 | 12 | DB 공통 컬럼·키 대조 | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| [profile.user_travel_preferences](#profile-user_travel_preferences) | 계정 기본 취향·제약·음성 설정 | 7 | DB 공통 컬럼·키 대조 | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) |
| [planning.trip_preference_overrides](#planning-trip_preference_overrides) | 날짜별 여행 설정 덮어쓰기 | 8 | DB 공통 컬럼·키 대조 | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |
| [community.post_reports](#community-post_reports) | 게시물 신고·처리 상태 | 8 | DB 공통 컬럼·키 대조 | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |
| [community.chat_room_members](#community-chat_room_members) | 채팅방 멤버·역할 | 5 | 코드에만 존재 / DB 없음 | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55) |
| [community.idempotency_keys](#community-idempotency_keys) | 계정별 쓰기 재시도·응답 재생 | 9 | 코드에만 존재 / DB 없음 | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| [community.chat_ws_tickets](#community-chat_ws_tickets) | WebSocket 일회용 티켓 hash·소비 상태 | 7 | 코드에만 존재 / DB 없음 | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118) |

<a id="identity-users"></a>
## identity.users

Logto 식별자와 LALA 서비스 계정 연결. DB 공통 컬럼·키 대조. 생성 근거: [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) |
| `issuer` | `text` | 아니오 | 없음 | UNIQUE | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) |
| `subject` | `text` | 아니오 | 없음 | UNIQUE | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) |
| `status` | `text` | 아니오 | `'active'` | — | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) |
| `last_seen_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) |
| `deletion_requested_at` | `timestamptz` | 예 | 없음 | — | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1) |

제약 정의:

- `PRIMARY KEY` ([SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1))
- `CONSTRAINT identity_users_status_check CHECK (status IN ('active', 'deleting'))` ([SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1))
- `CONSTRAINT identity_users_issuer_subject_key UNIQUE (issuer, subject)` ([SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L1))

<a id="identity-deleted_users"></a>
## identity.deleted_users

탈퇴한 식별자의 digest·처리 시각 보관. DB 공통 컬럼·키 대조. 생성 근거: [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L13).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `identity_digest` | `bytea` | 아니오 | 없음 | UNIQUE | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L13) |
| `deleted_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L13) |

제약 정의:

- `CONSTRAINT identity_deleted_users_digest_length_check CHECK (octet_length(identity_digest) = 32)` ([SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L13))
- `CONSTRAINT identity_deleted_users_identity_digest_key UNIQUE (identity_digest)` ([SQL 005](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/005_identity_users.sql#L13))

<a id="travel-places"></a>
## travel.places

장소 기본 정보와 공개 place_id. DB 공통 컬럼·키 대조. 생성 근거: [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `place_id` | `text` | 아니오 | 없음 | UNIQUE | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `name_ko` | `text` | 아니오 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `name_en` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `category` | `text` | 아니오 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `address_ko` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `address_en` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `image_url` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `region_name_ko` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `region_name_en` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `province_code` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `city_code` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `lat` | `double precision` | 아니오 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `lng` | `double precision` | 아니오 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `is_indoor` | `boolean` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `primary_source` | `text` | 아니오 | `'canonical'` | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `source_record_id` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3) |

제약 정의:

- `PRIMARY KEY` ([SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3))
- `UNIQUE` ([SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3))
- `CONSTRAINT places_category_check CHECK (category IN ('attraction', 'restaurant', 'event', 'culture_venue'))` ([SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L3))

<a id="travel-place_enrichments"></a>
## travel.place_enrichments

번역·실내 여부 등 장소 보강 이력. DB 공통 컬럼·키 대조. 생성 근거: [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `place_id` | `text` | 아니오 | 없음 | FK → travel.places(place_id) | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `enrichment_type` | `text` | 아니오 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `name_en` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `address_en` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `region_name_en` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `is_indoor` | `boolean` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `attributes` | `jsonb` | 아니오 | `CAST('{}' AS jsonb)` | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `confidence` | `numeric(5, 4)` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `source_method` | `text` | 아니오 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `model_name` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `prompt_version` | `text` | 예 | 없음 | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |
| `generated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36) |

제약 정의:

- `PRIMARY KEY` ([SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36))
- `REFERENCES travel.places (place_id)` ([SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L36))

<a id="travel-weather_observations"></a>
## travel.weather_observations

기상·대기질 관측 수집. DB 공통 컬럼·키 대조. 생성 근거: [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `location_name` | `text` | 아니오 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `temperature_c` | `double precision` | 예 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `precipitation_type` | `text` | 예 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `pm10` | `double precision` | 예 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `pm25` | `double precision` | 예 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `is_rain_snow` | `boolean` | 아니오 | `FALSE` | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `is_bad_dust` | `boolean` | 아니오 | `FALSE` | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `is_heatwave` | `boolean` | 아니오 | `FALSE` | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `is_coldwave` | `boolean` | 아니오 | `FALSE` | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `is_strong_wind` | `boolean` | 아니오 | `FALSE` | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `observed_at` | `timestamptz` | 아니오 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |
| `collected_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3) |

제약 정의:

- `PRIMARY KEY` ([SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L3))

<a id="travel-docent_scripts"></a>
## travel.docent_scripts

장소·언어·모드별 도슨트 원고 캐시. DB 공통 컬럼·키 대조. 생성 근거: [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| `place_id` | `text` | 아니오 | 없음 | UNIQUE | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| `category` | `text` | 아니오 | 없음 | UNIQUE | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| `language` | `text` | 아니오 | 없음 | UNIQUE | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| `mode` | `text` | 아니오 | 없음 | UNIQUE | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| `script` | `text` | 아니오 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| `source_method` | `text` | 아니오 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| `generated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |
| `expires_at` | `timestamptz` | 예 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22) |

제약 정의:

- `PRIMARY KEY` ([SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22))
- `UNIQUE (place_id, category, language, mode)` ([SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L22))

<a id="travel-place_events"></a>
## travel.place_events

장소에 연결되는 행사 정보. DB 공통 컬럼·키 대조. 생성 근거: [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35) |
| `place_id` | `text` | 아니오 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35) |
| `title` | `text` | 아니오 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35) |
| `starts_at` | `timestamptz` | 예 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35) |
| `ends_at` | `timestamptz` | 예 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35) |
| `url` | `text` | 예 | 없음 | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35) |

제약 정의:

- `PRIMARY KEY` ([SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L35))

<a id="community-keyword_watchlist"></a>
## community.keyword_watchlist

외부 수집 키워드·지역. DB 공통 컬럼·키 대조. 생성 근거: [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L3).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L3) |
| `keyword` | `text` | 아니오 | 없음 | UNIQUE | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L3) |
| `region_slug` | `text` | 아니오 | 없음 | UNIQUE | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L3) |
| `enabled` | `boolean` | 아니오 | `TRUE` | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L3) |

제약 정의:

- `PRIMARY KEY` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L3))
- `UNIQUE (keyword, region_slug)` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L3))

<a id="community-ingest_runs"></a>
## community.ingest_runs

외부 수집 실행·집계 상태. DB 공통 컬럼·키 대조. 생성 근거: [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11) |
| `provider` | `text` | 아니오 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11) |
| `status` | `text` | 아니오 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11) |
| `started_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11) |
| `finished_at` | `timestamptz` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11) |
| `error_message` | `text` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11) |
| `run_key` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L58) |
| `source_name` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L61) |
| `review_source_name` | `text` | 예 | 없음 | FK → ingest.review_sources(source_name) | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L69) |
| `license_class` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L73) |
| `terms_version` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L76) |
| `schema_version` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L79) |
| `received_count` | `integer` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L82) |
| `processed_count` | `integer` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L85) |
| `duplicate_count` | `integer` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L88) |
| `quarantined_count` | `integer` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L91) |
| `failure_category` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L94) |

제약 정의:

- `PRIMARY KEY` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L11))
- `REFERENCES ingest.review_sources (source_name)` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L69))

<a id="community-ingest_tasks"></a>
## community.ingest_tasks

실행별 키워드 작업. DB 공통 컬럼·키 대조. 생성 근거: [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |
| `run_id` | `uuid` | 아니오 | 없음 | FK → community.ingest_runs(id) | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |
| `keyword` | `text` | 아니오 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |
| `region_slug` | `text` | 아니오 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |
| `status` | `text` | 아니오 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |
| `started_at` | `timestamptz` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |
| `finished_at` | `timestamptz` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |
| `error_message` | `text` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20) |

제약 정의:

- `PRIMARY KEY` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20))
- `REFERENCES community.ingest_runs (id)` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L20))

<a id="community-posts"></a>
## community.posts

외부 제공자에서 수집한 게시물. DB 공통 컬럼·키 대조. 생성 근거: [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `provider` | `text` | 아니오 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `external_key` | `text` | 아니오 | 없음 | UNIQUE | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `keyword` | `text` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `region_slug` | `text` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `title` | `text` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `body` | `text` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `post_url` | `text` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `created_at_source` | `timestamptz` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |
| `collected_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31) |

제약 정의:

- `PRIMARY KEY` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31))
- `UNIQUE` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L31))

<a id="community-place_mentions_weekly"></a>
## community.place_mentions_weekly

장소별 주간 언급 집계. DB 공통 컬럼·키 대조. 생성 근거: [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `week_start` | `date` | 아니오 | 없음 | UNIQUE | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `place_id` | `text` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `place_name_ko` | `text` | 아니오 | 없음 | UNIQUE | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `provider` | `text` | 아니오 | 없음 | UNIQUE | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `category` | `text` | 아니오 | 없음 | UNIQUE | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `mention_count` | `integer` | 아니오 | `0` | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `organic_mention_count` | `integer` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `sentiment_score` | `numeric(5, 4)` | 예 | 없음 | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `attributes` | `jsonb` | 아니오 | `CAST('{}' AS jsonb)` | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44) |

제약 정의:

- `PRIMARY KEY` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44))
- `UNIQUE (week_start, place_name_ko, provider, category)` ([SQL 030](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/030_community_core_tables.sql#L44))

<a id="ingest-source_files"></a>
## ingest.source_files

수집 원본 파일 출처. DB 공통 컬럼·키 대조. 생성 근거: [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3) |
| `source_name` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3) |
| `dataset_name` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3) |
| `file_name` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3) |
| `file_sha256` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3) |
| `downloaded_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3) |
| `local_path` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3) |

제약 정의:

- `PRIMARY KEY` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L3))

<a id="culture-events"></a>
## culture.events

문화 행사 카탈로그. DB 공통 컬럼·키 대조. 생성 근거: [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `event_id` | `text` | 아니오 | 없음 | UNIQUE | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `title_ko` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `title_en` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `event_type` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `venue_name_ko` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `venue_place_id` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `region_name_ko` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `starts_on` | `date` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `ends_on` | `date` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `url` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `primary_source` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `source_record_id` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13) |

제약 정의:

- `PRIMARY KEY` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13))
- `UNIQUE` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L13))

<a id="economy-card_spending_area_monthly"></a>
## economy.card_spending_area_monthly

지역·업종별 월간 소비 통계. DB 공통 컬럼·키 대조. 생성 근거: [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `month` | `date` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `region_name_ko` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `industry_code` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `industry_name_ko` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `spend_amount` | `numeric(18, 2)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `transaction_count` | `integer` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `visitor_type` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `primary_source` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |
| `source_file_id` | `uuid` | 예 | 없음 | FK → ingest.source_files(id) | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33) |

제약 정의:

- `PRIMARY KEY` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33))
- `REFERENCES ingest.source_files (id)` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L33))

<a id="economy-card_spending_demographics"></a>
## economy.card_spending_demographics

인구 구간별 소비 통계. DB 공통 컬럼·키 대조. 생성 근거: [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `month` | `date` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `region_name_ko` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `industry_code` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `gender` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `age_group` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `spend_amount` | `numeric(18, 2)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `transaction_count` | `integer` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `primary_source` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |
| `source_file_id` | `uuid` | 예 | 없음 | FK → ingest.source_files(id) | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49) |

제약 정의:

- `PRIMARY KEY` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49))
- `REFERENCES ingest.source_files (id)` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L49))

<a id="economy-franchise_brands"></a>
## economy.franchise_brands

프랜차이즈 브랜드 기준. DB 공통 컬럼·키 대조. 생성 근거: [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `brand_id` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `brand_name_ko` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `normalized_brand_name` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `headquarters_name_ko` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `business_category` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `main_product` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `franchise_store_count` | `integer` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `average_sales_amount` | `numeric(18, 2)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `chain_scale_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `primary_source` | `text` | 아니오 | `'fair_trade_commission'` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `source_record_id` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65) |

제약 정의:

- `PRIMARY KEY` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65))
- `CONSTRAINT franchise_brands_scale_check CHECK (chain_scale_score IS NULL OR (chain_scale_score >= 0 AND chain_scale_score <= 1))` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L65))

<a id="economy-franchise_locations"></a>
## economy.franchise_locations

브랜드 점포 기준. DB 공통 컬럼·키 대조. 생성 근거: [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `franchise_location_id` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `brand_id` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `brand_name_ko` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `normalized_brand_name` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `store_name_ko` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `normalized_store_name` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `region_name_ko` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `address_ko` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `lat` | `double precision` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `lng` | `double precision` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `primary_source` | `text` | 아니오 | `'fair_trade_commission'` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `source_record_id` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91) |

제약 정의:

- `PRIMARY KEY` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L91))

<a id="analytics-place_business_identity"></a>
## analytics.place_business_identity

장소의 독립 상점·체인 분류. DB 공통 컬럼·키 대조. 생성 근거: [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `place_id` | `text` | 아니오 | 없음 | PK; FK → travel.places(place_id) | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `business_identity_type` | `text` | 아니오 | `'unknown'` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `is_franchise` | `boolean` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `franchise_brand_name` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `franchise_match_confidence` | `numeric(5, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `chain_scale_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `small_merchant_fit_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `matched_source` | `text` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `matched_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |
| `features` | `jsonb` | 아니오 | `CAST('{}' AS jsonb)` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119) |

제약 정의:

- `PRIMARY KEY` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119))
- `REFERENCES travel.places (place_id)` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119))
- `CONSTRAINT place_business_identity_type_check CHECK (business_identity_type IN ('independent_local', 'local_small_chain', 'franchise_store', 'national_franchise', 'corporate_chain', 'unknown'))` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119))
- `CONSTRAINT place_business_identity_confidence_check CHECK (franchise_match_confidence IS NULL OR (franchise_match_confidence >= 0 AND franchise_match_confidence <= 1))` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119))
- `CONSTRAINT place_business_identity_small_score_check CHECK (small_merchant_fit_score IS NULL OR (small_merchant_fit_score >= 0 AND small_merchant_fit_score <= 1))` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L119))

<a id="analytics-place_score_snapshots"></a>
## analytics.place_score_snapshots

추천 점수·산식·근거 스냅샷. DB 공통 컬럼·키 대조. 생성 근거: [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `place_id` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `scored_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `local_spending_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `small_merchant_fit_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `demand_dispersion_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `culture_relevance_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `weather_fit_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `review_quality_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `accessibility_fit_score` | `numeric(7, 4)` | 예 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `final_score` | `numeric(7, 4)` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `formula_version` | `text` | 아니오 | 없음 | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |
| `features` | `jsonb` | 아니오 | `CAST('{}' AS jsonb)` | — | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155) |

제약 정의:

- `PRIMARY KEY` ([SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L155))

<a id="rag-knowledge_chunks"></a>
## rag.knowledge_chunks

장소·문화·집계 근거와 임베딩. 공통 컬럼·키 일치 / DB 추가 컬럼 1개. 생성 근거: [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `source_type` | `text` | 아니오 | 없음 | UNIQUE | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `source_id` | `text` | 아니오 | 없음 | UNIQUE | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `source_table` | `text` | 아니오 | 없음 | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `place_id` | `text` | 예 | 없음 | FK → travel.places(place_id) | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `title_ko` | `text` | 예 | 없음 | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `body_ko` | `text` | 아니오 | 없음 | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `body_en` | `text` | 예 | 없음 | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `metadata` | `jsonb` | 아니오 | `CAST('{}' AS jsonb)` | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `embedding` | `vector(1536)` | 예 | 없음 | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `embedding_model` | `text` | 예 | 없음 | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `embedding_method` | `text` | 아니오 | `'local_hash'` | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `content_sha256` | `text` | 아니오 | 없음 | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `last_embedded_at` | `timestamptz` | 예 | 없음 | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3) |

제약 정의:

- `PRIMARY KEY` ([SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3))
- `REFERENCES travel.places (place_id)` ([SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3))
- `UNIQUE (source_type, source_id)` ([SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3))
- `CONSTRAINT knowledge_chunks_source_type_check CHECK (source_type IN ('place_profile', 'culture_event', 'community_post', 'place_mention', 'weather_context'))` ([SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L3))

<a id="ops-job_runs"></a>
## ops.job_runs

배치 실행 상태·시간. DB 공통 컬럼·키 대조. 생성 근거: [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3) |
| `job_name` | `text` | 아니오 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3) |
| `status` | `text` | 아니오 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3) |
| `started_at` | `timestamptz` | 아니오 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3) |
| `finished_at` | `timestamptz` | 예 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3) |
| `duration_ms` | `integer` | 예 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3) |
| `error_message` | `text` | 예 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3) |

제약 정의:

- `PRIMARY KEY` ([SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L3))

<a id="ops-dependency_checks"></a>
## ops.dependency_checks

의존 서비스 점검 기록. DB 공통 컬럼·키 대조. 생성 근거: [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L13).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L13) |
| `dependency_name` | `text` | 아니오 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L13) |
| `status` | `text` | 아니오 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L13) |
| `latency_ms` | `integer` | 예 | 없음 | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L13) |
| `checked_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L13) |

제약 정의:

- `PRIMARY KEY` ([SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L13))

<a id="ops-daily_costs"></a>
## ops.daily_costs

자원별 일일 비용 기록. DB 공통 컬럼·키 대조. 생성 근거: [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21) |
| `usage_date` | `date` | 아니오 | 없음 | UNIQUE | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21) |
| `resource_name` | `text` | 아니오 | 없음 | UNIQUE | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21) |
| `cost_amount` | `numeric(14, 4)` | 아니오 | `0` | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21) |
| `currency` | `text` | 아니오 | `'KRW'` | — | [SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21) |

제약 정의:

- `PRIMARY KEY` ([SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21))
- `UNIQUE (usage_date, resource_name)` ([SQL 040](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/040_ops_core_tables.sql#L21))

<a id="community-user_posts"></a>
## community.user_posts

앱 사용자가 작성한 게시물. DB 공통 컬럼·키 대조. 생성 근거: [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |
| `author_issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |
| `author_subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |
| `title` | `text` | 아니오 | 없음 | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |
| `body` | `text` | 아니오 | 없음 | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |
| `tags` | `text[]` | 아니오 | `'{}'` | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11) |

제약 정의:

- `PRIMARY KEY` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11))
- `CONSTRAINT fk_user_posts_author FOREIGN KEY (author_issuer, author_subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L11))

<a id="community-post_comments"></a>
## community.post_comments

사용자 게시물 댓글. DB 공통 컬럼·키 대조. 생성 근거: [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31) |
| `post_id` | `uuid` | 아니오 | 없음 | FK → community.user_posts(id) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31) |
| `author_issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31) |
| `author_subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31) |
| `body` | `text` | 아니오 | 없음 | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31) |

제약 정의:

- `PRIMARY KEY` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31))
- `CONSTRAINT fk_post_comments_post FOREIGN KEY (post_id) REFERENCES community.user_posts (id) ON DELETE CASCADE` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31))
- `CONSTRAINT fk_post_comments_author FOREIGN KEY (author_issuer, author_subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L31))

<a id="community-post_likes"></a>
## community.post_likes

사용자 게시물 좋아요. DB 공통 컬럼·키 대조. 생성 근거: [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `post_id` | `uuid` | 아니오 | 없음 | PK; FK → community.user_posts(id) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52) |
| `issuer` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52) |
| `subject` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52) |

제약 정의:

- `PRIMARY KEY (post_id, issuer, subject)` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52))
- `CONSTRAINT fk_post_likes_post FOREIGN KEY (post_id) REFERENCES community.user_posts (id) ON DELETE CASCADE` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52))
- `CONSTRAINT fk_post_likes_author FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L52))

<a id="community-user_follows"></a>
## community.user_follows

사용자 간 팔로우. DB 공통 컬럼·키 대조. 생성 근거: [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `follower_issuer` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68) |
| `follower_subject` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68) |
| `followee_issuer` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68) |
| `followee_subject` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68) |

제약 정의:

- `PRIMARY KEY (follower_issuer, follower_subject, followee_issuer, followee_subject)` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68))
- `CONSTRAINT fk_user_follows_follower FOREIGN KEY (follower_issuer, follower_subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68))
- `CONSTRAINT fk_user_follows_followee FOREIGN KEY (followee_issuer, followee_subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L68))

<a id="community-chat_rooms"></a>
## community.chat_rooms

채팅방과 공개 범위·생성자. DB에 기본 구조만 존재 / 068 차이. 생성 근거: [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L10).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L10) |
| `name` | `text` | 아니오 | 없음 | — | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L10) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L10) |
| `visibility` | `text` | 아니오 | `'public'` | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L17) |
| `created_by_issuer` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L20) |
| `created_by_subject` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L23) |

제약 정의:

- `PRIMARY KEY` ([SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L10))
- `CONSTRAINT chat_rooms_visibility_check CHECK (visibility IN ('public', 'private'))` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L29))
- `CONSTRAINT fk_chat_rooms_creator FOREIGN KEY (created_by_issuer, created_by_subject) REFERENCES identity.users (issuer, subject) ON DELETE SET NULL` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L36))

<a id="community-chat_messages"></a>
## community.chat_messages

채팅 메시지. DB 공통 컬럼·키 대조. 생성 근거: [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19) |
| `room_id` | `uuid` | 아니오 | 없음 | FK → community.chat_rooms(id) | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19) |
| `author_issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19) |
| `author_subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19) |
| `body` | `text` | 아니오 | 없음 | — | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19) |

제약 정의:

- `PRIMARY KEY` ([SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19))
- `CONSTRAINT fk_chat_messages_room FOREIGN KEY (room_id) REFERENCES community.chat_rooms (id) ON DELETE CASCADE` ([SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19))
- `CONSTRAINT fk_chat_messages_author FOREIGN KEY (author_issuer, author_subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L19))

<a id="ingest-review_sources"></a>
## ingest.review_sources

허용 출처·이용 조건 등록. DB 공통 컬럼·키 대조. 생성 근거: [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `source_name` | `text` | 아니오 | 없음 | PK | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `provider` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `license_class` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `terms_version` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `collection_method` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `retention_policy` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `redaction_policy` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `source_status` | `text` | 아니오 | `'active'` | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `approved_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27) |

제약 정의:

- `PRIMARY KEY` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27))
- `CONSTRAINT review_sources_license_class_check CHECK (license_class IN ('licensed', 'public_processed', 'approved_export', 'rejected'))` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27))
- `CONSTRAINT review_sources_status_check CHECK (source_status IN ('active', 'disabled'))` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L27))

<a id="ingest-review_ingest_receipts"></a>
## ingest.review_ingest_receipts

수집 중복·수정판 판정 영수증. DB 공통 컬럼·키 대조. 생성 근거: [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `source_name` | `text` | 아니오 | 없음 | FK → ingest.review_sources(source_name); PK | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114) |
| `external_key` | `text` | 아니오 | 없음 | PK | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114) |
| `content_sha256` | `text` | 아니오 | 없음 | PK | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114) |
| `first_run_id` | `uuid` | 아니오 | 없음 | FK → community.ingest_runs(id) | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114) |
| `last_run_id` | `uuid` | 아니오 | 없음 | FK → community.ingest_runs(id) | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114) |
| `first_seen_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114) |
| `last_seen_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114) |

제약 정의:

- `REFERENCES ingest.review_sources (source_name)` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114))
- `REFERENCES community.ingest_runs (id)` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114))
- `REFERENCES community.ingest_runs (id)` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114))
- `PRIMARY KEY (source_name, external_key, content_sha256)` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L114))

<a id="community-ingest_quarantine"></a>
## community.ingest_quarantine

수집 자료 격리·검토 상태. DB 공통 컬럼·키 대조. 생성 근거: [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `source_run_id` | `uuid` | 예 | 없음 | FK → community.ingest_runs(id) | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `source_name` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `provider` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `external_key` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `content_sha256` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `reason_category` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `reason_code` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `reason` | `text` | 아니오 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `received_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `quarantined_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `resolved_at` | `timestamptz` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `resolution` | `text` | 예 | 없음 | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |
| `safe_metadata` | `jsonb` | 아니오 | `CAST('{}' AS jsonb)` | — | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137) |

제약 정의:

- `PRIMARY KEY` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137))
- `REFERENCES community.ingest_runs (id)` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137))
- `CONSTRAINT ingest_quarantine_reason_category_check CHECK (reason_category IN ('schema_invalid', 'terms_violation', 'source_api_failure', 'duplicate_suspect', 'low_confidence', 'ambiguous_match'))` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137))
- `CONSTRAINT ingest_quarantine_resolution_check CHECK (resolution IS NULL OR resolution IN ('approved', 'rejected', 'retried'))` ([SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L137))

<a id="community-local_signals"></a>
## community.local_signals

지역 신호 본문·공개·검토 상태. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `author_issuer` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `author_subject` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `kind` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `status` | `text` | 아니오 | `'draft'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `moderation_state` | `text` | 아니오 | `'unreviewed'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `visibility` | `text` | 아니오 | `'private'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `source_language` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `title` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `body` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `locality_level` | `text` | 아니오 | `'district'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `locality_code` | `text` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `commercial_disclosure` | `text` | 아니오 | `'none'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `observation_date` | `date` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `aggregate_opt_in` | `boolean` | 아니오 | `FALSE` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `source_kind` | `text` | 아니오 | `'first_party'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `published_at` | `timestamptz` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5) |

제약 정의:

- `PRIMARY KEY` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT fk_local_signals_author FOREIGN KEY (author_issuer, author_subject) REFERENCES identity.users (issuer, subject) ON DELETE SET NULL` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_author_pair_check CHECK ((author_issuer IS NULL AND author_subject IS NULL) OR (author_issuer IS NOT NULL AND author_subject IS NOT NULL))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_kind_check CHECK (kind IN ('place_tip', 'route_note', 'local_question', 'accessibility_note', 'seasonal_update', 'correction', 'local_story'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_status_check CHECK (status IN ('draft', 'submitted', 'published', 'hidden', 'removed', 'deleted'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_moderation_state_check CHECK (moderation_state IN ('unreviewed', 'pending', 'approved', 'rejected'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_visibility_check CHECK (visibility IN ('private', 'pending_review', 'public', 'unlisted'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_language_check CHECK (source_language IN ('ko', 'en'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_title_length_check CHECK (char_length(title) BETWEEN 1 AND 160)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_body_length_check CHECK (char_length(body) BETWEEN 1 AND 4000)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_locality_check CHECK (locality_level IN ('none', 'province', 'city', 'district', 'place'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_locality_code_check CHECK (locality_code IS NULL OR locality_code ~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,63}$')` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_disclosure_check CHECK (commercial_disclosure IN ('none', 'visitor', 'owner_or_staff', 'paid_or_gifted'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_source_kind_check CHECK (source_kind = 'first_party')` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))
- `CONSTRAINT local_signals_publication_check CHECK (status <> 'published' OR published_at IS NOT NULL)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L5))

<a id="community-local_signal_places"></a>
## community.local_signal_places

지역 신호와 장소 연결. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `signal_id` | `uuid` | 아니오 | 없음 | FK → community.local_signals(id); PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80) |
| `place_id` | `text` | 아니오 | 없음 | FK → travel.places(place_id); PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80) |
| `relation` | `text` | 아니오 | `'primary'` | PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80) |
| `source_confidence` | `numeric(5, 4)` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80) |

제약 정의:

- `REFERENCES community.local_signals (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80))
- `REFERENCES travel.places (place_id)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80))
- `PRIMARY KEY (signal_id, place_id, relation)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80))
- `CONSTRAINT local_signal_places_relation_check CHECK (relation IN ('primary', 'context', 'route_stop'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80))
- `CONSTRAINT local_signal_places_confidence_check CHECK (source_confidence IS NULL OR source_confidence BETWEEN 0 AND 1)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L80))

<a id="community-local_signal_routes"></a>
## community.local_signal_routes

지역 신호와 경로 스냅샷 연결. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L98).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `signal_id` | `uuid` | 아니오 | 없음 | PK; FK → community.local_signals(id) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L98) |
| `route_snapshot_ref` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L98) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L98) |

제약 정의:

- `PRIMARY KEY` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L98))
- `REFERENCES community.local_signals (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L98))
- `CONSTRAINT local_signal_routes_ref_check CHECK (route_snapshot_ref ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L98))

<a id="community-local_signal_translations"></a>
## community.local_signal_translations

신호 번역·검수·원문 hash. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `signal_id` | `uuid` | 아니오 | 없음 | FK → community.local_signals(id); UNIQUE | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `target_language` | `text` | 아니오 | 없음 | UNIQUE | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `body` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `translation_method` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `translator_version` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `source_content_hash` | `text` | 아니오 | 없음 | UNIQUE | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `provenance` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `review_state` | `text` | 아니오 | `'pending'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `reviewed_at` | `timestamptz` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107) |

제약 정의:

- `PRIMARY KEY` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))
- `REFERENCES community.local_signals (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))
- `CONSTRAINT local_signal_translations_language_check CHECK (target_language IN ('ko', 'en'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))
- `CONSTRAINT local_signal_translations_body_length_check CHECK (char_length(body) BETWEEN 1 AND 4000)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))
- `CONSTRAINT local_signal_translations_method_check CHECK (translation_method IN ('human', 'machine', 'community_reviewed'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))
- `CONSTRAINT local_signal_translations_hash_check CHECK (source_content_hash ~ '^[0-9a-f]{64}$')` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))
- `CONSTRAINT local_signal_translations_provenance_check CHECK (provenance IN ('author_source', 'human_review', 'machine_reviewed', 'community_reviewed'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))
- `CONSTRAINT local_signal_translations_state_check CHECK (review_state IN ('pending', 'available', 'stale', 'rejected'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))
- `UNIQUE (signal_id, target_language, source_content_hash)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L107))

<a id="community-local_signal_reactions"></a>
## community.local_signal_reactions

신호 반응. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `signal_id` | `uuid` | 아니오 | 없음 | FK → community.local_signals(id); PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143) |
| `issuer` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143) |
| `subject` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143) |
| `reaction_type` | `text` | 아니오 | 없음 | PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143) |

제약 정의:

- `REFERENCES community.local_signals (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143))
- `PRIMARY KEY (signal_id, issuer, subject, reaction_type)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143))
- `CONSTRAINT fk_local_signal_reactions_actor FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143))
- `CONSTRAINT local_signal_reactions_type_check CHECK (reaction_type IN ('useful', 'respectful', 'needs_confirmation'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L143))

<a id="community-local_signal_comments"></a>
## community.local_signal_comments

신호 댓글·한 단계 답글. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `signal_id` | `uuid` | 아니오 | 없음 | FK → community.local_signals(id) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `parent_id` | `uuid` | 예 | 없음 | FK → community.local_signal_comments(id) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `author_issuer` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `author_subject` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `source_language` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `body` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `status` | `text` | 아니오 | `'submitted'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `depth` | `smallint` | 아니오 | `0` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159) |

제약 정의:

- `PRIMARY KEY` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))
- `REFERENCES community.local_signals (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))
- `REFERENCES community.local_signal_comments (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))
- `CONSTRAINT fk_local_signal_comments_author FOREIGN KEY (author_issuer, author_subject) REFERENCES identity.users (issuer, subject) ON DELETE SET NULL` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))
- `CONSTRAINT local_signal_comments_author_pair_check CHECK ((author_issuer IS NULL AND author_subject IS NULL) OR (author_issuer IS NOT NULL AND author_subject IS NOT NULL))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))
- `CONSTRAINT local_signal_comments_language_check CHECK (source_language IN ('ko', 'en'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))
- `CONSTRAINT local_signal_comments_body_length_check CHECK (char_length(body) BETWEEN 1 AND 1200)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))
- `CONSTRAINT local_signal_comments_status_check CHECK (status IN ('submitted', 'published', 'hidden', 'removed', 'deleted'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))
- `CONSTRAINT local_signal_comments_depth_check CHECK ((parent_id IS NULL AND depth = 0) OR (parent_id IS NOT NULL AND depth = 1))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L159))

<a id="community-local_signal_saves"></a>
## community.local_signal_saves

신호 저장. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `signal_id` | `uuid` | 아니오 | 없음 | FK → community.local_signals(id); PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192) |
| `issuer` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192) |
| `subject` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192) |

제약 정의:

- `REFERENCES community.local_signals (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192))
- `PRIMARY KEY (signal_id, issuer, subject)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192))
- `CONSTRAINT fk_local_signal_saves_actor FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L192))

<a id="community-local_signal_reports"></a>
## community.local_signal_reports

신호·댓글 신고. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| `target_type` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| `target_id` | `uuid` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| `reporter_issuer` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| `reporter_subject` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| `reason_code` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| `status` | `text` | 아니오 | `'open'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |
| `resolved_at` | `timestamptz` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204) |

제약 정의:

- `PRIMARY KEY` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204))
- `CONSTRAINT fk_local_signal_reports_reporter FOREIGN KEY (reporter_issuer, reporter_subject) REFERENCES identity.users (issuer, subject) ON DELETE SET NULL` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204))
- `CONSTRAINT local_signal_reports_reporter_pair_check CHECK ((reporter_issuer IS NULL AND reporter_subject IS NULL) OR (reporter_issuer IS NOT NULL AND reporter_subject IS NOT NULL))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204))
- `CONSTRAINT local_signal_reports_target_check CHECK (target_type IN ('signal', 'comment'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204))
- `CONSTRAINT local_signal_reports_reason_check CHECK (reason_code IN ('unsafe_content', 'privacy_exposure', 'misleading_place', 'promotion_not_disclosed', 'translation_issue', 'other_policy'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204))
- `CONSTRAINT local_signal_reports_status_check CHECK (status IN ('open', 'triaged', 'actioned', 'dismissed'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L204))

<a id="community-local_signal_moderation_actions"></a>
## community.local_signal_moderation_actions

검토·정책 처리 기록. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| `target_type` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| `target_id` | `uuid` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| `action_type` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| `reason_code` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| `actor_issuer` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| `actor_subject` | `text` | 예 | 없음 | FK → identity.users(issuer,subject) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| `policy_version` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244) |

제약 정의:

- `PRIMARY KEY` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244))
- `CONSTRAINT fk_local_signal_moderation_actor FOREIGN KEY (actor_issuer, actor_subject) REFERENCES identity.users (issuer, subject) ON DELETE SET NULL` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244))
- `CONSTRAINT local_signal_moderation_actor_pair_check CHECK ((actor_issuer IS NULL AND actor_subject IS NULL) OR (actor_issuer IS NOT NULL AND actor_subject IS NOT NULL))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244))
- `CONSTRAINT local_signal_moderation_target_check CHECK (target_type IN ('signal', 'comment'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244))
- `CONSTRAINT local_signal_moderation_action_check CHECK (action_type IN ('submit', 'publish', 'hide', 'remove', 'restore', 'delete', 'redact'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L244))

<a id="community-local_signal_capabilities"></a>
## community.local_signal_capabilities

제한 공유 토큰 hash·만료. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273) |
| `signal_id` | `uuid` | 아니오 | 없음 | FK → community.local_signals(id) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273) |
| `token_sha256` | `bytea` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273) |
| `scope` | `text` | 아니오 | `'read'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273) |
| `expires_at` | `timestamptz` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273) |
| `revoked_at` | `timestamptz` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273) |

제약 정의:

- `PRIMARY KEY` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273))
- `REFERENCES community.local_signals (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273))
- `CONSTRAINT local_signal_capabilities_hash_check CHECK (octet_length(token_sha256) = 32)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273))
- `CONSTRAINT local_signal_capabilities_scope_check CHECK (scope = 'read')` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L273))

<a id="community-local_signal_aggregate_eligibility"></a>
## community.local_signal_aggregate_eligibility

집계 활용 적격·동의 판정. DB 공통 컬럼·키 대조. 생성 근거: [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `signal_id` | `uuid` | 아니오 | 없음 | PK; FK → community.local_signals(id) | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `eligibility_status` | `text` | 아니오 | `'ineligible'` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `aggregate_opt_in` | `boolean` | 아니오 | `FALSE` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `moderation_passed` | `boolean` | 아니오 | `FALSE` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `independent_signal_count` | `integer` | 아니오 | `0` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `minimum_signal_count` | `integer` | 아니오 | `3` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `aggregate_scope` | `text` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `delayed_until` | `timestamptz` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `safe_summary_hash` | `text` | 예 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `policy_version` | `text` | 아니오 | 없음 | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289) |

제약 정의:

- `PRIMARY KEY` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289))
- `REFERENCES community.local_signals (id) ON DELETE CASCADE` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289))
- `CONSTRAINT local_signal_aggregate_status_check CHECK (eligibility_status IN ('ineligible', 'eligible', 'revoked'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289))
- `CONSTRAINT local_signal_aggregate_count_check CHECK (independent_signal_count >= 0 AND minimum_signal_count >= 3)` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289))
- `CONSTRAINT local_signal_aggregate_scope_check CHECK (aggregate_scope IS NULL OR aggregate_scope IN ('place_week', 'district_week'))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289))
- `CONSTRAINT local_signal_aggregate_hash_check CHECK (safe_summary_hash IS NULL OR safe_summary_hash ~ '^[0-9a-f]{64}$')` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289))
- `CONSTRAINT local_signal_aggregate_eligible_gate CHECK (eligibility_status <> 'eligible' OR (aggregate_opt_in AND moderation_passed AND aggregate_scope IS NOT NULL AND safe_summary_hash IS NOT NULL))` ([SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L289))

<a id="planning-user_saved_places"></a>
## planning.user_saved_places

계정별 저장 장소 현재 집합. DB 공통 컬럼·키 대조. 생성 근거: [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20) |
| `subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20) |
| `place_id` | `text` | 아니오 | 없음 | PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20) |
| `source` | `text` | 아니오 | `'public_mvp_snapshot'` | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20) |
| `saved_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20) |

제약 정의:

- `CONSTRAINT fk_user_saved_places_owner FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20))
- `CONSTRAINT user_saved_places_pkey PRIMARY KEY (issuer, subject, place_id)` ([SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L20))

<a id="planning-user_plans"></a>
## planning.user_plans

계정·날짜별 저장 일정. DB 공통 컬럼·키 대조. 생성 근거: [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) |
| `subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) |
| `plan_date` | `date` | 아니오 | 없음 | PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) |
| `schema_version` | `integer` | 아니오 | 없음 | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) |
| `envelope` | `jsonb` | 아니오 | 없음 | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40) |

제약 정의:

- `CONSTRAINT fk_user_plans_owner FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40))
- `CONSTRAINT user_plans_pkey PRIMARY KEY (issuer, subject, plan_date)` ([SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40))
- `CONSTRAINT user_plans_schema_version_check CHECK (schema_version > 0)` ([SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L40))

<a id="planning-slot_visits"></a>
## planning.slot_visits

일정 날짜·슬롯별 방문 결과. DB 공통 컬럼·키 대조. 생성 근거: [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `plan_date` | `date` | 아니오 | 없음 | PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `slot_period` | `text` | 아니오 | 없음 | PK | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `place_id` | `text` | 예 | 없음 | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `status` | `text` | 아니오 | `'planned'` | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `visited_at` | `timestamptz` | 예 | 없음 | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58) |
| `reason_code` | `text` | 예 | 없음 | — | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L30) |
| `use_for_recommendations` | `boolean` | 아니오 | `FALSE` | — | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L33) |
| `confirmed_at` | `timestamptz` | 예 | 없음 | — | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L36) |

제약 정의:

- `CONSTRAINT fk_slot_visits_owner FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58))
- `CONSTRAINT slot_visits_pkey PRIMARY KEY (issuer, subject, plan_date, slot_period)` ([SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58))
- `CONSTRAINT slot_visits_slot_period_check CHECK (slot_period IN ('morning', 'lunch', 'afternoon', 'dinner'))` ([SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L58))
- `CONSTRAINT slot_visits_status_check CHECK (status IN ('planned', 'visited', 'not_visited'))` ([SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L42))
- `CONSTRAINT slot_visits_reason_code_check CHECK (reason_code IS NULL OR reason_code IN ('closed', 'weather', 'crowded', 'time', 'transport', 'changed_mind', 'other'))` ([SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L49))
- `CONSTRAINT slot_visits_feedback_shape_check CHECK ((status = 'not_visited' OR reason_code IS NULL) AND (status <> 'planned' OR use_for_recommendations = FALSE))` ([SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L61))

<a id="profile-user_travel_preferences"></a>
## profile.user_travel_preferences

계정 기본 취향·제약·음성 설정. DB 공통 컬럼·키 대조. 생성 근거: [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) |
| `subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) |
| `schema_version` | `integer` | 아니오 | `1` | — | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) |
| `revision` | `bigint` | 아니오 | `1` | — | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) |
| `payload` | `jsonb` | 아니오 | 없음 | — | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10) |

제약 정의:

- `CONSTRAINT fk_user_travel_preferences_owner FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10))
- `CONSTRAINT user_travel_preferences_pkey PRIMARY KEY (issuer, subject)` ([SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10))
- `CONSTRAINT user_travel_preferences_schema_version_check CHECK (schema_version = 1)` ([SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10))
- `CONSTRAINT user_travel_preferences_revision_check CHECK (revision > 0)` ([SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10))
- `CONSTRAINT user_travel_preferences_payload_object_check CHECK (jsonb_typeof(payload) = 'object')` ([SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L10))

<a id="planning-trip_preference_overrides"></a>
## planning.trip_preference_overrides

날짜별 여행 설정 덮어쓰기. DB 공통 컬럼·키 대조. 생성 근거: [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |
| `subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |
| `plan_date` | `date` | 아니오 | 없음 | PK | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |
| `schema_version` | `integer` | 아니오 | `1` | — | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |
| `revision` | `bigint` | 아니오 | `1` | — | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |
| `payload` | `jsonb` | 아니오 | 없음 | — | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |
| `updated_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5) |

제약 정의:

- `CONSTRAINT fk_trip_preference_overrides_owner FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5))
- `CONSTRAINT trip_preference_overrides_pkey PRIMARY KEY (issuer, subject, plan_date)` ([SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5))
- `CONSTRAINT trip_preference_overrides_schema_version_check CHECK (schema_version = 1)` ([SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5))
- `CONSTRAINT trip_preference_overrides_revision_check CHECK (revision > 0)` ([SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5))
- `CONSTRAINT trip_preference_overrides_payload_object_check CHECK (jsonb_typeof(payload) = 'object')` ([SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L5))

<a id="community-post_reports"></a>
## community.post_reports

게시물 신고·처리 상태. DB 공통 컬럼·키 대조. 생성 근거: [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `id` | `uuid` | 아니오 | `gen_random_uuid()` | PK | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |
| `post_id` | `uuid` | 아니오 | 없음 | FK → community.user_posts(id) | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |
| `reporter_issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |
| `reporter_subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |
| `reason_code` | `text` | 아니오 | 없음 | — | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |
| `status` | `text` | 아니오 | `'open'` | — | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |
| `resolved_at` | `timestamptz` | 예 | 없음 | — | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6) |

제약 정의:

- `PRIMARY KEY` ([SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6))
- `REFERENCES community.user_posts (id) ON DELETE CASCADE` ([SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6))
- `CONSTRAINT fk_post_reports_reporter FOREIGN KEY (reporter_issuer, reporter_subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6))
- `CONSTRAINT post_reports_reason_check CHECK (reason_code IN ('spam_promotion', 'harassment_hate', 'explicit_content', 'privacy_exposure', 'misinformation', 'other_policy'))` ([SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6))
- `CONSTRAINT post_reports_status_check CHECK (status IN ('open', 'triaged', 'actioned', 'dismissed'))` ([SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L6))

<a id="community-chat_room_members"></a>
## community.chat_room_members

채팅방 멤버·역할. 코드에만 존재 / DB 없음. 생성 근거: [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `room_id` | `uuid` | 아니오 | 없음 | PK; FK → community.chat_rooms(id) | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55) |
| `issuer` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55) |
| `subject` | `text` | 아니오 | 없음 | PK; FK → identity.users(issuer,subject) | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55) |
| `role` | `text` | 아니오 | `'member'` | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55) |

제약 정의:

- `PRIMARY KEY (room_id, issuer, subject)` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55))
- `CONSTRAINT fk_chat_room_members_room FOREIGN KEY (room_id) REFERENCES community.chat_rooms (id) ON DELETE CASCADE` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55))
- `CONSTRAINT fk_chat_room_members_member FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55))
- `CONSTRAINT chat_room_members_role_check CHECK (role IN ('owner', 'member'))` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L55))

<a id="community-idempotency_keys"></a>
## community.idempotency_keys

계정별 쓰기 재시도·응답 재생. 코드에만 존재 / DB 없음. 생성 근거: [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `scope` | `text` | 아니오 | 없음 | PK | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| `actor_issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| `actor_subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject); PK | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| `idempotency_key` | `text` | 아니오 | 없음 | PK | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| `request_hash` | `text` | 아니오 | 없음 | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| `response_json` | `jsonb` | 아니오 | 없음 | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| `status_code` | `integer` | 아니오 | `200` | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |
| `expires_at` | `timestamptz` | 아니오 | 없음 | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87) |

제약 정의:

- `CONSTRAINT idempotency_keys_scope_check CHECK (scope IN ('community.post.create', 'community.chat.message.create'))` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87))
- `CONSTRAINT idempotency_keys_key_len_check CHECK (char_length(idempotency_key) BETWEEN 1 AND 200)` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87))
- `CONSTRAINT idempotency_keys_hash_len_check CHECK (char_length(request_hash) = 64)` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87))
- `CONSTRAINT fk_idempotency_keys_actor FOREIGN KEY (actor_issuer, actor_subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87))
- `PRIMARY KEY (scope, actor_issuer, actor_subject, idempotency_key)` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L87))

<a id="community-chat_ws_tickets"></a>
## community.chat_ws_tickets

WebSocket 일회용 티켓 hash·소비 상태. 코드에만 존재 / DB 없음. 생성 근거: [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118).

| 컬럼 | 타입 | NULL 허용 | DEFAULT (코드) | 키 | 정의 근거 |
|---|---|---|---|---|---|
| `ticket_hash` | `text` | 아니오 | 없음 | PK | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118) |
| `room_id` | `uuid` | 아니오 | 없음 | FK → community.chat_rooms(id) | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118) |
| `issuer` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118) |
| `subject` | `text` | 아니오 | 없음 | FK → identity.users(issuer,subject) | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118) |
| `created_at` | `timestamptz` | 아니오 | `now()` | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118) |
| `expires_at` | `timestamptz` | 아니오 | 없음 | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118) |
| `used_at` | `timestamptz` | 예 | 없음 | — | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118) |

제약 정의:

- `PRIMARY KEY` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118))
- `CONSTRAINT fk_chat_ws_tickets_room FOREIGN KEY (room_id) REFERENCES community.chat_rooms (id) ON DELETE CASCADE` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118))
- `CONSTRAINT fk_chat_ws_tickets_actor FOREIGN KEY (issuer, subject) REFERENCES identity.users (issuer, subject) ON DELETE CASCADE` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118))
- `CONSTRAINT chat_ws_tickets_ticket_hash_check CHECK (char_length(ticket_hash) = 64)` ([SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L118))

## 조회 뷰 7개

### travel.public_places

[SQL 050](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/050_views_and_indexes.sql#L3)

```sql
CREATE OR REPLACE VIEW travel.public_places AS SELECT place_id, name_ko, name_en, category, address_ko, address_en, region_name_ko, region_name_en, region_name_ko AS region_ko, region_name_en AS region_en, province_code, city_code, lat, lng, is_indoor, primary_source AS source, primary_source, source_record_id, updated_at, image_url FROM travel.places;
```

### compat.legacy_places_api

[SQL 050](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/050_views_and_indexes.sql#L27)

```sql
CREATE OR REPLACE VIEW compat.legacy_places_api AS SELECT place_id AS id, place_id, COALESCE(name_ko, name_en, place_id) AS name, name_ko, COALESCE(name_en, name_ko, place_id) AS name_en, lat, lng, category, COALESCE(address_ko, '') AS address, COALESCE(address_ko, '') AS road_addr, COALESCE(address_en, address_ko, '') AS address_en, COALESCE(region_ko, '') AS region, COALESCE(region_en, region_ko, '') AS region_en, is_indoor, image_url, FALSE AS is_approximate_location, CAST(NULL AS text) AS event_start_date, CAST(NULL AS text) AS event_end_date, CAST(NULL AS text) AS event_url, category AS source_type, source AS upstream_source, updated_at FROM travel.public_places;
```

### compat.legacy_docent_scripts_api

[SQL 050](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/050_views_and_indexes.sql#L53)

```sql
CREATE OR REPLACE VIEW compat.legacy_docent_scripts_api AS SELECT place_id, category, language, mode, script, source_method AS upstream_source, generated_at AS created_at, generated_at, expires_at, CASE WHEN expires_at IS NULL THEN NULL ELSE GREATEST(0, CAST(floor(EXTRACT(EPOCH FROM expires_at - now())) AS integer)) END AS ttl_sec FROM travel.docent_scripts WHERE expires_at IS NULL OR expires_at > now();
```

### travel.latest_weather

[SQL 050](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/050_views_and_indexes.sql#L71)

```sql
CREATE OR REPLACE VIEW travel.latest_weather AS SELECT DISTINCT ON (location_name) location_name AS location, temperature_c AS temperature, CAST(temperature_c AS text) AS temp, precipitation_type, pm10, pm25, is_rain_snow, is_bad_dust, is_heatwave, is_coldwave, is_strong_wind, observed_at AS record_time, collected_at AS created_at FROM travel.weather_observations ORDER BY location_name, observed_at DESC;
```

### ops.dependency_latest

[SQL 050](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/050_views_and_indexes.sql#L89)

```sql
CREATE OR REPLACE VIEW ops.dependency_latest AS SELECT DISTINCT ON (dependency_name) dependency_name, status, latency_ms, checked_at FROM ops.dependency_checks ORDER BY dependency_name, checked_at DESC;
```

### community.local_signal_public

[SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L326)

```sql
CREATE OR REPLACE VIEW community.local_signal_public AS SELECT id, kind, source_language, title, body, locality_level, locality_code, commercial_disclosure, observation_date, published_at, created_at, updated_at FROM community.local_signals WHERE status = 'published' AND moderation_state = 'approved' AND visibility = 'public';
```

### community.local_signal_aggregate_candidates

[SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L347)

```sql
CREATE OR REPLACE VIEW community.local_signal_aggregate_candidates AS SELECT eligibility.signal_id, signal.kind, signal.source_language, signal.locality_level, signal.locality_code, signal.observation_date, eligibility.aggregate_scope, eligibility.independent_signal_count, eligibility.minimum_signal_count, eligibility.delayed_until, eligibility.safe_summary_hash, eligibility.policy_version FROM community.local_signal_aggregate_eligibility AS eligibility INNER JOIN community.local_signals AS signal ON signal.id = eligibility.signal_id WHERE signal.status = 'published' AND signal.moderation_state = 'approved' AND signal.visibility = 'public' AND eligibility.eligibility_status = 'eligible';
```

## 명시적 인덱스 목록

| 테이블 | 인덱스 | UNIQUE | SQL |
|---|---|---|---|
| travel.places | idx_places_category | 아니오 | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L27) |
| travel.places | idx_places_lat_lng | 아니오 | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L28) |
| travel.places | idx_places_geog_expr | 아니오 | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L30) |
| travel.places | idx_places_region_name_ko | 아니오 | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L31) |
| travel.place_enrichments | idx_place_enrichments_place_id | 아니오 | [SQL 010](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/010_travel_core_tables.sql#L53) |
| travel.weather_observations | idx_weather_observations_location_observed_at | 아니오 | [SQL 020](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/020_travel_domain_tables.sql#L20) |
| culture.events | idx_culture_events_region_name_ko | 아니오 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L31) |
| economy.card_spending_area_monthly | idx_card_spending_area_monthly_region_month | 아니오 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L47) |
| economy.card_spending_demographics | idx_card_spending_demographics_region_month | 아니오 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L63) |
| economy.franchise_brands | idx_franchise_brands_source_record | 예 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L85) |
| economy.franchise_brands | idx_franchise_brands_normalized_name | 아니오 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L89) |
| economy.franchise_locations | idx_franchise_locations_source_record | 예 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L109) |
| economy.franchise_locations | idx_franchise_locations_normalized_brand | 아니오 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L113) |
| economy.franchise_locations | idx_franchise_locations_lat_lng | 아니오 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L116) |
| analytics.place_business_identity | idx_place_business_identity_type | 아니오 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L153) |
| analytics.place_score_snapshots | idx_place_score_snapshots_place_scored_at | 아니오 | [SQL 035](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/035_data_pipeline_tables.sql#L178) |
| rag.knowledge_chunks | idx_knowledge_chunks_place_id | 아니오 | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L32) |
| rag.knowledge_chunks | idx_knowledge_chunks_source_type_updated_at | 아니오 | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L36) |
| rag.knowledge_chunks | idx_knowledge_chunks_content_sha256 | 아니오 | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L39) |
| rag.knowledge_chunks | idx_knowledge_chunks_embedding_cosine | 아니오 | [SQL 036](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/036_rag_knowledge_tables.sql#L42) |
| community.user_posts | idx_user_posts_created_at | 아니오 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L27) |
| community.user_posts | idx_user_posts_author | 아니오 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L29) |
| community.post_comments | idx_post_comments_post | 아니오 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L50) |
| community.user_follows | idx_user_follows_follower | 아니오 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L86) |
| community.user_follows | idx_user_follows_followee | 아니오 | [SQL 060](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/060_community_tables.sql#L88) |
| community.chat_rooms | idx_chat_rooms_created_at | 아니오 | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L17) |
| community.chat_messages | idx_chat_messages_room | 아니오 | [SQL 061](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/061_community_chat_tables.sql#L37) |
| ingest.review_sources | idx_review_sources_license_class | 아니오 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L47) |
| community.ingest_runs | idx_community_ingest_runs_run_key | 예 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L101) |
| ingest.review_ingest_receipts | idx_review_ingest_receipts_external_key | 아니오 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L128) |
| community.ingest_quarantine | idx_community_ingest_quarantine_run | 아니오 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L168) |
| community.ingest_quarantine | idx_community_ingest_quarantine_unresolved | 아니오 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L172) |
| community.ingest_quarantine | idx_community_ingest_quarantine_dedupe | 예 | [SQL 062](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/062_review_ingestion_governance.sql#L179) |
| community.local_signals | idx_local_signals_public_feed | 아니오 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L73) |
| community.local_signals | idx_local_signals_locality | 아니오 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L76) |
| community.local_signals | idx_local_signals_author | 아니오 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L78) |
| community.local_signal_places | idx_local_signal_places_place | 아니오 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L96) |
| community.local_signal_translations | idx_local_signal_translations_signal | 아니오 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L141) |
| community.local_signal_comments | idx_local_signal_comments_signal | 아니오 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L190) |
| community.local_signal_reports | idx_local_signal_reports_unresolved | 예 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L241) |
| community.local_signal_moderation_actions | idx_local_signal_moderation_target | 아니오 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L271) |
| community.local_signal_capabilities | idx_local_signal_capabilities_active | 예 | [SQL 063](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/063_local_signals_contract.sql#L286) |
| planning.user_saved_places | user_saved_places_owner_idx | 아니오 | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L34) |
| planning.slot_visits | slot_visits_owner_date_idx | 아니오 | [SQL 064](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/064_planning_action_tables.sql#L79) |
| profile.user_travel_preferences | user_travel_preferences_updated_idx | 아니오 | [SQL 065](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/065_user_travel_preferences.sql#L31) |
| planning.trip_preference_overrides | trip_preference_overrides_owner_date_idx | 아니오 | [SQL 066](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/066_trip_library_and_visit_feedback.sql#L28) |
| community.post_reports | idx_post_reports_unresolved | 예 | [SQL 067](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/067_community_post_reports.sql#L35) |
| community.chat_rooms | idx_chat_rooms_visibility | 아니오 | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L51) |
| community.chat_room_members | idx_chat_room_members_member | 아니오 | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L75) |
| community.idempotency_keys | idx_idempotency_keys_expiry | 아니오 | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L111) |
| community.chat_ws_tickets | idx_chat_ws_tickets_actor_expiry | 아니오 | [SQL 068](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/sql/canonical/068_community_chat_durable_controls.sql#L139) |

PK·UNIQUE 제약이 만드는 암묵적 인덱스는 위 51개 CREATE INDEX 수와 별도다.
