# 00. 제품·시각 기준

## 1. 입력 자료의 역할

| 입력 | 사용 범위 | 그대로 복제하지 않는 것 |
| --- | --- | --- |
| 기능 정의서 | 기능·상태·완료 조건 | 화면 치수와 장식 |
| 기존 20260728 계약 | 토큰·4탭·지도·일정·Signals 구조 | 이미 해소된 과거 코드 경로 |
| Stitch A | 지도와 Local Signals의 IA | 예시 수치, 무동작 버튼, 원격 이미지 |
| Stitch B | 언어·지역·출처·개입 사유·이동 흐름 | 한 화면 언어 혼합, 중복 저장 CTA |
| 현재 Flutter 코드 | 실제 위젯·상태·조건부 import | 코드에 있다는 이유만으로 나쁜 UX 유지 |
| 현재 API 모델 | 실제 표시 가능한 필드 | 내부 점수·원문·개인정보 노출 |

## 2. 시각 방향

- 운영 도구처럼 조용하고 빠르게 스캔되는 정보 밀도를 유지한다.
- 지도는 전체 화면 Kakao surface가 주인공이며 카드형 페이지 안에 넣지 않는다.
- 페이지 section을 떠 있는 카드처럼 만들지 않는다. 카드는 장소·신호·슬롯처럼
  반복되는 개별 항목에만 사용한다.
- 카드 radius는 기존 토큰 `controlRadius` 8dp를 기본으로 한다. draggable sheet의
  상단 20dp는 기존 `sheetTopRadius` 예외다.
- 하나의 지배색으로 화면을 채우지 않는다. 카테고리 색, 상태 색, 중립 회색을
  역할별로 사용한다.
- 장식용 gradient orb, bokeh, 과도한 hero type, 중첩 카드를 사용하지 않는다.
- 버튼은 명령에만 텍스트를 사용하고, 저장·필터·설정·재생처럼 익숙한 동작은
  아이콘 또는 아이콘+짧은 라벨과 tooltip으로 제공한다.

## 3. 런타임 진실성 등급

UI 요소는 아래 등급 중 하나로만 표시한다.

| 등급 | 표시 규칙 |
| --- | --- |
| `observed` | API가 값과 관측·집계 시각을 함께 제공. 값+출처+시각 표시 가능 |
| `estimated` | 코드가 추정값임을 명시. 값 옆에 `예상`/`Estimated` 표시 |
| `stale` | 마지막 정상값은 유지하되 stale 아이콘·문구·기준 시각 표시 |
| `unavailable` | 값 자리에 숫자나 placeholder를 넣지 않고 사유와 다음 행동 표시 |
| `disabled` | 기능이 운영 설정상 비활성. 사용 가능한 대체 경로를 유지 |

### 금지 예시

- `Updated 5m ago`를 현재 시각으로 임의 계산
- 공급자 없는 `92% positive`, `450+ mentions`, `실시간 한적함` 표시
- 좌표 기반 이동시간을 실제 경로 탐색 결과처럼 표시
- 음성 바이트가 없는데 재생 버튼을 활성화
- 네트워크 오류를 결과 없음으로 표현
- 장소 이미지가 없는데 다른 장소의 사진을 대체 사용

## 4. 토큰 계약

현재 SSOT는 `apps/flutter_app/lib/app/lala_visual_tokens.dart`다. 구현 전에 새
토큰을 만들기보다 기존 토큰을 우선 사용한다.

| 역할 | 계약 |
| --- | --- |
| 페이지 gutter | 일반 화면 24dp, 지도 overlay 12dp |
| 카드·control radius | 8dp |
| sheet 상단 radius | 20dp |
| 최소 touch target | 44×44dp |
| 본문 | compact panel에서 읽기 쉬운 크기, viewport 폭 기반 확대 금지 |
| 메타 정보 | 11sp 미만 금지, muted color라도 대비 AA 유지 |
| letter spacing | 0 |

## 5. 카테고리와 상태 표현

- `attraction`, `restaurant`, `event`, `culture`의 기존 색 바인딩을 chip, pin,
  card accent에서 동일하게 사용한다.
- 선택은 색만 바꾸지 않고 outline·아이콘·z-order 중 두 가지 이상을 사용한다.
- stale/error/disabled도 색상 외 아이콘과 문구를 함께 사용한다.
- 전체 카테고리는 중립 treatment를 사용하고 특정 카테고리 색을 빌리지 않는다.
