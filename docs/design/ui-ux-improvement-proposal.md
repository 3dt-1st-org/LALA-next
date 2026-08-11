# UI/UX 개선안 제안

> **목적**: 외국인 여행자(한국의 진짜 로컬 스팟을 찾는 사용자) 대상 UI/UX 개선 방향 제안
> **범위**: 제안 문서입니다. 코드 변경은 포함되어 있지 않습니다.
> **작성 기준일**: 2026-08-11
> **검증 대상**: `https://lala-next.cloud` (프로덕션 웹), `https://api.lala-next.cloud` (라이브 API)

관련 산출물:

- 시각 목업: [`ui-ux-mockup.html`](./ui-ux-mockup.html) — 브라우저로 직접 열어보세요. 5개 화면(지도 / 도슨트 플레이어 / 장소 상세 / Discover / 하루 일정) 목업과 팔레트·타이포·컴포넌트 정의가 들어 있습니다.

---

## 0. 핵심 요약

1. **주 기능인 자동 생성 도슨트가 UI에서 2단계 안쪽에 묻혀 있습니다.** 장소 상세 시트를 열고 스크롤해야 나옵니다. 도슨트를 최상위 표면으로 올리는 것이 이 제안의 1번 목표입니다.
2. **영어 모드가 절반만 동작합니다.** 지도 탭만 번역되고 Discover/Plan 탭과 하단 탭바는 영어 모드에서도 한글로 남습니다. 대상 사용자가 외국인 여행자인데 앱을 읽을 수 없는 상태입니다.
3. **API가 이미 주고 있는데 클라이언트가 안 쓰는 데이터가 있습니다.** 이동 시간, 슬롯 제목, 영문 장소명 등. 서버 작업 없이 클라이언트만 고치면 되는 항목들입니다.
4. **점수 기반 UI는 데이터 복구가 선행되어야 합니다.** 현재 32곳 중 1곳만 점수가 존재합니다.

---

## 1. 이미 있음 — 바로 붙일 수 있는 것

| 항목 | 실제 상태 | 근거 |
|---|---|---|
| 카테고리 색상 4종 | **이미 구현되어 있음** | `apps/flutter_app/lib/main.dart:7718` |
| 한글+영문 이름 병기 | `name_ko` / `name_en` 32/32 전부 내려옴 | 라이브 API `/api/v1/places` |
| 장소 이미지 | `image_url` 31/32 | 라이브 API |
| 영어 도슨트 생성 | **실제 동작 확인됨**, OpenAI 라이브 | `POST /api/v1/docents/script` → 200 |
| 날씨 반영 문구 | 이미 스크립트 본문에 포함됨 | 응답: *"Current weather is 25.2°C…"* |
| 생성 시각 / 출처 | `generated_at`, `citations`, `grounding_sources` | 라이브 API |
| 이동 시간 | **API가 이미 내려줌** (1분·5분·7분) | `POST /api/v1/plans/daily` |

### 1-1. 카테고리 색상은 앱의 기존 값을 그대로 사용

목업 초안에서 단색으로 통일했던 것은 **후퇴**였습니다. 앱에 이미 정의된 값을 유지합니다.

| 카테고리 | HEX | 한글 |
|---|---|---|
| `attraction` | `#C53030` | 명소 |
| `restaurant` | `#F5C842` | 맛집 |
| `event` | `#2B6CB0` | 행사 |
| `culture_venue` | `#0F766E` | 문화 |

정의 위치: `apps/flutter_app/lib/main.dart:7718` `_categoryColor()`

### 1-2. `"lu"` / `"di"` 라벨 버그 — 원인 확정

`apps/flutter_app/lib/main.dart:9218` `_periodLabel()` 이 `morning` / `afternoon` / `evening` 만 처리합니다.
그런데 API가 실제로 보내는 값은 `morning` / **`lunch`** / `afternoon` / **`dinner`** 이고, `evening`은 아예 오지 않습니다.

매칭에 실패하면 default 분기로 떨어져 잘립니다.

```dart
// 한국어: period.substring(0, 2)  → "lunch" → "lu",  "dinner" → "di"
// 영어  : period.substring(0, 3)  → "lunch" → "lun", "dinner" → "din"
```

**API는 이미 `title: "Lunch"`, `"Dinner"` 를 정상적으로 내려주고 있고**, Dart 클라이언트도 `clients/flutter/lib/lala_api_client.dart:1044` 에서 `title` 을 파싱까지 해둔 상태입니다.
→ `_periodLabel()` 대신 `slot.title` 을 사용하면 해결됩니다.

---

## 2. 만들어져 있지만 막혀 있는 것

| 항목 | 상태 | 막힌 지점 |
|---|---|---|
| 도슨트 오디오(TTS) | 엔드포인트·스키마·Dart 클라이언트 **모두 존재** | `503 SPEECH_NOT_CONFIGURED` — Azure Speech 키 3개 미설정 + **Flutter에 오디오 재생 라이브러리 없음** |
| 장소 점수 | 스키마·API 파라미터 존재 | `include_scores=true` 로 요청해도 **32곳 중 1곳만** 점수 있음 (배치 미가동) |
| 카드소비 데이터 | 존재 | `card_month: 2026-03-01` — 5개월 전 데이터 |

> **주의**: 도슨트 오디오는 "설정만 켜면 되는" 수준이 아닙니다.
> Azure Speech 프로비저닝(`AZURE_SPEECH_KEY` / `REGION` / `ENDPOINT`)에 더해,
> `apps/flutter_app/pubspec.yaml` 에 오디오 재생 패키지(`just_audio` 등)가 아직 없어 **클라이언트 작업이 별도로 필요**합니다.

---

## 3. 데이터가 뒷받침되지 않아 제안에서 제외/수정한 것

### 3-1. "82% 현지인 소비" 표기는 사용하면 안 됨

실제 `local_spending_score` 값은 `0.4144` 형태의 **0~1 정규화 점수**입니다.
산출 근거를 보면 `region_spend_amount`, `region_place_count` 등 **지역 단위** 카드소비 집계에서 나온 값입니다.

- 근거 테이블: `analytics.place_score_snapshots` (`sql/canonical/035_data_pipeline_tables.sql:159`)
- 입력 소스: `economy.card_spending_area_monthly` 외

즉 **"이 가게 손님의 82%가 내국인"이라는 의미가 아닙니다.** 그대로 퍼센트로 표기하면 사실과 다른 표시가 됩니다.

→ **"이 지역 소비 패턴 기준 로컬 지수"** 수준으로 문구를 바꾸고, 퍼센트가 아닌 **지수/등급**으로 표현할 것을 권장합니다.

### 3-2. "여기 들어가도 되나요?" 칩 — 근거 데이터 없음

- `review_quality_score: null`
- `missing_signals: ["place_business_identity", "review_attribute_analysis"]`
- `review_signal` 전 필드 null

리뷰 속성 분석이 동작하지 않아 현재 데이터로는 만들 수 없습니다. 아이디어로만 보존하고, 리뷰 파이프라인 복구 이후로 미룹니다.

### 3-3. 자동 챕터 — 응답에 없음

`/docents/script` 응답에 챕터 구조가 없습니다. 신규 개발 항목입니다.

---

## 4. 영어 모드 — 정량화

`apps/flutter_app/lib/main.dart` 기준:

| 구분 | 개수 |
|---|---|
| 한글 문자열 리터럴 총계 | 281 |
| `_copy(ko:, en:)` 로 감싼 것 | 150 |
| **하드코딩(미번역) 추정** | **131** |

이것이 Discover / Plan 탭이 영어 모드에서 한글로 남는 직접적인 원인입니다.
구조 변경이 아니라 **문자열 래핑 작업**입니다.

추가로 확인된 영어 모드 문제:

- 하단 탭바(`검색` / `지도` / `플랜`)가 영어 모드에서 번역되지 않음 — 항상 화면에 떠 있는 유일한 컨트롤
- 언어 전환 UI가 English를 **`영어`** 로 표기 — 한글을 못 읽는 사용자는 전환 경로를 찾을 수 없음
- 카카오 지도 타일 라벨이 전부 한글 (`화서역블루밍푸른숲아파트` 등) — 주 표면이 판독 불가

---

## 5. 제안하는 UI/UX 방향

목업: [`ui-ux-mockup.html`](./ui-ux-mockup.html)

### 5-1. 도슨트를 최상위로 (핵심)

| 현재 | 제안 |
|---|---|
| 장소 상세 시트 5번째 패널, 스크롤 필요 | 카드/행마다 재생 컨트롤, **전용 전체 화면 플레이어** |
| 재생 후 화면 이탈하면 끊김 | 탭바 위 **미니 플레이어**가 3개 탭 전체에 상주 |
| 텍스트 블록 | 재생 시간 표기(`2:14`) — 탭 전 소요 시간을 알 수 있어 재생률 상승 |

자동 생성이라는 사실 자체를 UI에 노출:

- `generated_at` 기반 생성 시각 배지
  (단, `ttl_sec: 604800` = **7일 캐시**이므로 "방금 생성" 문구는 부정확합니다. "오늘 기준" 정도로 표현 권장)
- 날씨 맥락 노출 — 스크립트에 이미 반영되어 있으므로 그대로 표면화
- `citations` / `grounding_sources` 기반 출처 표기

### 5-2. 하루 일정 = 재생목록

- `travel_time_from_previous_minutes` 를 파싱해 정거장 사이에 이동 시간 표시 (**API는 이미 제공 중**)
- 하루 전체 연속 재생

### 5-3. 그 외

- 영문명 + 한글명 병기 (`name_ko` 활용) — 번역이 아니라 **택시 기사·간판 대조용 도구**
- 카테고리 색상은 기존 앱 값 유지
- 점수는 주인공이 아니라 **근거**로 배치

---

## 6. 권장 진행 순서

### 1순위 — 클라이언트 수정만으로 가능 (서버 작업 불필요)

- [ ] `slot.title` 사용해 `"lu"` / `"di"` 라벨 버그 수정
- [ ] `travel_time_from_previous_minutes` 파싱 추가 → 이동 시간 표시
- [ ] 하드코딩 한글 리터럴 131개 `_copy()` 래핑
- [ ] 하단 탭바 / 언어 전환 라벨 번역
- [ ] `name_ko` 병기 + "기사님께 보여주기" 카드

### 2순위 — 데이터 복구 선행 필요

- [ ] 장소 점수 배치 재가동 (1/32 → 정상화)
      **이것이 되기 전에는 점수 UI를 넣어도 97%가 빈칸입니다**
- [ ] 카드소비 데이터 갱신 (현재 5개월 경과)
- [ ] 장소 대표 이미지 품질 게이트
      (현재 수원화성박물관 대표 이미지가 화장실 사진)

### 3순위 — 도슨트 강화 (주 기능)

- [ ] Azure Speech 프로비저닝
- [ ] Flutter 오디오 재생 라이브러리 도입
- [ ] 전체 화면 플레이어 / 미니 플레이어 구현
- [ ] 지도 타일 영문화 (영어 로케일)

---

## 7. 검증 방법

이 문서의 API 관련 주장은 아래로 재현할 수 있습니다.

```bash
curl -s -H "Origin: https://lala-next.cloud" \
  'https://api.lala-next.cloud/api/v1/places?lat=37.2636&lng=127.0286&radius_m=3000&limit=60&include_scores=true&lang=en'
```

```bash
curl -s -H "Origin: https://lala-next.cloud" -H "Content-Type: application/json" \
  -X POST 'https://api.lala-next.cloud/api/v1/plans/daily' \
  -d '{"lat":37.2636,"lng":127.0286,"radius_m":3000,"language":"en"}'
```
