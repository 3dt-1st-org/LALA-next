# 02. 화면 계약

## S1. 온보딩

### 구조

```text
┌──────────────────────────────────────────┐
│ LALA                         [언어 선택] │
│ 1 / 3                                    │
│ 어떤 여행을 계획 중인가요?               │
│ [국내 여행                              ]│
│ [해외 방문                              ]│
│                                          │
│                           [다음]          │
└──────────────────────────────────────────┘

2 / 3: 언어 선택
3 / 3: 읽기 전용 Kakao preview + 현재 위치 사용
       + 지역 직접 선택 + 나중에 하기
```

### 계약

- 언어 selector는 첫 질문 전에 접근 가능하며 변경 즉시 현재 화면 전체가 한 언어로
  바뀐다.
- 여행 유형, 언어, 위치를 한 화면에 몰아넣지 않는다.
- 선택 전 `다음`은 disabled이며 선택 row를 누르는 즉시 다음 화면으로 자동 이동하지
  않는다.
- 위치 단계의 세 종료 action은 항상 보인다. 권한 요청이 실패해도 직접 선택과 나중에
  하기가 사라지지 않는다.
- 직접 선택은 시도 chip, 시군구 검색, 최근 선택, 결과 없음 상태를 제공한다.
- 완료 후 cold relaunch에서 온보딩을 건너뛰고 선택 언어·지역을 복원한다.

### 상태

`initial`, `selected`, `permission_prompt`, `temporary_denied`,
`permanent_denied`, `manual_select`, `manual_empty`, `persist_error`.

## S2. 검색

### 구조

```text
┌──────────────────────────────────────────┐
│ 장소·지역 검색                     [필터]│
│ 현재 지역  평택시 고덕동          [변경]│
│ [거리순 | 인기순]                        │
│ ──────────────────────────────────────── │
│ [image] 장소명       한 줄 추천 이유     │
│         카테고리 · 거리 · 출처/신선도    │
│ [image] ...                              │
│                                          │
│ 검색          지도          일정    신호  │
└──────────────────────────────────────────┘
```

### 계약

- 지역 행은 검색 field 바로 아래에 두고 전국 선택 sheet로 연결한다.
- 정렬은 segmented control 하나로 표현한다. 동시에 두 항목이 선택되어 보이면 안 된다.
- 서버가 거리·인기 정렬 계약을 지원하지 않으면 control을 disabled 또는 숨기고 향후
  기능을 동작하는 것처럼 보이지 않는다.
- pending은 결과 카드와 같은 치수의 skeleton 3개를 표시한다.
- empty와 network error를 분리한다. error에는 재시도, empty에는 검색어·지역 변경을
  제공한다.
- 선택 결과는 `SelectedPlaceStore`에 canonical ID로 기록한 뒤 지도 탭의 같은 pin과
  rail card를 강조한다.
- 결과 카드에는 실제 `reason`만 한 줄로 표시한다. `source`와 dataset `data_as_of`가
  없으면 source/freshness 영역을 숨긴다.

### 상태

`idle`, `typing`, `loading`, `loaded`, `empty`, `network_error`,
`region_unavailable`.

## S3. 지도

### 구조

```text
┌──────────────────────────────────────────┐
│ LALA                               [설정]│
│ [전체][명소][맛집][행사][문화]            │
│ [추천 카드][추천 카드][추천 카드] →       │
│                                          │
│          full-bleed Kakao Map            │
│       pin  pin  selected-pin             │
│                               [날씨]     │
│                               [현위치]   │
│ ───────── selected place dock ────────── │
│ 장소명 · 이유 · 출처 · 신선도      [저장]│
│ 검색          지도          일정    신호  │
└──────────────────────────────────────────┘
```

### 계약

- Kakao Map surface는 full-bleed이며 decorative card에 넣지 않는다.
- 393dp 폭에서 카테고리 5개와 설정 control의 접근 경로가 사라지지 않는다. 필요하면
  chip row만 수평 스크롤한다.
- pin-first 정책을 유지한다. cluster는 실제 pin 수와 zoom threshold를 만족할 때만
  사용하고 선택 pin은 숨기지 않는다.
- rail card, pin, dock는 같은 canonical ID를 사용하며 양방향 동기화한다.
- 지도 bounds 변경 요청은 stale response suppression을 적용한다. 늦게 도착한 이전
  bounds 응답이 최신 map state를 덮지 않는다.
- 네트워크 실패 시 bundled place나 임의 marker를 표시하지 않는다. 마지막 정상값이
  있으면 stale로 표시하고, 없으면 지도 surface 위에 재시도 action을 제공한다.
- dock와 floating controls, bottom navigation이 겹치지 않는다.

### 상태

`locating`, `loading_places`, `loaded`, `empty`, `stale`, `network_error`,
`location_denied`, `map_key_unavailable`.

## S4. 장소 상세·도슨트

### 구조

```text
mobile bottom sheet / wide web side panel
┌──────────────────────────────────────────┐
│ [actual place image or honest fallback] │
│ 장소명 · 카테고리                 [저장]│
│ 지역 · 거리                              │
│ 지금 갈 이유                             │
│  이유 요약                               │
│  [출처 · 신선도]                         │
│ 날씨·대기질 근거                         │
│ 도슨트                                   │
│  [텍스트] [음성 상태/재생]               │
│ [일정에 추가]                            │
└──────────────────────────────────────────┘
```

### 계약

- 저장 action은 header 한 곳에만 둔다. 별도 bookmark/favorite CTA를 중복하지 않는다.
- 장소 메타 출처, 이미지 권리/출처, 추천 근거 출처를 한 `Source:`로 합치지 않는다.
- `LalaPlace.reason`, dataset `dataAsOf`, `LalaWeather.recordTime`은 개념이 다르므로
  각각의 근거 block에 붙인다.
- 상세 점수·reason은 기본 접힘이며 사용자가 요청할 때만 펼친다. 내부 formula나 raw
  review는 노출하지 않는다.
- 도슨트 텍스트는 음성 가용성과 독립적으로 유지한다. 음성이 disabled/unavailable이면
  재생 버튼을 disabled 처리하고 이유를 표시한다.
- 이미지 URL이 없거나 검증 실패면 흐린 stock photo가 아니라 category fallback과
  `이미지 준비 중` 상태를 사용한다.
- 모바일은 draggable bottom sheet, 넓은 웹은 최대폭 side panel을 사용한다.

### 상태

`summary`, `reason_expanded`, `docent_loading`, `docent_loaded`,
`docent_error`, `audio_disabled`, `audio_loading`, `audio_playing`,
`save_auth_required`.

## S5. 4슬롯 일정·상황 회복

### 구조

```text
┌──────────────────────────────────────────┐
│ 오늘 일정                       [날짜]    │
│ 날씨·PM 요약 / 데이터 기준 시각          │
│ [상황 변화 banner: 원인·출처·시각]       │
│                                          │
│ 오전  장소 A · 운영시간(추정)             │
│       │ 예상 18분 · 도보/수단 미확인      │
│ 점심  장소 B                             │
│       │ 예상 22분                        │
│ 오후  장소 C                             │
│       │ 예상 15분                        │
│ 저녁  장소 D                             │
│                                          │
│ 검색          지도          일정    신호  │
└──────────────────────────────────────────┘
```

### 계약

- 오전·점심·오후·저녁 네 슬롯을 유지한다. API가 슬롯을 반환하지 못하면 장소를
  발명하지 않고 unavailable reason을 표시한다.
- `travel_time_from_previous_minutes`, `estimated_opening_hours`는 반드시
  `예상`/`Estimated` badge와 함께 표시한다.
- 상황 개입은 원인, 관측 시각, 출처를 보여 주고 원래 슬롯과 대체 슬롯을 한 화면에서
  비교한다.
- `기존 일정 유지`와 `대체 적용`을 동등한 action으로 제공한다. 적용 뒤 undo
  snackbar를 제공한다.
- 유효한 대체가 없으면 `alternative_slot`을 꾸며내지 않고 이유와 재시도/닫기를
  제공한다.
- bottom navigation이 마지막 슬롯이나 개입 CTA를 가리지 않도록 safe-area 하단
  padding을 확보한다.

### 상태

`loading`, `loaded`, `partial_slots`, `error`, `intervention_available`,
`comparison`, `applied`, `undo_available`, `no_alternative`.

## S6. Local Signals

### 구조

```text
┌──────────────────────────────────────────┐
│ 로컬 신호                                │
│ 선택 지역  평택시 고덕동           [변경]│
│ 광고·협찬·중복을 제외한 집계              │
│ 집계 기준 2026-08-xx                     │
│ ──────────────────────────────────────── │
│ 장소명 · 카테고리                        │
│ 최근 언급 12 · 자연 언급 9               │
│ 품질/감성은 표본과 값이 있을 때만         │
│ [장소 보기] [일정 추가]                  │
│ ...                                      │
│ 검색          지도          일정    신호  │
└──────────────────────────────────────────┘
```

### 계약

- system aggregate와 user post를 한 feed item으로 섞지 않는다.
- aggregate 카드에는 raw text, author, external key, URL, 정밀 좌표를 담지 않는다.
- `available=false` 또는 items가 비어 있으면 `집계 준비 중` empty state를 표시한다.
  예시 행을 채우지 않는다.
- mention count와 organic count는 실제 값만 표시한다. 감성·품질 score는 값과 표본
  의미가 명확할 때만 보조 정보로 표시한다.
- aggregate freshness는 `lastRefreshedAt ?? computedAt`을 사용한다.
- `장소 보기`는 canonical ID가 있을 때만 활성화하고 지도 선택 상태로 이동한다.
- `일정 추가`는 plan context에 후보를 전달하며, 즉시 일정이 변경됐다고 가장하지
  않는다.
- 광고·협찬·중복 필터 적용 사실을 짧게 고지하되 내부 임계값과 원문은 노출하지 않는다.

### 상태

`loading`, `loaded`, `empty`, `disabled`, `stale`, `error`,
`place_unresolved`.
