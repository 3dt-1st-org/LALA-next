# LALA-next Data Dictionary

Status: draft source of truth for the next schema refactor  
Last updated: 2026-06-15

이 문서는 LALA-next의 데이터베이스 스키마, 테이블, 주요 컬럼 이름을 정리한다.
기준은 "서비스가 무엇을 하는지"가 이름에서 바로 보이는 것이다. 특정 지역, 특정
공급자, 과거 프로젝트명은 테이블명에 넣지 않고 컬럼이나 `source_name` 값으로
남긴다.

## Naming Principles

| Rule | Decision |
|---|---|
| 지역명은 테이블명에 넣지 않는다 | `gyeonggi_events` 대신 `culture.events`, `card_spending_area_monthly`를 사용하고 `province_code`, `region_name_ko`로 지역을 표현한다. |
| 공급자명은 테이블명에 넣지 않는다 | `daangn.community_posts` 대신 `community.posts`를 사용하고 `provider` 값으로 `daangn`, `naver`, `public_portal` 등을 구분한다. |
| 브랜드/옛 프로젝트명은 스키마명에 넣지 않는다 | `locallink` 대신 실제 도메인인 `travel`, `culture`, `economy`, `community`를 사용한다. |
| 운영 데이터는 서비스 데이터와 분리한다 | `monitoring` 대신 짧고 명확한 `ops` 스키마를 사용한다. |
| 마이그레이션 호환 뷰는 별도 스키마에 둔다 | `v_legacy_*` 뷰는 `compat.*`에 모아 앱 코드와 과거 API 호환을 분리한다. |
| 공개 API용 식별자는 안정적으로 유지한다 | 내부 `id uuid`와 별개로 `place_id`, `event_id`, `source_record_id`를 둔다. |
| AI 생성값은 출처와 버전을 같이 저장한다 | 영문명, 실내/실외 분류, 속성 점수 등은 `model`, `prompt_version`, `confidence`, `generated_at`을 남긴다. |

## Schema Overview

| Schema | Purpose | MVP |
|---|---|---|
| `travel` | 앱이 직접 추천/조회하는 장소, 날씨, 도슨트 캐시 | Yes |
| `culture` | 문체부 계열 API와 공공 문화행사/공연/관광 콘텐츠의 정규화 데이터 | Yes |
| `economy` | 카드 소비/매출, 지역 수요, 관광 분산 계산용 경제 데이터 | Yes |
| `community` | 공급자 중립의 지역 커뮤니티 언급/후기/키워드 신호 | Later |
| `ingest` | 원천 파일/API 적재 이력, 원본 레코드 추적, 배치 실행 메타데이터 | Yes |
| `analytics` | 추천 점수, 공공가치 지표, 실험/스냅샷 결과 | Yes |
| `ops` | 잡 실행, 의존성 점검, 비용 등 운영 관측 데이터 | Yes |
| `compat` | 기존 라라/Flutter/API 호환용 읽기 전용 뷰 | Migration only |

## Current Rename Map

| Current name | Target name | Reason |
|---|---|---|
| `locallink` | `travel` | 브랜드/구현명이 아니라 앱 도메인 중심 이름 |
| `locallink.places` | `travel.places` | 추천/지도/도슨트의 핵심 장소 테이블 |
| `locallink.realtime_weather_conditions` | `travel.weather_observations` | 실시간 여부보다 관측 데이터라는 의미가 명확함 |
| `locallink.docent_cache` | `travel.docent_scripts` | 캐시 구현보다 도메인 산출물 이름 |
| `locallink.place_events` | `travel.place_events` | 장소에 연결된 일정/행사 |
| `locallink.v_public_places` | `travel.public_places` | API 읽기용 공개 장소 뷰 |
| `locallink.v_latest_weather_api` | `travel.latest_weather` | 최신 날씨 읽기용 뷰 |
| `locallink.v_legacy_places_api` | `compat.legacy_places_api` | 호환 계층을 도메인 스키마에서 분리 |
| `locallink.v_legacy_docent_script_cache_api` | `compat.legacy_docent_scripts_api` | 과거 API 호환 이름만 남김 |
| `daangn` | `community` | 특정 공급자 종속 제거 |
| `daangn.weekly_keywords` | `community.keyword_watchlist` | 수집 키워드 관리 의미가 명확함 |
| `daangn.crawl_runs` | `community.ingest_runs` | 크롤링 구현보다 적재 실행 의미 |
| `daangn.crawl_tasks` | `community.ingest_tasks` | 공급자/방법이 바뀌어도 유지 가능 |
| `daangn.community_posts` | `community.posts` | 공급자 중립 커뮤니티 게시글 |
| `daangn.place_mentions_weekly` | `community.place_mentions_weekly` | 주간 장소 언급 집계 |
| `monitoring` | `ops` | 짧고 운영 스키마임이 분명함 |
| `monitoring.function_runs` | `ops.job_runs` | Azure Function 여부와 무관한 잡 실행 |
| `monitoring.dependency_checks` | `ops.dependency_checks` | 외부 의존성 상태 |
| `monitoring.cost_daily` | `ops.daily_costs` | 일별 비용 집계 |

## `travel.places`

앱이 노출하는 장소의 표준 테이블이다. 관광지, 식당, 문화장소, 행사 대표 지점이
여기에 들어온다. 경기도 데이터로 시작하더라도 테이블명에 `gyeonggi`를 넣지 않는다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `place_id` | text | Yes | API/클라이언트에서 쓰는 안정 식별자 |
| `name_ko` | text | Yes | 한국어 장소명 |
| `name_en` | text | No | API/공공 번역/AI 전처리로 만든 영문 장소명 |
| `category` | text | Yes | `attraction`, `restaurant`, `event`, `culture_venue` 중 하나 |
| `address_ko` | text | No | 한국어 주소 |
| `address_en` | text | No | 영문 주소 또는 로마자 주소 |
| `region_name_ko` | text | No | 시군구/생활권 표시명 |
| `region_name_en` | text | No | 영문 지역 표시명 |
| `province_code` | text | No | 행정구역 코드 또는 광역 지자체 코드 |
| `city_code` | text | No | 시군구 코드 |
| `lat` | double precision | Yes | 위도 |
| `lng` | double precision | Yes | 경도 |
| `is_indoor` | boolean | No | 날씨 필터용 실내 여부. 판단 불가면 null |
| `primary_source` | text | Yes | 대표 원천. 예: `tour_api`, `kcisa`, `kopis`, `data_portal`, `manual_seed` |
| `source_record_id` | text | No | 원천 시스템의 레코드 ID |
| `updated_at` | timestamptz | Yes | 마지막 갱신 시각 |

Notes:

- `region_name_*`를 쓰고 `region_*` 약칭은 피한다. 지역 단위가 시군구인지
  읍면동인지 문맥 없이 흐려지기 때문이다.
- `category`는 MVP에서는 기존 API 호환 때문에 `attraction`, `restaurant`,
  `event`를 우선 유지하고, 문화시설은 필요 시 `culture_venue`를 추가한다.
- `is_indoor`는 추천 계산식에서 악천후 후보 필터에 사용한다. 실시간 API 요청 중
  계산하지 않고 전처리 배치에서 채운다.

## `travel.place_enrichments`

AI/API/로컬 변환으로 만든 보강 결과를 저장한다. `travel.places`에는 현재 선택된
값을 넣고, 이 테이블에는 생성 근거와 버전을 남긴다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `place_id` | text | Yes | `travel.places.place_id` |
| `enrichment_type` | text | Yes | `place_profile`, `english_text`, `indoor_classification`, `review_attributes`, `sentiment` |
| `name_en` | text | No | 보강된 영문명 |
| `address_en` | text | No | 보강된 영문 주소 |
| `region_name_en` | text | No | 보강된 영문 지역명 |
| `is_indoor` | boolean | No | AI/룰 기반 실내 분류 |
| `attributes` | jsonb | No | 맛, 서비스, 분위기, 혼잡도 등 속성 점수 |
| `confidence` | numeric | No | 0-1 신뢰도 |
| `source_method` | text | Yes | `azure_openai`, `k_term_api`, `juso_api`, `local_romanization`, `manual` |
| `model_name` | text | No | AI 모델 또는 API 버전 |
| `prompt_version` | text | No | 프롬프트 버전 |
| `generated_at` | timestamptz | Yes | 생성 시각 |

## `travel.weather_observations`

날씨/대기질 관측값이다. 앱 추천에서 실내/실외 필터, 악천후 회피, 날씨 기반
도슨트 문구에 사용한다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `location_name` | text | Yes | 관측 지역명 |
| `temperature_c` | double precision | No | 섭씨 온도 |
| `precipitation_type` | text | No | 비/눈/없음 등 |
| `pm10` | double precision | No | 미세먼지 |
| `pm25` | double precision | No | 초미세먼지 |
| `is_rain_snow` | boolean | Yes | 비/눈 여부 |
| `is_bad_dust` | boolean | Yes | 대기질 나쁨 여부 |
| `is_heatwave` | boolean | Yes | 폭염 여부 |
| `is_coldwave` | boolean | Yes | 한파 여부 |
| `is_strong_wind` | boolean | Yes | 강풍 여부 |
| `observed_at` | timestamptz | Yes | 관측 시각 |
| `collected_at` | timestamptz | Yes | 수집 시각 |

## `travel.docent_scripts`

장소별 AI 도슨트 대본 캐시다. 캐시라는 구현명보다 실제 산출물인 script를 기준으로
이름을 정한다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `place_id` | text | Yes | 대상 장소 |
| `category` | text | Yes | 장소 카테고리 |
| `language` | text | Yes | `ko`, `en` |
| `mode` | text | Yes | `summary`, `walking`, `audio` 등 |
| `script` | text | Yes | 생성된 대본 |
| `source_method` | text | Yes | `azure_openai`, `fallback`, `manual` |
| `generated_at` | timestamptz | Yes | 생성 시각 |
| `expires_at` | timestamptz | No | 재생성 기준 시각 |

## `culture.events`

문체부 계열 API, TourAPI, KOPIS, KCISA, 공공데이터포털 문화 데이터에서 들어오는
공연/전시/축제/행사 정규화 테이블이다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `event_id` | text | Yes | API/클라이언트용 안정 식별자 |
| `title_ko` | text | Yes | 한국어 제목 |
| `title_en` | text | No | AI/API 전처리 영문 제목 |
| `event_type` | text | No | 공연, 전시, 축제, 체험 등 |
| `venue_name_ko` | text | No | 장소명 |
| `venue_place_id` | text | No | `travel.places.place_id` 연결 |
| `region_name_ko` | text | No | 지역명 |
| `starts_on` | date | No | 시작일 |
| `ends_on` | date | No | 종료일 |
| `url` | text | No | 상세 URL |
| `primary_source` | text | Yes | `kopis`, `kcisa`, `tour_api`, `data_portal` 등 |
| `source_record_id` | text | No | 원천 레코드 ID |
| `updated_at` | timestamptz | Yes | 마지막 갱신 시각 |

## `economy.card_spending_area_monthly`

내국인 소비 기반의 로컬 경험 추천과 지역경제 활성화 점수에 쓰는 월별/지역별 카드
소비 집계다. 데이터 출처가 경기도여도 테이블명에는 지역명을 넣지 않는다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `month` | date | Yes | 월 시작일 |
| `region_name_ko` | text | Yes | 시군구 또는 상권 지역명 |
| `industry_code` | text | No | 업종 코드 |
| `industry_name_ko` | text | No | 업종명 |
| `spend_amount` | numeric | No | 결제 금액 |
| `transaction_count` | integer | No | 결제 건수 |
| `visitor_type` | text | No | 내국인/외국인/전체 등 원천 기준 |
| `primary_source` | text | Yes | 예: `gyeonggi_data_dream`, `data_portal` |
| `source_file_id` | uuid | No | `ingest.source_files.id` |

## `economy.card_spending_demographics`

성별/연령대별 카드 소비 집계다. 맛집/장소 추천의 과밀 회피, 생활권별 선호,
관광 수요 분산 계산에 사용한다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `month` | date | Yes | 월 시작일 |
| `region_name_ko` | text | Yes | 지역명 |
| `industry_code` | text | No | 업종 코드 |
| `gender` | text | No | 원천 기준 성별 |
| `age_group` | text | No | 연령대 |
| `spend_amount` | numeric | No | 결제 금액 |
| `transaction_count` | integer | No | 결제 건수 |
| `primary_source` | text | Yes | 원천명 |
| `source_file_id` | uuid | No | 원천 파일 |

## `community.posts`

지역 커뮤니티, 후기, 검색 결과 등 비공식 로컬 신호를 공급자 중립으로 저장한다.
크롤러 여부나 특정 플랫폼명은 테이블명에 넣지 않는다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `provider` | text | Yes | `daangn`, `naver_blog`, `naver_local`, `manual` 등 |
| `external_key` | text | Yes | 공급자 레코드 ID 또는 URL hash |
| `keyword` | text | No | 수집 키워드 |
| `region_slug` | text | No | 수집 지역 |
| `title` | text | No | 제목 |
| `body` | text | No | 본문/요약 |
| `post_url` | text | No | URL |
| `created_at_source` | timestamptz | No | 원천 게시 시각 |
| `collected_at` | timestamptz | Yes | 수집 시각 |

## `community.place_mentions_weekly`

장소별 주간 언급량과 리뷰 신호를 저장한다. 광고 필터링, 감성 분석, 맛/서비스/분위기
속성 점수는 `attributes`에 남긴다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `week_start` | date | Yes | ISO week 시작일 |
| `place_id` | text | No | 매칭된 `travel.places.place_id` |
| `place_name_ko` | text | Yes | 매칭 전/후 장소명 |
| `provider` | text | Yes | 원천 공급자 |
| `mention_count` | integer | Yes | 전체 언급 수 |
| `organic_mention_count` | integer | No | 광고/홍보 필터 후 언급 수 |
| `sentiment_score` | numeric | No | -1 to 1 |
| `attributes` | jsonb | No | `taste`, `service`, `price`, `atmosphere` 등 |
| `updated_at` | timestamptz | Yes | 갱신 시각 |

## `ingest.source_files`

CSV/XLSX/ZIP 원본 파일의 출처와 해시를 기록한다. 원본 파일 자체는 Git에 넣지 않고
`artifacts/tmp/raw`나 별도 스토리지에 둔다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `source_name` | text | Yes | `data_portal`, `gyeonggi_data_dream`, `tour_api` 등 |
| `dataset_name` | text | Yes | 원천 데이터셋명 |
| `file_name` | text | Yes | 다운로드 파일명 |
| `file_sha256` | text | No | 파일 해시 |
| `downloaded_at` | timestamptz | Yes | 다운로드 시각 |
| `local_path` | text | No | 로컬 개발 경로. 운영에서는 스토리지 URI 사용 |

## `analytics.place_score_snapshots`

추천 계산식과 공공가치 지표의 결과 스냅샷이다. "왜 추천됐는지"를 설명하고 공모전
평가에서 지역경제 활성화와 관광 수요 분산 근거를 보여주는 테이블이다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `place_id` | text | Yes | 대상 장소 |
| `scored_at` | timestamptz | Yes | 점수 계산 시각 |
| `local_spending_score` | numeric | No | 실제 내국인 소비 기반 점수 |
| `demand_dispersion_score` | numeric | No | 과밀 지역 회피/분산 점수 |
| `weather_fit_score` | numeric | No | 현재 날씨 적합도 |
| `review_quality_score` | numeric | No | 광고 필터 후 리뷰/속성 품질 점수 |
| `culture_relevance_score` | numeric | No | 문체부/문화 데이터 연계 점수 |
| `final_score` | numeric | Yes | 최종 추천 점수 |
| `formula_version` | text | Yes | 계산식 버전 |
| `features` | jsonb | No | 점수 산출 입력 피처 |

### `local-value-v1` Score Contract

MVP API는 장소 응답의 `score` 필드로 최신 추천 점수를 노출한다. DB-backed 모드에서는
`analytics.place_score_snapshots`의 최신 행을 그대로 사용하고, public demo 모드에서는
`data_basis=demo_fallback`으로 표시한 카테고리/거리 기반 prior만 사용한다. 데모 fallback은
실제 카드 소비 데이터라고 표시하지 않는다.

현재 계산식 가중치:

| Component | Weight | Public-value meaning |
|---|---:|---|
| `local_spending_score` | 0.30 | 내국인 카드 소비/매출 기반 지역경제 활성화 신호 |
| `demand_dispersion_score` | 0.25 | 과밀 지역 회피와 관광 수요 분산 신호 |
| `weather_fit_score` | 0.15 | 날씨/실내외 적합도 |
| `review_quality_score` | 0.15 | 광고 필터 후 리뷰 감성/속성 품질 |
| `culture_relevance_score` | 0.15 | 문체부/TourAPI/KOPIS/KCISA 문화 데이터 연계성 |

결측 component는 0점으로 취급하지 않고, 존재하는 component의 가중치 합으로 재정규화한다.
따라서 리뷰 분석이 아직 없는 장소도 카드 소비/수요 분산/문화 연계 점수만으로 설명 가능한
초기 추천 점수를 만들 수 있다.

## `ops.job_runs`

수집/전처리/스코어링 잡 실행 이력이다.

| Column | Type | Required | Description |
|---|---:|---:|---|
| `id` | uuid | Yes | 내부 PK |
| `job_name` | text | Yes | 잡 이름 |
| `status` | text | Yes | `started`, `succeeded`, `failed`, `skipped` |
| `started_at` | timestamptz | Yes | 시작 시각 |
| `finished_at` | timestamptz | No | 종료 시각 |
| `duration_ms` | integer | No | 실행 시간 |
| `error_message` | text | No | secret-safe 오류 메시지 |

## Source Names

`primary_source`, `source_name`, `provider` 값은 다음처럼 관리한다.

| Source name | Meaning |
|---|---|
| `tour_api` | 한국관광공사 TourAPI |
| `kcisa` | 한국문화정보원 문화정보 API |
| `kopis` | 공연예술통합전산망 |
| `data_portal` | 공공데이터포털 파일/API |
| `gyeonggi_data_dream` | 경기데이터드림 |
| `naver_search` | 네이버 검색 API |
| `naver_local` | 네이버 지역/플레이스 계열 데이터 |
| `kakao_local` | 카카오 로컬 API |
| `juso_api` | 주소기반산업지원서비스 영문주소 API |
| `k_term_api` | 국립국어원 온용어 API |
| `azure_openai` | Azure OpenAI 전처리/생성 |
| `manual_seed` | 개발/시연용 수동 seed |

## AI Enrichment Flow

전처리 단계는 API 요청 중 실행하지 않는다. 비용, 지연, 재현성 때문에 배치로만
실행한다.

1. 원천 파일/API를 `ingest.source_files`와 staging 테이블에 기록한다.
2. 정규화된 장소/행사/소비 데이터를 `travel`, `culture`, `economy`에 적재한다.
3. 영문명/영문주소/실내 여부/리뷰 속성 점수를 `travel.place_enrichments`에 저장한다.
4. 현재 앱에서 바로 쓸 선택값만 `travel.places`에 반영한다.
5. 추천 계산식은 `analytics.place_score_snapshots`에 버전별로 남긴다.

MVP에서 우선 구현할 보강 항목:

- `name_en`, `address_en`, `region_name_en`
- `is_indoor`
- 리뷰 광고 필터 후 `taste`, `service`, `price`, `atmosphere` 속성 점수
- `local_spending_score`, `demand_dispersion_score`, `culture_relevance_score`

## Open Questions

- `event`를 `travel.places.category` 안에 둘지, `culture.events` 중심으로만 둘지
  API 화면 요구에 맞춰 한 번 더 결정해야 한다.
- 음식점은 공공/카드/지도 API 기반으로 충분한지, 민간 리뷰 신호를 어디까지
  공급자 약관에 맞춰 쓸지 별도 검토가 필요하다.
- `province_code`, `city_code`는 행정안전부 법정동/행정동 코드 기준 중 어느 것을
  우선할지 정해야 한다.
