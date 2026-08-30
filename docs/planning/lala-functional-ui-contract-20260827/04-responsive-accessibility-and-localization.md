# 04. 반응형·접근성·현지화

## 1. 기준 viewport

| 대상 | 검증 기준 |
| --- | --- |
| iOS | iPhone 17 Pro Simulator의 실제 reported logical viewport |
| 모바일 웹 | 393×852 |
| 짧은 모바일 | 높이 667dp 수준에서 action 접근 가능 여부 |
| 데스크톱 웹 | 1280×900 |
| 확대 | 200% browser zoom, Flutter textScaleFactor 1.3/2.0 |

iPhone 논리 해상도를 문서에 추정값으로 고정하지 않는다. 캡처 보고서가 기기명,
OS, 실제 logical size, build SHA를 기록한다.

## 2. 반응형 규칙

### 모바일

- 지도는 full-bleed, 상세는 bottom sheet다.
- 일반 화면은 24dp gutter, 지도 overlay는 12dp gutter를 사용한다.
- bottom navigation 높이와 safe area만큼 scroll content 하단 여백을 확보한다.
- fixed CTA는 화면당 하나의 command group만 사용하고 본문 action을 가리지 않는다.
- 긴 chip row는 해당 row만 수평 스크롤한다. 페이지 전체 가로 overflow는 금지한다.

### 넓은 웹

- 지도는 계속 full-bleed이며 상세를 최대폭 side panel로 연다.
- 검색·일정·Signals의 본문은 읽기 가능한 max-width에 제한한다.
- bottom navigation을 무작정 데스크톱 전체 폭으로 늘리지 않는다. 동일 정보구조의
  compact rail 또는 제한 폭 navigation으로 전환할 수 있다.
- fixed CTA가 상세 근거나 마지막 slot을 가리지 않는다.

## 3. 텍스트와 overflow

- viewport 폭으로 font size를 비례 확대하지 않는다.
- compact panel 제목은 hero scale을 사용하지 않는다.
- 긴 한국어·영어·일본어·중국어 장소명은 최대 2줄 후 의미 있는 ellipsis를 사용한다.
- 버튼 label이 잘리면 먼저 줄바꿈·폭 확장을 검토하고, icon-only로 바꾸는 경우 tooltip과
  semantic label을 제공한다.
- source/freshness는 11sp 미만으로 줄이지 않는다.
- letter spacing은 0이다.

## 4. 접근성

| 항목 | 수용 기준 |
| --- | --- |
| touch | 모든 interactive target 44×44dp 이상 |
| label | icon-only button에 tooltip + semantic label |
| 이미지 | 실제 장소명 기반 alt 또는 decorative 제외 선언 |
| focus | 읽기 순서가 시각 순서와 일치, modal 밖 focus 차단 |
| 선택 | 색상 외 check/outline/icon 사용 |
| 상태 | loading/error/stale를 screen reader live region으로 전달 |
| 지도 | pin에 장소명·category label, 동일 장소 list 대체 경로 제공 |
| 동적 글자 | 2.0에서 CTA와 navigation이 본문을 가리지 않음 |
| 대비 | WCAG AA, muted meta도 최소 대비 유지 |
| motion | reduce motion에서 carousel/sheet animation 축소 |

## 5. 현지화

- 지원 UI locale: KO, EN, JA, zh-Hans, zh-Hant.
- 한 화면에는 선택 언어 하나만 사용한다. 고유명사·공식 source label은 예외다.
- 서버 콘텐츠가 KO/EN만 제공되면 JA/zh 사용자는 EN fallback을 받고, 필요한 곳에
  `영어로 제공`에 해당하는 짧은 고지를 표시한다.
- 국기 emoji를 언어 identity로 사용하지 않는다. `KO`, `EN`, `JA`, `简`, `繁`처럼
  텍스트 badge를 사용한다.
- CJK font fallback을 명시한다. 플랫폼 기본값에만 의존하지 않고 KR/JP/SC/TC glyph가
  안정적으로 표시되는 stack을 선택한다.
- 숫자·날짜·상대시간은 locale formatter를 사용하고 문자열 연결로 조립하지 않는다.

## 6. 화면별 접근성 이름 예시

| control | KO | EN |
| --- | --- | --- |
| 저장 | `장소 저장` / `저장 해제` | `Save place` / `Remove saved place` |
| 지역 | `탐색 지역 변경` | `Change exploration region` |
| 필터 | `검색 필터` | `Search filters` |
| 현재 위치 | `현재 위치로 지도 이동` | `Move map to current location` |
| 도슨트 | `도슨트 재생` / `음성 사용 불가` | `Play docent` / `Audio unavailable` |
| 일정 적용 | `대체 일정 적용` | `Apply alternative plan` |
