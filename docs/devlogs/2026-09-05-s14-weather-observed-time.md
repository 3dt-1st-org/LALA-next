# S-14 날씨 관측 시각(observed time) 노출 — 2026-09-05

## 배경

API/reference 클라이언트는 이미 `LalaWeather.recordTime`(`record_time`)를 전달하지만,
S-14 날씨 시트는 이를 조용히 버렸다. 제품 문서(`lala-service-functional-spec.md` F-014 출력:
"기온, 하늘 상태, 야외 적합도, PM10, PM2.5, **관측 시각**, 예보, 출처")는 이 화면이 관측
시각을 노출한다고 명시한다. 이 변경은 UI 가 wire 계약보다 신선도에 대해 덜 정직했던 부분을
닫는다.

## 커밋

1. `afd9e353` — 순수 헬퍼 + 결정적 단위 테스트.
2. `07540e81` — S-14 UI 통합(배지 + 히어로 카드 반응형) + 위젯/a11y/큰 텍스트 테스트.
3. (이 커밋) 파서 경성화 — 음수 오프셋 분 단위 적용, 무효 성분 명시적 거부.

## 정확한 동작

### 파싱(wire 표현 — 현행 fixtures/tests 에 실제로 존재하는 두 가지)

- ISO-8601 + 오프셋: `2026-06-18T23:00:00+09:00`(`docs/api/flutter-contract.md`,
  `apps/api` KMA/DB `isoformat()` 경로). 소수 초(`.ffffff`)도 허용 — Python
  `datetime.isoformat()` 이 마이크로초를 붙일 수 있기 때문.
- KMA/AirKorea `dataTime` 비-타임존 형식: `2026-06-21 12:00`
  (`weather_service.py` 의 airkorea 단독 `record_time` 경로). 두 공급자 모두 KST
  벽시계를 보고하므로 **KST(+09:00)로 해석**한다. 기기 로컬 타임존을 쓰지 않는다
  (timezone truth). 표시는 항상 관측 순간의 KST 벽시계로 정규화한다(예: `+00:00`
  관측은 KST 시각으로 표시).

### 경성화(세 번째 커밋)

- 음수 오프셋 부호는 **시·분 모두**에 적용: `-05:30` == -330분. 회귀:
  `2026-09-04T09:00:00-05:30` → `2026-09-04 14:30Z` → `관측 시각 2026-09-04 23:30`.
- `DateTime` 정규화에 기대지 않고 왕복 검사로 무효 성분 명시적 거부: 2월 30일,
  평년 2월 29일, 9월 31일, 24시, 60분, 60초 → 모두 정직한 unknown. 윤년 2월 29일은
  유효하게 통과(거부 과잉 없음).
- ISO-8601 오프셋 범위(±23:59) 밖(`+99:00`)도 거부.

### 신선도 정책(UI 전용 상수)

- `kWeatherObservationCurrentWindow = Duration(minutes: 60)` — 관측 시각이 이 창
  안이면 `current`("최신 관측"), 지나면 `stale`("이전 관측값").
- 근거: KMA 초단기실황(~10분 주기)과 AirKorea 시도 실시간 대기질(~1시간 주기) 중
  늦은 쪽의 한 사이클. 60분 초과는 최소 한 공급 사이클 이상 갱신 지연이므로 실시간
 처럼 보이게 두지 않는다. Local Signals 의 14일 임계값과 무관하다(코드/문서/테스트에
  날씨 UI 용 확립된 창은 없어 새로 도입).
- 경계(포함): 경과 == 60분 정각 → current; 60분 + 1ms → stale.
- 미래 skew 허용치 `kWeatherObservationClockSkewTolerance = 2분`: 정확히 2분 미래는
  age 0으로 클램프해 current; 2분 + 1ms 초과 미래는 unknown.
- 부재/망가짐/미래 skew → 정직한 unknown("관측 시각 확인 중"). 나이를 발명하지
  않는다. "방금 전"류 상대 문구는 절대 출력하지 않는다.
- 헬퍼는 `now` 주입 순수 함수 — 완전 결정적.

### UI(S-14 WeatherSheetContent)

- `WeatherObservationBadge`(`weather-observed-time` key): 히어로 카드(현재 날씨
  요약) 바로 아래 배치. `Wrap` 조합(고정 Row 아님)으로 320dp/큰 텍스트에서 감싸진다.
- valid: `관측 시각 14:30`(같은 KST 날짜) 또는 `관측 시각 2026-09-04 23:00`(다른
  날짜) + 최신/이전 칩(색상 점). unknown: `관측 시각 확인 중`, 상태 칩 없음.
- 5개 로케일 `lalaCopyMulti`: ko/en/ja/zh-Hans/zh-Hant(BCP-47 변형 정규화 포함).
- 스크린 리더: `Semantics(container, excludeSemantics, label)` 한 노드로
  "관측 시각 …, 최신 관측" 결합 전달.
- 기존 unavailable 동작 보존: placeholder/null 날씨는 여전히
  `weather-unavailable-card`만(배지 없음). 공개 API/클라이언트 계약·생성 클라이언트
  미변경.
- 히어로 카드(`WeatherHeroCard`): 고정 `Row`가 320dp + `TextScaler.linear(2)`에서
  출처 칩으로 넘쳤다. `LayoutBuilder` + 이중 `Wrap`(spaceBetween)으로 변경 — 넓은
  폭에서는 종전 배치(텍스트 좌측, 칩 우측) 유지, 좁은 폭/큰 텍스트에서는 칩이 아래
  run으로 감싸진다. FittedBox 축소 없음.

## 검증 명령과 결과(apps/flutter_app 기준)

- `flutter test test/features/weather/weather_observation_freshness_test.dart` →
  23 passed(경계/무효 성분/오프셋/로케일 포함).
- `flutter test test/features/weather/weather_observation_badge_test.dart` →
  16 passed(320dp+2x 배지·시트, semantics, 5로케일, unavailable 보존 포함).
- `flutter test test/features/weather/` → 58 passed(기존 helpers/pill/chart 포함).
- `flutter analyze` → No issues found.
- `flutter test --reporter expanded`(전체) → **+1104: All tests passed** (약 55초).
- 리포지토리 루트: `uv run pre-commit run --all-files`, `git diff --check` →
  커밋 시점에 통과(아래 결과 보고서에 최종 기록).

## 정직한 한계

- 시뮬레이터/실기기 런타임 검증 없음(위젯/단위 레벨 결정적 검증만). 실기기 화면
  날씨 시트의 픽셀/타이포그래피는 미확인.
- 60분 창은 UI 정책 상수이며 서버 계약이 아니다. 서버가 자체 신선도 임계값을
  내려주면 그쪽으로 일원화해야 한다.
