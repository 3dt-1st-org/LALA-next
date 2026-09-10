# 화면 선별 대조표와 결정 질문

상태: **수령 전 대조 틀 작성 / 최종 최소 화면 범위 미결정**. 화면 선별 PDF와 온보딩 질문안은 아직 받지 않았다. 아래는 9/7 비교 자료와 9/8 회의 공개 요약을 기준으로 만든 가안이며, 새 자료를 받으면 화면별 선택·근거를 갱신한다.

## 1. 대조 방법과 증거

- 논리 화면 36개 ID를 추적한다. 이 목록 전체를 구현 목록이나 출시 완료 목록으로 쓰지 않는다.
- 판정은 사용자 선택·회의 방향·코드 사실·설계 제안을 구분한다. 코드 대표 파일 존재나 변경 여부는 실제 화면·로그인·음성 성공을 뜻하지 않는다.
- 9/7 보고서의 캡처는 여러 과거 빌드다. S-21·S-51·S-58·S-59에는 독립 캡처가 없다. 생성 시안은 디자인 승인본이 아니다.
- 원본은 [보존 목록](04-preservation.md)의 v3.1 Markdown/PDF다. 이번 대조에는 같은 로컬 디렉터리의 team-code-evidence.json을 보조 색인으로 사용하고, 대표 소스의 존재·내용 차이는 Git 객체로 다시 확인했다.
- 모든 화면의 새 자료 출처·쪽수·질문안 버전·검토자·최종 선택은 수령 전이므로 미기입이다. 수령했다고 추정하지 않는다.

## 2. 최소 사용자 흐름 가안

첫 진입·게스트/로그인 → 국가·언어·여행 스타일 → 현재 위치 또는 다른 여행지 → 탐색·검색 → 장소 상세 → 저장 → 저장 목록 → 장소 상세/도슨트.

도슨트는 상세에서 바로 들을 수도 있다. 저장을 재생의 필수 선행 조건으로 만들지 않는다. 자동 안내는 ON/OFF 선택을 유지하며 별도 조건을 정한다. 위치 거부 시 수동 지역 선택으로 이어지고, 재진입은 저장한 설정과 인증 상태를 확인한다.

필수 상태는 loading·empty·error·retry, 위치 거부, 계정 연결 실패, 기기 저장·계정 동기화 상태다. 화면 수를 줄여도 이 상태가 사라지는 것은 아니다.

## 3. 결정 질문

| ID | 질문 | 결정 주도 / 검토 | 결과 기록 |
|---|---|---|---|
| Q-01 | 첫 화면은 지도형·정보형 중 무엇이며 현재 위치/다른 여행지 선택은 어디에 두는가? | 프론트 / 백엔드·PM | 미결정 |
| Q-02 | 온보딩 질문 순서·필수/선택·재진입 처리는 무엇인가? | 프론트 / PM·백엔드 | 질문안 수령 대기 |
| Q-03 | 추천 투어 편집·자유 경로·장소 중심 생성 중 첫 실증 범위는? | 백엔드·프론트 / PM·기술 리드 | 미결정 |
| Q-04 | 게스트 저장을 계정에 연결하는 동의·충돌·로그아웃 후 보존 정책은? | 백엔드·기술 리드 / 프론트·PM | 기존 코드와 목표 정책 대조 필요 |
| Q-05 | 자동 도슨트의 시작·중단·중복 억제 조건과 느리게/빠르게 배속은? | 프론트·백엔드 / PM | 1배속 기본·3단계 방향만 확정 |
| Q-06 | 음식점 도움·기본 날씨·지난 일정·방문 독립 화면은 어디까지 필요한가? | 프론트·백엔드 / PM | 미결정 |
| Q-07 | 식이·접근성·예산 등 설정과 추천 요청의 경계는? | 백엔드·기술 리드 / 프론트 | 세밀한 초기 예산·혼잡 선택은 보류 |
| Q-08 | 실증 행동·피드백에서 성공을 어떻게 판단할 것인가? | PM / 개발팀 | 측정 항목 제안, 목표 수치 미결정 |

## 4. 화면별 카드

각 카드의 코드 링크는 대표 경계만 가리킨다. 공통 의존성 전체는 기존 보고서와 [API·MVVM 설계](09-mvvm-and-api-contracts.md)를 함께 본다. 분류의 '핵심 후보'는 최종 화면 채택이 아니라 해당 사용자 흐름을 우선 검토한다는 뜻이다.

### S-01 · 앱 시작·상태 복원

- **분류:** 핵심 후보 · 제안. 목적: 앱을 처음 또는 다시 열고 다음 행동으로 이동.
- **포함 검토:** 복원·재진입·실패 후 게스트 진입. **보류·제외 검토:** 장식용 복원 단계 확대.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/onboarding/presentation/pages/splash_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/onboarding/presentation/pages/splash_page.dart).
- **API·저장·공통 의존성:** S-01 타이머 → 온보딩 시작; 저장 스냅샷과 router redirect는 별도 경로다. 전역 복원 코드의 존재를 S-01 복원 UI 완료로 세지 않는다.
- **남은 검증·결정:** 손상 저장값·만료 인증에서 무한 대기가 없는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-02 · 여행 맥락 선택

- **분류:** 핵심 후보 · 제안. 목적: 한국 여행의 맥락을 정함.
- **포함 검토:** 로그인/게스트·국가·언어·여행 스타일 흐름에 맞춰 재배치. **보류·제외 검토:** 해외 목적지 확장·생활권 포함 3갈래 진입.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/onboarding/presentation/pages/start_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/onboarding/presentation/pages/start_page.dart).
- **API·저장·공통 의존성:** start_page → OnboardingState → OnboardingPreferences → 후속 온보딩. 현재 두 선택지이며 추천 소비 계약과는 분리해서 본다.
- **남은 검증·결정:** 현재 위치/다른 여행지 선택은 어느 화면에 놓는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-03 · 언어 선택

- **분류:** 핵심 후보 · 제안. 목적: 이해할 수 있는 언어로 시작.
- **포함 검토:** 국가 기반 언어 제안과 직접 변경. **보류·제외 검토:** 국가가 언어를 강제로 고정하는 동작.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/onboarding/presentation/pages/language_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/onboarding/presentation/pages/language_page.dart).
- **API·저장·공통 의존성:** 언어 선택 → OnboardingState → 화면 copy/API 언어; 지도는 KO NAVER, 나머지 지원 언어 open-vector로 분기한다.
- **남은 검증·결정:** 언어 변경과 재진입에서 선택이 유지되는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-04 · 위치 사용·추천 지역

- **분류:** 핵심 후보 · 제안. 목적: 위치 사용 여부를 선택.
- **포함 검토:** 동의·거부·수동 지역 선택 연결. **보류·제외 검토:** 위치 허용을 강요하는 진입.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/onboarding/presentation/pages/location_consent_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/onboarding/presentation/pages/location_consent_page.dart).
- **API·저장·공통 의존성:** location_consent → 플랫폼 위치 어댑터 / ManualLocationSheet → RegionContextStore → 탐색 화면.
- **남은 검증·결정:** 위치 거부 후 탐색과 도슨트 수동 진입이 가능한가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-05 · 지역 직접 선택

- **분류:** 핵심 후보 · 제안. 목적: 다른 지역의 여행지를 선택.
- **포함 검토:** 현재 위치와 다른 여행지 선택. **보류·제외 검토:** 불필요하게 세밀한 행정구역 필수 입력.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/location/widgets/manual_location_sheet.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/location/widgets/manual_location_sheet.dart).
- **API·저장·공통 의존성:** 온보딩 또는 지역 변경 → ManualLocationSheet → RegionContextStore. 화면 이름은 별도 ID지만 독립 전체 페이지는 아니다.
- **남은 검증·결정:** 외국인에게 이해 가능한 지역 선택 단위는 무엇인가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-06 · 선택적 계정 연결

- **분류:** 핵심 후보 · 제안. 목적: 게스트 또는 계정으로 이용.
- **포함 검토:** Logto 로그인과 게스트 지속, 계정 연결 결과. **보류·제외 검토:** 초기부터 상세 취향 전체 입력.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/onboarding/presentation/pages/account_link_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/onboarding/presentation/pages/account_link_page.dart).
- **API·저장·공통 의존성:** S-06 → LogtoAuthGateway → AuthController → GET /api/v1/me → lala_app의 계정별 취향/일정 연결. 인증 성공과 동기화 성공은 별도 상태다.
- **남은 검증·결정:** provider 로그인과 LALA 계정 연결 실패를 구분하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-10 · 지도 기반 탐색

- **분류:** 핵심 후보 · 제안. 목적: 주변 장소를 탐색.
- **포함 검토:** 언어별 지도·장소 선택·상세 연결. **보류·제외 검토:** 첫 화면을 지도형으로 미리 확정.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/map_route/presentation/pages/map_route_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/map_route/presentation/pages/map_route_page.dart).
- **API·저장·공통 의존성:** MapRoutePage → HomePage → LalaBackend.getPlaces → 장소 API. 선택 장소/일정은 공유 store. 지도 공급자 분기 변경은 후보 branch 상태를 별도 표시한다.
- **남은 검증·결정:** 지도형/정보형 첫 화면과 지역 선택 위치를 결정했는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-11 · 장소·지역 검색

- **분류:** 핵심 후보 · 제안. 목적: 장소와 지역을 검색.
- **포함 검토:** 검색·필터 후 빈 결과·다시 시도. **보류·제외 검토:** 복잡한 고급 조건 전체 노출.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/search/presentation/pages/search_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/search/presentation/pages/search_page.dart).
- **API·저장·공통 의존성:** SearchPage._fetchPlaces → LalaBackend.getPlaces → client. 화면 검색/필터와 서버 장소 데이터 계약을 구별한다.
- **남은 검증·결정:** 요청 순서가 바뀌어도 최신 검색 결과만 표시하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-12 · 장소 상세

- **분류:** 핵심 후보 · 제안. 목적: 장소를 이해하고 저장하거나 듣기.
- **포함 검토:** 필수 장소 정보·출처·저장·도슨트 연결. **보류·제외 검토:** 보류 기능까지 상세 버튼으로 자동 포함.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/place/presentation/pages/place_detail_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/place/presentation/pages/place_detail_page.dart).
- **API·저장·공통 의존성:** 상세 로드 → 장소 모델 → 선택 상태/일정 행동. 음식점 도움은 저장된 사용자 취향에서 만든 카드로 이동한다.
- **남은 검증·결정:** 정보 누락과 저장 실패를 성공으로 표시하지 않는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-13 · 음식점 방문 도움

- **분류:** 세부 범위 미결정. 목적: 음식점에서 요청을 전달.
- **포함 검토:** 설정에 보관한 식이·알레르기 정보의 선택적 활용. **보류·제외 검토:** 첫 진입 필수 식이 설문·음성 지원 전체 필수화.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/preferences/presentation/restaurant_communication_sheet.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/preferences/presentation/restaurant_communication_sheet.dart).
- **API·저장·공통 의존성:** S-54 저장값 → RestaurantCommunicationSheet → 한국어/방문객 카드 → Clipboard 또는 기기 TTS. 유료 도슨트 음성과 별개다.
- **남은 검증·결정:** 요청 카드·발음·기기 TTS 중 무엇을 넣는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-14 · 날씨·대기질 상세

- **분류:** 세부 범위 미결정. 목적: 장소 방문에 필요한 기본 날씨 정보를 확인.
- **포함 검토:** 기본 정보·관측 시각·unknown 표현 검토. **보류·제외 검토:** 날씨 변화에 따른 자동 일정 재계획.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/weather/widgets/weather_sheet_content.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/weather/widgets/weather_sheet_content.dart).
- **API·저장·공통 의존성:** Home/backend 날씨 응답 → WeatherSheetContent/신선도 helper. PR #206은 main 병합과 CI를 완료했지만 Flutter 배포·실기기 검증은 별도다.
- **남은 검증·결정:** 정보 표시와 자동 개입을 분리했는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-15 · 동선·투어 탐색

- **분류:** 세부 범위 미결정. 목적: 추천 투어 또는 경로를 탐색.
- **포함 검토:** 추천 투어와 장소 중심 생성 후보 검토. **보류·제외 검토:** 세 가지 생성·편집 방식 전부를 필수화.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/tour/widgets/tour_sheet_content.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/tour/widgets/tour_sheet_content.dart).
- **API·저장·공통 의존성:** Home가 전달한 places.take(5) → TourSheetContent의 읽기 목록/해설. 해당 StatelessWidget에는 후보 편집 상태나 순서 전달 CTA가 없다.
- **남은 검증·결정:** 추천 편집/자유 경로/장소 중심 중 첫 범위는 무엇인가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-20 · 하루 일정

- **분류:** 핵심 후보 · 세부 미결정. 목적: 저장하거나 선택한 일정 확인.
- **포함 검토:** 단순한 장소·투어 저장과 일정 확인. **보류·제외 검토:** 날씨 재계획·복잡한 방문 이력 연동.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/plan/presentation/pages/plan_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/plan/presentation/pages/plan_page.dart).
- **API·저장·공통 의존성:** PlanPage._fetchPlan → composePlanPreferenceContext → createDailyPlan → getIntervention. 공유 plan store가 지도/검색 행동을 이어받는다.
- **남은 검증·결정:** 생성·편집·저장의 단위와 전환을 정했는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-21 · 상황 변화 비교

- **분류:** 보류 · 확정. 목적: 상황 변화에 따른 일정 대안을 비교.
- **포함 검토:** 기존 코드·테스트·공유 상태 의존성 보존. **보류·제외 검토:** 날씨 기반 일정 재계획을 첫 실증에 포함.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/intervention/presentation/pages/intervention_comparison_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/intervention/presentation/pages/intervention_comparison_page.dart).
- **API·저장·공통 의존성:** getIntervention → PlanPage → InterventionComparisonPage → 명시적 선택 결과 → 대안 적용/되돌리기.
- **남은 검증·결정:** 기본 날씨·일정 조회까지 함께 끊지 않았는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-22 · 이번 여행 설정

- **분류:** 세부 범위 미결정. 목적: 이번 여행만의 설정을 구분.
- **포함 검토:** 기본 취향과 여행별 설정의 데이터 경계. **보류·제외 검토:** 모든 임시 설정·충돌 해결 UI의 필수화.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/trip_library/presentation/pages/trip_settings_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/trip_library/presentation/pages/trip_settings_page.dart).
- **API·저장·공통 의존성:** TripSettingsPage → TripLibraryStore.saveOverride → /me/plans/{date}/preferences. 일정 요청 때 defaults와 날짜 override를 합성한다.
- **남은 검증·결정:** 기본값 적용과 override/revision 정책은 무엇인가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-23 · 저장한 장소

- **분류:** 핵심 후보 · 제안. 목적: 저장한 장소를 다시 확인.
- **포함 검토:** 저장·해제·목록·누락 장소 안내. **보류·제외 검토:** 저장과 방문을 같은 상태로 취급.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/trip_library/presentation/pages/saved_places_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/trip_library/presentation/pages/saved_places_page.dart).
- **API·저장·공통 의존성:** SavedPlaceStore/TripLibraryStore → GET/PUT/DELETE /me/saved-places → PlanningRepository. 표시 시 실제 장소 projection을 읽는다.
- **남은 검증·결정:** 기기 저장·원격 승인·동기화 상태를 구분하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-24 · 지난 일정

- **분류:** 세부 범위 미결정. 목적: 이전 일정 확인.
- **포함 검토:** 보존할 과거 데이터와 최소 조회 필요성 검토. **보류·제외 검토:** 복잡한 과거 일정·방문 통합.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/trip_library/presentation/pages/past_trips_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/trip_library/presentation/pages/past_trips_page.dart).
- **API·저장·공통 의존성:** PastTripsPage → TripLibraryStore → /me/plans. _reuse에서 날짜를 선택하여 재사용하며 원본 불변과 최신 데이터 재평가는 별도 합격 조건이다.
- **남은 검증·결정:** 독립 화면이 이번 실증에 필요한가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-25 · 방문 확인

- **분류:** 상태 구분 확정 · 화면 미결정. 목적: 방문 여부를 기록 또는 확인.
- **포함 검토:** 저장과 방문의 구분, 상세 내 상태 표시 후보. **보류·제외 검토:** 스탬프·배지·수집과 복잡한 이력.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/trip_library/presentation/pages/visit_confirmation_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/trip_library/presentation/pages/visit_confirmation_page.dart).
- **API·저장·공통 의존성:** VisitConfirmationPage → TripVisitFeedback → saveVisit → PUT /me/plans/{date}/visits/{slot}. 소비액 모델/수집 계약은 별도로 필요하다.
- **남은 검증·결정:** 독립 화면과 상세 표시 중 무엇이 필요한가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-30 · 장소 도슨트

- **분류:** 핵심 후보 · 제안. 목적: 장소를 선택해 설명을 듣기.
- **포함 검토:** 직접 재생·단일 재생 상태·재시도·자동 안내 선택. **보류·제외 검토:** 검증되지 않은 설명·음성을 완료로 표시.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/docent/presentation/pages/docent_player_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/docent/presentation/pages/docent_player_page.dart).
- **API·저장·공통 의존성:** DocentPlayerPage → DocentExperienceController → /docents/script 및 /docents/audio → playback controller. 준비되지 않은 음성은 별도 상태다.
- **남은 검증·결정:** 자동 안내 조건·중복 재생·실패 UX를 정했는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-31 · Local Signals 탐색

- **분류:** 보류 · 확정. 목적: Local Signals 탐색.
- **포함 검토:** 기존 코드·테스트·데이터 의존성 보존. **보류·제외 검토:** 첫 실증 진입과 인기·변화 정보 확장.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/local_signals/presentation/pages/local_signals_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/local_signals/presentation/pages/local_signals_page.dart).
- **API·저장·공통 의존성:** LocalSignalsPage → /community/signals 및 /community/signals/aggregates. 커뮤니티 신호와 장소별 주간 aggregate는 합쳐서 한 종류로 세지 않는다.
- **남은 검증·결정:** 공통 탐색·저장 경계를 함께 삭제하지 않는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-32 · Local Signal 상세·참여

- **분류:** 보류 · 확정. 목적: Local Signal 상세와 참여.
- **포함 검토:** 기존 권한·저장·이동 의존성 보존. **보류·제외 검토:** 첫 실증 참여 기능.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/local_signals/presentation/pages/local_signal_detail_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/local_signals/presentation/pages/local_signal_detail_page.dart).
- **API·저장·공통 의존성:** 신호 ID → participation repository → /community/signals/{id}. 장소 aggregate는 별도 조회이며 기간/대상 단위가 다르다.
- **남은 검증·결정:** 숨김과 서버 접근 제어를 혼동하지 않는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-40 · 커뮤니티 피드

- **분류:** 보류 · 확정. 목적: 커뮤니티 피드 확인.
- **포함 검토:** 기존 코드·테스트 보존. **보류·제외 검토:** 첫 실증 피드·운영 기능.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/community/presentation/pages/community_feed_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/community/presentation/pages/community_feed_page.dart).
- **API·저장·공통 의존성:** CommunityFeedPage → /community/posts → CommunityRepository. 계정/지역 변경 중 오래된 응답 폐기와 인증 경계가 중요하다.
- **남은 검증·결정:** 인증·공통 상태에 연결된 의존성은 무엇인가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-41 · 게시글 상세

- **분류:** 보류 · 확정. 목적: 게시글과 댓글 확인.
- **포함 검토:** 기존 코드·테스트·권한 검사 보존. **보류·제외 검토:** 첫 실증 게시글·댓글.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/community/presentation/pages/community_post_detail_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/community/presentation/pages/community_post_detail_page.dart).
- **API·저장·공통 의존성:** 게시글 ID → /community/posts/{id} → 댓글/반응/신고 API. UI 사용자 표기와 서버 작성자 권한을 구분한다.
- **남은 검증·결정:** 공통 인증을 함께 제거하지 않는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-42 · 커뮤니티 글 작성

- **분류:** 보류 · 확정. 목적: 커뮤니티 글 작성.
- **포함 검토:** 기존 쓰기 보호와 테스트 보존. **보류·제외 검토:** 첫 실증 작성·신고·운영.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/community/presentation/pages/community_create_post_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/community/presentation/pages/community_create_post_page.dart).
- **API·저장·공통 의존성:** 텍스트 controller → createCommunityPost(title, body, tags) → 커뮤니티 API. 오류 중 입력 보존은 있으나 디스크 초안 저장소와 사진 업로드 계약은 없다.
- **남은 검증·결정:** 쓰기 API의 보호를 유지하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-43 · 채팅방 목록

- **분류:** 보류 · 확정. 목적: 채팅방 목록 확인.
- **포함 검토:** 기존 연결·권한 검사 보존. **보류·제외 검토:** 첫 실증 채팅 목록.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/community/presentation/pages/chat_room_list_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/community/presentation/pages/chat_room_list_page.dart).
- **API·저장·공통 의존성:** ChatRoomListPage → GET/POST /community/chat/rooms → membership 기반 저장소. 로그아웃/계정 변경 때 목록을 다시 구분한다.
- **남은 검증·결정:** 계정 변경 시 정리 책임을 보존하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-44 · 채팅방

- **분류:** 보류 · 확정. 목적: 메시지 주고받기.
- **포함 검토:** 기존 중복·재시도·전달 권한 검사 보존. **보류·제외 검토:** 첫 실증 채팅.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/community/presentation/pages/chat_room_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/community/presentation/pages/chat_room_page.dart).
- **API·저장·공통 의존성:** ChatRoomPage → 일회성 ticket → WebSocket; 실패 시 REST와 동일 요청 키로 복구. 영속 메시지/멤버십과 프로세스 연결 상태는 별개다.
- **남은 검증·결정:** 진입점 숨김이 권한 검사 대체가 되지 않는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-50 · 설정 허브·내 정보

- **분류:** 핵심 후보 · 세부 미결정. 목적: 기본 설정과 계정 상태 확인.
- **포함 검토:** 계정·동의·취향·도슨트로 이어지는 최소 설정. **보류·제외 검토:** 전체 기존 설정을 그대로 첫 실증에 포함.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/profile/presentation/pages/profile_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/profile/presentation/pages/profile_page.dart).
- **API·저장·공통 의존성:** ProfilePage → 공용 auth/pref/trip store → 계정·취향·라이브러리·위치 설정. Google S-50/S-52는 같은 캡처로 중복된다.
- **남은 검증·결정:** 필요 설정으로 일관되게 이동하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-51 · 계정 관리

- **분류:** 핵심 후보 · 제안. 목적: 계정 연결 상태를 이해.
- **포함 검토:** 로그인·로그아웃·계정 동기화 상태. **보류·제외 검토:** provider 정보 표시를 계정 저장 성공으로 간주.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/profile/presentation/pages/account_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/profile/presentation/pages/account_page.dart).
- **API·저장·공통 의존성:** AccountPage → AuthController → Logto SDK / GET·DELETE /me. 동기화 성공 후에만 계정 저장소를 해당 계정에 연결한다.
- **남은 검증·결정:** 계정 A/B 전환과 늦은 응답 검증이 있는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-52 · 여행 취향·빠른 조정

- **분류:** 세부 범위 미결정. 목적: 기본 취향을 확인하고 수정.
- **포함 검토:** 기본 취향·설정 이후 입력. **보류·제외 검토:** 세밀한 빠른 조정 전체 필수화.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart).
- **API·저장·공통 의존성:** TravelPreferencesPage → store → remote → /me/preferences → DB. 별도로 composePlanPreferenceContext가 여행 override를 합쳐 일부 soft 필드만 일정에 보낸다.
- **남은 검증·결정:** 기본 취향과 이번 여행 설정을 구분하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-53 · 관심사·여행 스타일

- **분류:** 핵심 후보 · 세부 미결정. 목적: 관심사와 여행 스타일 선택.
- **포함 검토:** 짧은 여행 스타일 질문과 이후 수정. **보류·제외 검토:** 초기 긴 설문.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart).
- **API·저장·공통 의존성:** 상위 빠른 조정 + StylePreferencesPage의 draft → 상위 저장 → 서버 기본값. 일정 soft projection에는 실내외·날씨 민감도만 이 화면에서 연결된다.
- **남은 검증·결정:** 온보딩 질문안과 선택지 의미가 일치하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-54 · 음식 취향·식이 제약

- **분류:** 선택 설정 후보 · 미결정. 목적: 필요한 경우 식이 정보를 보관.
- **포함 검토:** 상세 설정에서 선택 입력. **보류·제외 검토:** 첫 진입 필수 알레르기·식이 설문.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart).
- **API·저장·공통 의존성:** FoodPreferencesPage → 기본 취향 서버 저장 → S-13 카드. 일정 공개 요청에는 음식 종류만 전달하고 알레르기/재료/식이는 의도적으로 제외한다.
- **남은 검증·결정:** 민감 설정의 동의·요청 payload 범위를 제한하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-55 · 이동·접근성

- **분류:** 선택 설정 후보 · 미결정. 목적: 이동과 접근성 제약 설정.
- **포함 검토:** 필요한 이동·접근성 조건. **보류·제외 검토:** 모든 이동 조건을 초기 필수화.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart).
- **API·저장·공통 의존성:** MobilityPreferencesPage → 기본 취향. 공개 일정 요청에는 walkingBand/maxOneWayMinutes를 보내며 필수 접근성 정보를 포함하지 않는다.
- **남은 검증·결정:** 여행별 설정이 기본 접근성 제약을 약화시키지 않는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-56 · 예산·혼잡·운영 조건

- **분류:** 세부 조건 보류 · 화면 미결정. 목적: 가격과 혼잡 정보를 참고.
- **포함 검토:** 장소 정보에서 판단을 돕는 표시 검토. **보류·제외 검토:** 초기 상세 예산·혼잡도 선택.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart).
- **API·저장·공통 의존성:** BudgetPreferencesPage → 저장 모델 → 서버. 일정에는 budgetBand/excludeClosingSoon만 이 설정 묶음에서 전달된다. maxWait/crowd/dayRhythm까지 소비된다고 확대하지 않는다.
- **남은 검증·결정:** 설정 숨김과 데이터·필터 제거를 구분하는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-57 · 도슨트·콘텐츠 언어

- **분류:** 핵심 후보 · 제안. 목적: 도슨트 언어·자동 안내·속도 설정.
- **포함 검토:** 자동 안내 ON/OFF, 보통 1배속과 3단계 속도 방향. **보류·제외 검토:** 임의 배속 수치·말투 선택 확정.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/preferences/presentation/travel_preferences_page.dart).
- **API·저장·공통 의존성:** DocentPreferencesPage → 기본 취향 저장. 앱 언어는 S-03/설정에서 공유하며 별도 콘텐츠 언어 필드는 없다. 설정값의 모든 재생 경로 적용은 추가 검증한다.
- **남은 검증·결정:** 느리게/빠르게 수치와 설정 저장 범위는 무엇인가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-58 · 개인정보·위치

- **분류:** 핵심 후보 · 제안. 목적: 동의와 기기 데이터를 관리.
- **포함 검토:** 위치·개인정보 동의·기기 저장 안내. **보류·제외 검토:** 기기 삭제를 서버 삭제로 오인시키는 동작.
- **코드 대조:** 두 SHA의 대표 파일 내용 동일. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/settings/presentation/pages/privacy_location_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/settings/presentation/pages/privacy_location_page.dart).
- **API·저장·공통 의존성:** PrivacyLocationPage → PrivacySettingsStore / OS 설정. 기기 초기화는 취향·일정·지역·온보딩 저장소를 정리하며 계정 삭제는 S-51에 남긴다.
- **남은 검증·결정:** 동의 철회·기기 삭제·계정 데이터 경계가 명확한가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

### S-59 · 취향 동기화 충돌 해결

- **분류:** 복잡한 UI 보류 · 처리 규칙 미결정. 목적: 동기화 충돌과 실패를 이해.
- **포함 검토:** revision 충돌·실패 상태와 데이터 보존. **보류·제외 검토:** 복잡한 수동 충돌 화면 필수화.
- **코드 대조:** 후보에서 대표 파일 변경. [main 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/9e312bb49af7afd981e5bdbbbb314d7d98ddf0e6/apps/flutter_app/lib/features/preferences/presentation/preference_sync_conflict_page.dart) / [후보 대표 소스](https://github.com/3dt-1st-org/LALA-next/blob/8aa184e375f381fa4de0a97bca82ffa3e59ba836/apps/flutter_app/lib/features/preferences/presentation/preference_sync_conflict_page.dart).
- **API·저장·공통 의존성:** PreferenceSyncConflictPage → store.useAccountPreferences / saveDevicePreferencesToAccount → expectedRevision PUT. Trip override 우선순위와는 별개의 충돌 해결 화면이다.
- **남은 검증·결정:** 자동 동기화 방향과 충돌 발생 시 처리 원칙을 맞췄는가. 현재 두 SHA의 실구동은 미검증.
- **새 자료 대조:** 선별 PDF 쪽수·질문안 항목·일치/충돌·최종 판정·근거는 수령 후 기록.

## 5. 온보딩 질문안 수령 후 작성할 카드

질문 ID / 연결 화면 ID / 사용자 목적 / 원문 질문과 출처 / 필수·선택 / 건너뛰기·거부 / 기본값 / 수정 위치 / 기기·계정 저장 범위 / API 입력 여부 / 재진입 처리 / 결정 상태를 한 카드에 기록한다.

국가와 언어를 동일 값으로 취급하지 않고 언어 수정 경로를 확인한다. 식이·알레르기를 첫 진입 필수 설문으로 옮기지 않는다. 답변 원문이나 개인 프로필을 이 공개 문서에 수집하지 않는다.

## 6. 수령·합의 절차

1. 원본은 기존처럼 비공개 위치에 보존하고 문서명·버전·해시·쪽수만 기록한다.
2. 36개 카드에 새 자료 근거를 연결한다. 신규 화면에는 새 ID를 부여하고 기존 ID를 재사용하지 않는다.
3. 일치 항목은 범위표에 반영하고 충돌은 Q-01~Q-08에 모은다. 회의록의 방향을 화면 세부 확정으로 강화하지 않는다.
4. 개발 담당자가 흐름·API·저장 의존성을 함께 검토하고 PM이 실증 목적을 확인한다.
5. 최종 포함 기능·보류 기능·결정일·주도 역할을 기록하고 03-next-decisions.md와 역할별 인계를 함께 갱신한다.

보류 기능은 현재 삭제·숨김하지 않는다. 후속 실증 빌드의 진입점 제어 항목에만 등록하고, 공통 인증·저장·이동과 연결된 코드는 남긴다. 별도 내부 실험 메뉴나 권한 체계를 지금 새로 만들지 않는다.
