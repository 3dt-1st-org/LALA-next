# 06. 시각·동작 수용 행렬

## 1. 증거 규칙

각 캡처에는 다음 metadata를 남긴다.

- exact Git SHA와 `LALA_BUILD_SHA`
- 플랫폼·OS·device·actual logical viewport
- 선택 locale과 region source
- action sequence
- 사용한 API base의 공개 식별 가능한 호스트만 기록하고 secret·query payload는 제외
- screenshot SHA-256
- OCR로 확인한 주요 문구와 사람의 시각 판정

서로 다른 상태라고 주장하는 파일의 SHA-256이 같으면 해당 증거는 무효다. 같은 이미지를
이름만 바꾸어 여러 상태로 제출하지 않는다.

## 2. 화면별 필수 증거

| 화면 | 필수 상태 | 데이터 진실성 | 핵심 시각 판정 |
| --- | --- | --- | --- |
| 온보딩 | 여행 유형 initial/selected, 언어, 위치, denial, manual region | 저장 상태와 실제 permission result | 한 화면 한 언어, 세 action, overflow 없음 |
| 검색 | loading, loaded, empty/error 중 실제 발생 상태 | 실제 place ID와 region | region 행, 단일 sort, skeleton 전환 |
| 지도 | loading, loaded, selected, location recovery | Kakao surface와 실제 pins | pin/rail/dock 동기화, overlap 없음 |
| 상세 | summary, reason expanded, audio disabled 또는 available | 실제 source/time, actual image 또는 honest fallback | 저장 CTA 하나, source 의미 분리 |
| 일정 | loading, 4-slot loaded, recovery comparison 또는 honest no-trigger | actual plan slots, estimated 표시 | connector, CTA non-overlap, keep/apply |
| Signals | loading, loaded 또는 honest empty | aggregate-only, no raw review | freshness와 filter disclosure, action 상태 |

## 3. 플랫폼 행렬

| 검사 | iPhone 17 Pro | 모바일 웹 393×852 | 데스크톱 웹 1280×900 |
| --- | --- | --- | --- |
| 온보딩·지역 | 필수 | 필수 | 필수 |
| Kakao 지도·pin | 필수 | 필수 | 필수 |
| 지도 상세 surface | bottom sheet | bottom sheet | side panel |
| 검색·정렬·지역 | 필수 | 필수 | 필수 |
| 4슬롯·recovery | 필수 | 필수 | 필수 |
| Signals | 필수 | 필수 | 필수 |
| text scale/zoom | 1.0, 1.3, 2.0 | 100%, 200% | 100%, 200% |
| keyboard/focus | screen reader 표본 | keyboard 필수 | keyboard 필수 |

## 4. 실패 판정

다음 중 하나면 시각 PASS가 아니다.

- `오류`, `준비 중`, placeholder 화면만 캡처하고 loaded라고 보고
- 실제 데이터 없이 시안 수치를 fixture로 넣음
- Kakao surface 대신 정적 bitmap을 지도 증거로 사용
- 위치·선택·일정 상태를 VM state injection으로만 만들고 터치 흐름 미검증
- 하단 navigation이나 fixed CTA가 본문 action을 가림
- source/freshness가 실제 field와 무관함
- 한국어와 영어가 선택 언어와 무관하게 섞임
- 음성 disabled인데 활성 play affordance가 보임
- 캡처 hash 중복 또는 exact build SHA 누락

## 5. 수용 보고 형식

| ID | 화면/상태 | 플랫폼 | build SHA | action sequence | observed data | screenshot/hash | 판정 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A-01 | 예: 지도 loaded | iPhone 17 Pro | `<sha>` | 앱 시작→위치 허용→지도 | 실제 place count/source | `<path>` / `<hash>` | PASS/FAIL |

최종 보고는 `PASS`, `CORRECTION_REQUIRED`, `BLOCKED_EXTERNAL`을 구분한다. 자동 테스트
통과를 runtime PASS로 승격하지 않는다.
