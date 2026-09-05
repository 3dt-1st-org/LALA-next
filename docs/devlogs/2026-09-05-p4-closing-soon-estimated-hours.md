# P4 추정 운영시간 기반 closing-soon/마감 개입 — 2026-09-05

## 배경

개입(intervention)의 마감 계열 사유는 카테고리 기반 **추정** 운영시간 투영에서만
유도된다. 그러나 기존 UI 라벨(`폐업 의심`/`Possible closure`)과 증거 문구
("~영업 종료 가능성이 관측됐어요")는 추정치를 폐업·관측된 마감처럼 표현했다.
또한 마감 "임박" 개입은 존재하지 않았다. 이 체크포인트는 (1) 결정론적 bounded
window 에서 유도된 별도 `closing_soon` 개입 추가, (2) 추정 마감 계열 사유/행동
문구의 정직화(estimated + 확인 필요), 두 가지를 닫는다. #191 의 날씨/대기질 사유
분리는 그대로 보존했다.

## 커밋

1. `96809479` — API: 창 상수/순수 헬퍼 + 슬롯 투영 + 트리거/사유/행동 + openapi.
2. `05b14cc9` — Flutter: 5-로케일 문구 정직화 + S-20/S-21 마감 임박 배지 + 경성
   320dp/200% 위젯 테스트.
3. `48583333` — 이 devlog.
4. (정정 커밋) — 독립 검증 CORRECTION_REQUIRED 반영: 공유 strict 파서 + 공유
   멤버십 정의(아래 "검증자 정정" 절).

## 확정 동작

### API

- `opening_hours_service.CLOSING_SOON_WINDOW_MINUTES = 60`(명명된 결정론적 상수).
  `is_closing_soon(slot_time, open_time, close_time, window=60)`: 운영시간 내이면서
  추정 마감까지 남은 분이 window 이하 → True. 경계: close-60 정각 포함, 마감 시각
  정각(남은 분 0)도 True(`is_within_hours` 가 마감 시각을 포함하므로 closed 와
  상호 배제 유지), 마감 후/영업 전 → False. 값 누락/파싱 불가, open==close(마감
  미정의), window ≤ 0 → None(추측 금지). 자정 넘김 범위(close < open)는 당일
  오픈 이후/익일 마감 이전을 운영중로 본다.
- 슬롯 투영: `PLAN_FULL_SLOTS` on 일 때만 `closing_soon: bool|null` 추가 키
  (closure_state 형제). closing_soon=true 는 운영시간 내에서만 나오므로
  `closure_state="closed"` 와 구조적으로 상호 배제(전 기간×전 카테고리 스윕 테스트).
- 트리거: `closing_soon`(단독) 및 조합
  `bad_weather_and_closing_soon` / `bad_air_quality_and_closing_soon` /
  `bad_weather_and_air_quality_and_closing_soon` 추가. factor
  `slot_closing_soon: within_estimated_window`. closure 와 closing-soon 이 동시
  참이 되는 퇴화 입력에서는 closure 가 결정론적으로 우선(런타임 불가 조합).
- 사유/행동: 추정 운영시간 사유가 유일한 원인이면 그 원인만 명시("추정
  운영시간(...) 밖/마감에 가까워요. 실제 영업 여부는 확인이 필요해요.")하고
  날씨/대기질을 언급하지 않는다. 조합은 모든 실제 원인을 명시. 폐업·영구/임시/
  휴일 마감·관측 어휘 금지(테스트로 봉쇄).
- 대안: 추정 운영시간 원인(단독/조합)에서는 이미 가져온 실제 candidate 중 이번
  슬롯을 추정 운영시간이 커버하면서 closing-soon window 밖인 첫 장소(조합 시
  실내 조건 추가)를 제안하고, 없으면 정직한 null. fixture/demo 장소 삽입 없음.
- 호환: 플래그 off → 슬롯 키·트리거·사유/행동이 pre-V3 바이트 호환(키 집합
  회귀 테스트). no-context(선호 컨텍스트 없는 일일 플랜) 경로 무변경.

### Flutter

- 배지/토스트 폴백/S-21 제목·증거·칩/타일 배지가 모두 "예상 운영시간 외 /
  Outside est. hours", "마감 임박(예상) / Closing soon (est.)" 계열로 교체(5개
  로케일 단일 언어). `폐업 의심`/`Possible closure`/`may be closed`/관측 표현은
  이 경로에서 제거(금지 어휘 스윕 테스트).
- S-20 플랜 타일: `closingSoon == true` 일 때만 `마감 임박(예상)` 배지를
  '영업중' 배지 옆에 추가(closed 배지와는 공존하지 않음). 헤더 Row 를
  Flexible 화해 320dp + 200% 텍스트 스케일에서 오버플로 예외 없음.
- S-21: slot 카드에 마감 임박 배지, factor 칩은 마감 계열 공통 '예상 운영시간'.
- 참조 클라이언트: `LalaPlanSlot.closingSoon`(부가 필드, 부재 → null).
  생성 클라이언트(clients/flutter_generated)는 변경 불필요 — closure_state 를
  모델링하지 않으므로 부가 필드 영향 없음(244 테스트 무변경 통과로 입증).

## 가정

- window 60분은 제품 합의 상수가 아니라 이 체크포인트에서 도입한 문서화된 값이다.
  실측 체류시간 authority 가 생기면 재조정 필요.
- 개입 original 슬롯은 고정 afternoon(14:00) 이고 현행 카테고리 추정표에서 가장
  이른 마감이 18:00 이므로, 현재 데이터로는 closing_soon 개입 트리거가 실제
  경로에서 발동하지 않는다(기존 closure_detected 가 snapshot 데이터로 발동하지
  않는 것과 동일한 구조). dinner(18:00) × culture_venue(19:00 마감) 등 일일
  플랜 슬롯 투영·S-20 배지는 실제로 발동한다. 발동 조건은 데이터가 바뀌면
  (추정 마감 ≤ 15:00) 자동으로 열린다 — 시간을 발명해 발동시키지 않는다.
- 마감 시각 정각 경계는 `is_within_hours` 의 포함 규칙을 따라 "운영중 + 마감
  임박"으로 판정한다(closed 와 closing-soon 이 동시 참이 되지 않게 하는 근거).

## 테스트

- API: `test_opening_hours_service.py`(경계 행렬 before/window/exact-close/
  after-close, 자정 넘김, 파손값, 상호 배제 분 스윕), `test_v3_four_slot_projections.py`
  (투영·트리거·조합·플래그 off 바이트 호환·진위표 13행·스키마), `test_planner_service.py`
  (사유/행동 정직성, 조합 원인 명시, 금지 어휘). 전체 `uv run pytest apps/api/tests`
  2078 passed.
- Flutter: 배지 5로케일 전 트리거 표, 금지 어휘 스윕, 단일 언어 검증, 320px +
  TextScaler.linear(2) 위젯 테스트(토스트/타일/S-21, 스크롤 포함, 예외·오버플로
  없음). `flutter analyze` 0 이슈, `flutter test` 1139 passed. 참조 클라이언트
  48 passed, 생성 클라이언트 244 passed(무변경).

## 검증자 정정(correction, 2026-09-05 2차)

독립 검증이 두 가지 결함을 확정해 정정했다. 범위는
`apps/api/app/services/opening_hours_service.py` 와 그 테스트뿐(Flutter/생성
클라이언트/카테고리 데이터/문구 무변경).

1. **공유 strict 파서**: `_hhmm_minutes` 는 정확한 ASCII `HH:MM` 만 받는다 —
   길이 5, index 2 콜론, `[0-9]` 문자 클래스(`\d` 는 Unicode 숫자를 받으므로
   사용 금지), 시 00-23, 분 00-59. 잘못된 구분자·과길이(`"11:000"`)·부호
   (`"+11:00"`)·공백/패딩·전각·Arabic-Indic·첨자 digit·시 ≥24·분 ≥60·빈 값·
   비문자열은 모두 None(unknown)이고 긍정 판정으로 이어지지 않는다. 기존
   `int(슬라이싱)` 구현이 전각 digit/부호/공백/과길이를 받아들이던 것이 결함이었다.
2. **공유 멤버십**: `is_within_hours`/`is_closing_soon` 이 같은 파서와 같은
   `_within_minutes` 멤버십을 쓴다 — 주간(open<close)은 open 이상 close 이하,
   자정 넘김(close<open, 예: 20:00-02:00)은 당일 open 이후 또는 close 이전,
   `open==close` 는 unknown. 기존 `is_within_hours` 에 자정 넘김/open==close
   규칙이 없어 `is_closing_soon` 과 정의가 어긋났던 것이 결함이었다. 결과적으로
   유효한 모든 분에서 `closing_soon=True ⇒ is_within_hours=True` 가 성립하고
   `_plan_slot` payload 에서 `closing_soon=True` 는 `closure_state="closed"` 와
   공존하지 않는다.

정정 테스트(`test_opening_hours_service.py`, `test_v3_four_slot_projections.py`):
45개 adversarial malformed 표현 × (슬롯/open/close/자정넘김) 조합이 모두
unknown; 유효 경계 값 수용(과잉 거부 없음); 20:00-02:00 멤버십 경계; open==close
양쪽 unknown; 20:00-09:30 × morning 09:00(운영중 + 마감 30분, helper +
`_plan_slot` payload 증명); 주간/자정넘김 2종 전일(1440분) 스윕으로
(closing_soon ⇒ within) 함축과 window 정합성 검증; 파손 추정시간의
`_plan_slot` unknown 투영. 기존 테스트는 약화하지 않았다(기존 165→신규 포함
전체 통과).

정정 후 확인된 동작 변화는 의도된 것뿐: 과길이 입력(예: `"09:30:00"`)이
과거 첫 5자를 잘라 판정했다면 이제 정직한 unknown. 실제 호출처(planner/
places_service)는 카테고리 표와 프론트엔드 `HH:MM` 값만 전달하므로 영향 없음
(전체 API 스위트 통과로 확인).

## 외부 게이트(실제 운영시간 authority)

- 카테고리 추정표가 아닌 실제 운영시간(Kakao Places 상세 hours, 공공데이터
  영업시간) 이 연결되기 전까지 모든 마감 라벨은 추정이다. authority 연결 시
  (1) `estimated_opening_hours`/`closing_soon` 값을 실측으로 대체하고 라벨에서
  "예상/(est.)" 마커를 내리며, (2) 폐업(`bsn_state_nm`) 등 실측 상태는 별도
  원인 코드로만 표현해야 한다(BLOCKED_EXTERNAL V7).
