# LALA Stitch vs LALA-next 화면 비교 보고서 v2

작성일: 2026-09-03  
성격: 기능·UI 대응 및 검증 상태 업데이트  
비교 기준: Stitch 통합 프로토타입과 LALA-next canonical 36화면  
LALA-next 앱 코드 기준: `651b5f245a2eea88acea479f02ff05dd6097fb93`  
검증 빌드 기준: `71c22daa7f1afcc2d5a6d396258a5c6a69fc491c`

## 1. 요약 판정

이전 비교 보고서에서 미완료였던 36개 canonical 화면의 진입점, 상태, 실제
서비스 바인딩은 현재 비운영 integration 브랜치에 모두 구현됐다. Stitch 통합본은
여전히 시각·상호작용 아이디어를 비교하는 프로토타입이고, LALA-next가 실제 제품
구현의 기준이다.

- 논리 화면 구현: **36/36**
- 누락된 canonical ID: **0개**
- 최종 통합 PR: `#171`, `#172`, `#173`, `#174` 모두 MERGED
- 전체 자동 검증: Flutter 832 tests, Dart client 39 tests, API tests, Ruff,
  formatting, pre-commit 및 detect-secrets 통과
- exact-head iPhone 17 Pro 실검증: S-02, S-03, S-04, S-05, S-06, S-10,
  S-40, S-42의 비로그인 gate, S-50, S-58
- exact-head 웹 검증: 온보딩, NAVER 지도 surface, 전역 내비게이션, 내 정보의
  모바일·데스크톱 반응형
- 운영 승인이 필요한 상태: 실제 Logto 계정 쓰기, 채팅, production DB 적용,
  유료 AI·음성, integration에서 main으로의 승격

`71c22da`와 squash merge 결과 `651b5f2`의 Git tree는
`f986680d6d54bdad2339721151c9c40f15dbed36`으로 동일하다. 따라서 앱 실구동
증거는 현재 integration에 병합된 제품 tree와 일치한다. 이 문서 추가는 제품 코드가
아닌 문서 변경이다.

## 2. 비교 대상과 판정 규칙

### Stitch 기준

- 기능 입력: 로컬 전용 `output/local/lala-stitch-functional-screen-brief-20260903.md`
- 통합 프로토타입: 로컬 전용 `output/local/lala-stitch-integrated-app-20260903/`
- 이전 보고서: 로컬 전용
  `output/local/lala-stitch-ai-studio-integration-review-20260903.md`
- Stitch의 장소, 날씨, 출처, 계정, Local Signals, 채팅 데이터는 예시다.
  실제 서비스 증거로 사용하지 않는다.

### LALA-next 기준

- 기능 기준: `docs/product/lala-service-functional-spec.md`
- 구현 대조표: `docs/product/lala-canonical-screen-reconciliation.md`
- 라우팅: `apps/flutter_app/lib/core/routing/lala_route_paths.dart` 및
  `apps/flutter_app/lib/core/routing/lala_router.dart`
- 실행 기준: 비운영 `integration/canonical-screen-completion-20260903`
- `main`은 `e13216cdabd467b9c7b5ec0a0e475a8005d1a152`로 유지됐으며, 이 비교는
  production 배포 완료를 뜻하지 않는다.

### 표의 기호

| 기호 | 의미 |
| --- | --- |
| `FULL` | Stitch가 의도한 핵심 기능이 실제 상태·데이터 계약과 함께 구현됨 |
| `ADAPTED` | 기능은 구현됐으나 별도 route 대신 sheet/nested page 등 LALA 구조로 표현됨 |
| `GATED` | 화면과 계약은 구현됐지만 인증·유료 호출·운영 데이터 등 명시 gate 뒤의 상태가 남음 |
| `E` | 병합된 앱 tree와 동일한 exact-head에서 iPhone 또는 웹으로 확인 |
| `P` | 해당 phase 또는 이전 빌드 증거가 있고 전체 자동 검증을 통과했으나 최종 head 개별 재생은 안 함 |
| `A` | 코드와 자동 검증만 확인; 해당 실상태를 기기에서 만들지 않음 |

이 기호는 시각적 픽셀 복제율이 아니라 기능·상태·근거성의 대응 정도다.

## 3. 이전 보고서 대비 변화

| 항목 | 이전 판정 | v2 판정 |
| --- | --- | --- |
| 36개 canonical 화면 | route parity 미완료 | 36개 모두 도달 가능; route, focused sheet, nested page로 의도에 맞게 구현 |
| 지도 | 점선 캔버스와 고정 예시 핀 | 실제 NAVER Dynamic Map, API 장소, 핀·클러스터·선택 동기화 |
| 검색·상세 | 예시 데이터와 로컬 상태 | canonical place ID와 API 검색·상세 흐름 연결 |
| 일정 | 모달 안의 4슬롯 예시 | 서버 호환 4슬롯, 상황 변화 비교, 여행별 override, 방문 확인 연결 |
| Local Signals | 고정 mention 수치 | governed aggregate 및 source-safe 상세; 데이터 부족은 정직한 상태로 표시 |
| 계정 | 가짜 프로필과 로컬 동기화 | Logto SDK와 `/api/v1/me` 계약; 성공·동기화·오류 상태 분리 |
| 개인화 | React 메모리 상태 | device-first 저장, 계정 동기화, 여행별 override 및 충돌 해결 |
| 커뮤니티·채팅 | 가짜 실시간 대화 | 공개 읽기와 Logto-gated 쓰기/채팅; 로그아웃 시 private state 폐기 |
| 실구동 | 모바일 브라우저 prototype만 | iPhone 17 Pro exact-tree 설치·실제 탭 및 모바일·데스크톱 웹 검증 |
| 사실성 | 예시를 실시간처럼 보일 위험 | unavailable, empty, stale, auth-required를 실제 데이터와 분리 |

## 4. Flow 1: 시작과 진입

| ID | Stitch 의도 | LALA-next 현재 대응 | 판정 | 검증·남은 차이 |
| --- | --- | --- | --- | --- |
| S-01 앱 시작·복원 | 스플래시, 설정 복원, 실패 복구 | `OnboardingSplashPage`가 저장 상태를 복원하고 안전한 다음 route를 결정 | `FULL/A` | 자동 테스트 대상. 최종 캡처는 복원 후 S-02부터 시작해 splash frame은 별도 보존하지 않음 |
| S-02 여행 맥락 | 국내 여행·해외 방문·생활권 탐색 선택 | 1/3 단계에서 맥락을 저장하고 이후 추천 기본값에 전달 | `FULL/E` | iPhone 17 Pro에서 실제 선택·다음 이동 확인 |
| S-03 언어 | KO/EN/JA/zh-Hans/zh-Hant 선택 | 2/3 독립 화면과 5개 locale 선택, 선택 언어 상태 유지 | `FULL/E` | 다섯 선택지와 선택 상태를 exact-head에서 확인; 모든 하위 콘텐츠의 번역 완전성은 별도 locale QA |
| S-04 위치 설정 | 현재 위치, 직접 선택, 나중에 하기 | 권한 요청·거부 회복·직접 지역·나중에 진행을 모두 제공 | `FULL/E` | NAVER map preview와 세 행동을 실제 화면에서 확인 |
| S-05 지역 직접 선택 | 검색, 시·도/시군구, 최근 지역 | 229개 전국 지역 selector, 검색·빠른 선택·공통 region context | `FULL/E` | 실제 sheet 열기와 지역 목록 확인 |
| S-06 계정 연결 | Google/다른 로그인 또는 guest | Logto 시작과 guest 진행을 분리하고 탐색은 비로그인 허용 | `GATED/E` | guest 진입은 확인. 실제 Google 로그인과 `/me` 동기화 완료 상태는 실계정 gate |

### Flow 판정

Stitch가 한 화면에 많이 묶었던 언어·위치·계정을 LALA-next는 3단계로 분리했다.
화면 수는 늘지만 한 단계의 판단 부담이 낮고, 위치나 로그인 실패가 탐색 진입을 막지
않는다는 점에서 방문객 접근성과 회복성이 더 높다.

## 5. Flow 2: 발견과 방문 준비

| ID | Stitch 의도 | LALA-next 현재 대응 | 판정 | 검증·남은 차이 |
| --- | --- | --- | --- | --- |
| S-10 지도 탐색 | 지도 핀, 카테고리, 추천 rail | 실제 NAVER map, API 장소, category pin, cluster, 선택·rail 동기화, 오류 회복 | `FULL/E` | iPhone에서 실데이터 장소·날씨·핀 확인. 웹 localhost API는 production CORS를 유지해 데이터 호출이 차단됨 |
| S-11 검색 | 지역 문맥, 정렬·필터, 장소 선택 | API 검색, 선택 지역, 필터, canonical ID로 지도·상세 연결 | `FULL/P` | phase 증거와 테스트 통과; 최종 head에서 검색 전체 flow는 개별 재캡처하지 않음 |
| S-12 장소 상세 | 이미지, 근거, 저장, 일정·도슨트·소통 CTA | `PlaceDetailPage`가 canonical API 장소와 추천 근거 및 각 후속 route를 연결 | `FULL/P` | 기능은 실제 binding. Stitch보다 장식은 절제되고 source·unavailable 구분을 우선 |
| S-13 음식점 방문 도움 | 알레르기·주문 요청을 큰 글씨로 제시 | 저장된 식이 제약을 사용한 식당 소통 sheet, 큰 글씨·복사·안전 고지 | `ADAPTED/P` | 별도 top-level route가 아닌 음식점 상세의 focused sheet. 실매장 사용성·번역 검수는 후속 현장 QA |
| S-14 날씨·대기질 | 현재 날씨, PM, 일정 영향과 대안 | 실제 weather/AQ 응답, observed time, 오류·stale, 일정 개입 진입 | `ADAPTED/P` | map/detail의 focused sheet. 유효 데이터가 없을 때 예시값을 만들지 않음 |
| S-15 동선·투어 | 후보 순서, 이동시간, 일정 초안 | 선택된 실제 장소 기반 `TourSheetContent`, 순서·상태·plan 연결 | `ADAPTED/P` | sheet 표현. 정밀 경로가 아닌 추정 정보의 의미를 구분 |

### Flow 판정

Stitch의 가장 큰 시각 장점은 장소 상세 안에서 행동을 빠르게 발견하는 구조다.
LALA-next는 그 구조를 유지하면서 지도와 장소를 예시가 아닌 동일 canonical ID로
연결했다. 다음 시각 보정에서는 S-12의 추천 이유·출처·신선도 계층과 S-13 진입
가시성을 우선 다듬을 가치가 있다.

## 6. Flow 3: 일정과 회복

| ID | Stitch 의도 | LALA-next 현재 대응 | 판정 | 검증·남은 차이 |
| --- | --- | --- | --- | --- |
| S-20 하루 일정 | 오전·점심·오후·저녁과 이동 연결 | server-compatible 4슬롯 일정과 장소·도슨트·방문 행동 | `FULL/P` | 전체 suite와 phase 증거. 최종 head 일대일 캡처는 안 함 |
| S-21 상황 변화 비교 | 기존 장소와 날씨·대기질 대안을 비교·적용 | 실제 intervention 전후안을 독립 route에서 비교하고 선택 | `FULL/P` | 적용 전 비교 상태가 구현됨; production mutation 없이 검증 |
| S-22 이번 여행 설정 | 동행·속도·이동·안전 조건의 임시 override | 날짜별 `TripPreferenceOverride`와 server contract, 기본 취향과 우선순위 분리 | `FULL/P` | 코드·API·migration 계약과 phase 검증 완료; production migration apply는 별도 승인 |
| S-23 저장한 장소 | 저장 목록, 상태 변화, 오늘 일정 추가 | device-first 저장 ID와 계정 동기화 경로, 상세·일정 연결 | `FULL/P` | guest local 흐름과 자동 테스트; account cross-device 상태는 인증 gate |
| S-24 지난 일정 | 과거 여행 조회·재사용 | 계정 plan history와 현재 조건을 구분한 `PastTripsPage` | `GATED/P` | 화면·계약 구현. 실제 계정 history는 실계정 데이터가 있어야 검증 가능 |
| S-25 방문 확인 | 실제 방문 여부와 제한된 feedback | 일정 slot의 bounded visit confirmation route와 저장 계약 | `GATED/A` | 테스트로 계약 확인. 실제 계정 쓰기와 전환 측정은 production write gate |

### Flow 판정

Stitch의 이동 연결선과 대체 제안은 여전히 좋은 시각 참고다. LALA-next는 여기에
실제 전후안, 여행별 override 우선순위, 저장·방문 계약을 붙였다. 남은 차이는 기능
부재가 아니라 최종 head에서 S-20~S-25를 한 번에 재생한 영상·캡처 증거다.

## 7. Flow 4: 도슨트와 로컬 정보

| ID | Stitch 의도 | LALA-next 현재 대응 | 판정 | 검증·남은 차이 |
| --- | --- | --- | --- | --- |
| S-30 장소 도슨트 | 음성 player, script, 이동 제어 | RAG text를 기본 제공하고 음성은 enablement·유료 gate에 따라 분리 | `GATED/P` | text/read-only는 구현. 유료 음성 호출과 전 장소 품질 QA는 별도 운영 gate |
| S-31 Local Signals | 자연 언급과 광고 의심을 구분한 집계 탐색 | governed public aggregates, 표본·신선도·데이터 부족 상태 | `FULL/P` | mock count를 정상 경로에서 쓰지 않음; 운영 데이터량에 따라 honest empty 가능 |
| S-32 Signal 상세·참여 | 표본·관측 메타데이터, 장소·일정 연결 | source-safe detail, canonical place 연결, moderation-aware action | `FULL/P` | phase 구현·테스트 완료. 원문·작성자·raw URL은 의도적으로 공개하지 않음 |

### Flow 판정

Stitch는 수치가 풍부해 보이지만 예시값이었다. LALA-next는 정보량이 적더라도 실제
집계가 없으면 준비 중·없음으로 표시한다. 이는 시각적 밀도보다 근거성을 우선한
의도적 차이다.

## 8. Flow 5: 커뮤니티와 채팅

| ID | Stitch 의도 | LALA-next 현재 대응 | 판정 | 검증·남은 차이 |
| --- | --- | --- | --- | --- |
| S-40 커뮤니티 피드 | 팁·질문 중심 사용자 대화 | Local Signals와 명확히 분리된 public feed, empty/error/retry, 글쓰기 gate | `FULL/E` | iPhone에서 실제 public empty와 신뢰 고지 확인 |
| S-41 게시글 상세 | 본문, 댓글, 반응, 신고 | public read와 authenticated reaction/comment 경계를 구현 | `GATED/A` | 운영 글을 만들지 않았으므로 실제 detail data는 미재생 |
| S-42 글 작성 | category, place context, publish | Logto account가 있어야 publish하며 로그인 중단 후 draft 보존 | `GATED/E` | 비로그인 write gate와 draft-preservation 문구 exact-head 확인; 실제 publish는 미실행 |
| S-43 채팅방 목록 | unread, 상대·가이드별 thread | authenticated membership 기반 room list, loading/empty/error | `GATED/A` | 실제 회원 room 데이터 미사용. 로그아웃 시 private list 즉시 폐기 테스트 통과 |
| S-44 채팅방 | REST/WebSocket 메시지, 전송·재시도 | authenticated REST/WebSocket flow와 late-response suppression | `GATED/A` | actual private chat은 미실행. logout 뒤 message/user state가 남지 않는 회귀 테스트 통과 |

### Flow 판정

Stitch의 채팅은 풍부하지만 가짜 사용자와 로컬 메모리였다. LALA-next는 비어 있어도
실제 public 상태를 보여 주고, private UI는 로그인 직후만 허용한다. 실제 콘텐츠를
삽입하지 않은 것은 미구현이 아니라 데이터·개인정보 경계를 지킨 결과다.

## 9. Flow 6: 계정과 개인화

| ID | Stitch 의도 | LALA-next 현재 대응 | 판정 | 검증·남은 차이 |
| --- | --- | --- | --- | --- |
| S-50 설정 허브 | 계정, 취향, 저장, 지난 일정, 언어·위치, 커뮤니티 | 다섯 번째 `내 정보` tab과 모든 하위 기능의 실제 entry | `FULL/E` | iPhone 및 웹 mobile/desktop에서 진입·스크롤 확인 |
| S-51 계정 관리 | 프로필, sync 상태, 재시도, logout | Logto와 `/api/v1/me` 상태, guest/account/error/logout 분리 | `GATED/A` | wiring·tests 완료. 실제 Google 로그인 후 account sync는 실계정 검증 gate |
| S-52 취향 요약 | 기본값과 여행 override 차이, 빠른 조정 | device-first/account-synced defaults와 여행별 적용 진입 | `FULL/P` | phase 검증 완료; profile에서 entry 확인 |
| S-53 관심사·스타일 | 최대 관심사, 여행 스타일, 동행·속도 | `StylePreferencesPage`에서 interests, pace, style과 저장 | `FULL/P` | nested page로 구현; Stitch의 컬러 chip을 절제해 사용 |
| S-54 음식·식이 제약 | 요리·맵기·예산과 알레르기·식단 | preference와 hard safety constraint를 분리하고 S-13 카드에 연결 | `FULL/P` | 자동·phase 검증. 번역과 실제 매장 전달은 현장 QA 권장 |
| S-55 이동·접근성 | 도보, 교통, 환승, 휠체어·유아차 | `MobilityPreferencesPage`와 추천 filtering 계약 | `FULL/P` | 미검증 접근성 정보를 사실처럼 표시하지 않음 |
| S-56 예산·혼잡·운영 조건 | 일일·식사 예산, 대기, 활동 시간, 휴무 규칙 | `BudgetPreferencesPage`에서 예산·혼잡·대기·운영 조건 저장 | `FULL/P` | 기능 대응. 추천 결과에 반영되는 production 데이터 QA는 후속 |
| S-57 도슨트·콘텐츠 언어 | locale, 설명 깊이, 자동재생, 속도 | `DocentPreferencesPage`에서 언어·깊이·playback 설정 | `GATED/P` | 설정은 구현. 실제 유료 음성 preview는 호출하지 않음 |
| S-58 개인정보·위치 | 앱 동의, OS 권한, 동기화·삭제 안내 | persisted app-level consent, OS 설정 분리, manual region, guest data clear | `FULL/E` | exact-head 화면·재실행 persistence·OCR 확인 |
| S-59 취향 동기화 충돌 | 기기값·계정값 비교와 명시 선택 | `PreferenceSyncConflictPage`에서 양쪽 요약과 선택적 해결 | `ADAPTED/A` | 강제로 가짜 conflict를 만들지 않음; reducer/store tests로 검증 |

### Flow 판정

Stitch가 제안한 개인화 분류는 대부분 유지됐고, LALA-next는 이를 실제 저장 우선순위와
계정 경계에 연결했다. 시각적으로는 S-53~S-57이 Stitch보다 조용하고 실무적인
형태다. 컬러 chip을 늘릴 때도 안전 조건과 일반 취향의 우선순위가 색상만으로
구분되지 않게 해야 한다.

## 10. 시각·UX 비교

### LALA-next가 앞선 부분

1. 실제 지도와 데이터 상태: NAVER map, API 장소, 오류·위치 회복이 한 화면에서
   실제로 동작한다.
2. 일관된 앱 구조: 검색·지도·일정·로컬 신호·내 정보의 5개 목적지가 모든 주요
   화면에서 같은 의미를 가진다.
3. 사실성: 가짜 계정, 가짜 실시간 수치, 가짜 채팅을 정상 상태로 사용하지 않는다.
4. 인증 안전성: 로그인 전 공개 읽기와 로그인 후 쓰기를 구분하고, 로그아웃 시
   private state 및 늦게 도착한 응답을 폐기한다.
5. 위치 회복: OS 권한과 앱 선택을 분리하고 전국 직접 선택을 항상 제공한다.

### Stitch에서 계속 참고할 부분

1. S-12: 대표 이미지 아래 핵심 행동과 추천 근거를 더 빠르게 스캔하는 계층.
2. S-20/S-21: 슬롯 사이 이동선과 원안·대안의 시각적 비교.
3. S-30: script와 playback 상태를 한눈에 이해하는 player 구성.
4. S-53~S-57: 긴 설정을 압축하는 색상 chip과 즉시 보이는 선택 요약.
5. S-13: 식당 직원에게 보여 주는 큰 글씨 mode의 첫 화면 도달성.

### 가져오면 안 되는 부분

- 고정된 mention 수, 혼잡도, 신선도, 평점, 날씨를 실제값처럼 표시
- 사용자 입력이 아닌 심각도나 생명 위험 표현을 알레르기 카드에 추가
- 가짜 이메일·프로필·동기화 완료·채팅 메시지
- 장소와 일치하지 않거나 권리가 검증되지 않은 원격 이미지
- Local Signals와 사용자 커뮤니티를 같은 신뢰 등급으로 표현
- mock/demo를 실제 데이터가 없는 정상 경로의 대체물로 사용

## 11. 실구동 및 증거

### iPhone 17 Pro

- 기기: iPhone 17 Pro PR157, iOS 26.5 Simulator
- build: 기존 build 삭제 후 approved build wrapper로 새 simulator debug build
- install: 기존 bundle uninstall 후 새 `Runner.app` install
- 입력: 실제 simulator tap; fixture, VM state injection, demo data 미사용
- 관찰: 온보딩, 229개 지역 selector, 실제 NAVER map 및 API 장소·날씨,
  내 정보, community empty, write auth gate, 개인정보·위치
- exact `71c22da` 캡처: 11개, SHA-256 모두 상이
- 로컬 증거 경로:
  `/tmp/lala-canonical-screen-audit-20260903/output/local/runtime-evidence/pr174-iphone17pro/exact-71c22da/`

### 웹

- build: iOS 확인 뒤 기존 build를 다시 삭제하고 exact head로 web build
- viewport: 393 x 852 및 1440 x 900
- 관찰: 온보딩 클릭, NAVER iframe, 5-tab navigation, My Info 반응형
- localhost에서 production API 호출은 기존 CORS 정책 때문에 실패한다. 보안을
  약화하지 않았으며, 실데이터 acceptance는 iPhone 결과를 사용했다.
- 로컬 증거 경로:
  `/tmp/lala-canonical-screen-audit-20260903/output/local/runtime-evidence/pr174-web/exact-71c22da/`

### 자동 검증

| 검증 | 결과 |
| --- | --- |
| Flutter analyze | PASS |
| Flutter tests | PASS, 832 tests |
| community auth/logout focused tests | PASS, 3 tests |
| Dart client tests | PASS, 39 tests |
| API tests and safety contracts | PASS |
| Ruff check/format | PASS |
| pre-commit all files and detect-secrets | PASS |
| GitHub CI 3 jobs | PASS |
| `git diff --check` | PASS |

## 12. 정직한 완료 경계

### 완료

- 36개 canonical 화면의 route/sheet/nested-page 표현
- 화면 간 canonical ID, region, selected place, plan, preference state 전달
- 실제 NAVER 지도와 read API 정상 경로
- 게스트 탐색, location denial recovery, manual nationwide region
- 기본 취향, 여행별 override, 저장 장소, 지난 일정, sync conflict UI
- governed Local Signals와 사용자 커뮤니티의 신뢰 경계
- Logto-gated community writes/chat 및 logout privacy regression
- exact merged-tree 자동 검증과 대표 iPhone/web 실구동

### 구현됐지만 외부 상태 때문에 아직 끝까지 누르지 않은 것

- 실제 Google/Logto 로그인 후 `/api/v1/me` 동기화
- authenticated post/comment/reaction/chat 및 account history
- production DB migration/apply와 실제 visit write
- 유료 도슨트·음성 호출과 전체 장소 수동 품질 QA
- 36개 화면 각각의 final exact-head screenshot replay
- Android 최신 integration 실구동

이 목록은 누락 화면 목록이 아니다. 코드가 존재해도 실제 계정, 운영 데이터,
비용 또는 production mutation이 필요한 상태는 별도의 승인·검증 단계로 남긴 것이다.

## 13. 다음 시각 개선 우선순위

1. S-12 장소 상세: 추천 이유·출처·신선도와 세 핵심 행동의 first viewport 밀도 조정.
2. S-20/S-21 일정: 슬롯 이동선, 원안·대안 비교, 적용·되돌리기의 시각 일관성.
3. S-13 음식점 도움: 음식점 상세에서 한 번의 탭으로 큰 글씨 카드에 도달하도록 보정.
4. S-30 도슨트: text-first 기본 상태와 음성 disabled/available 상태의 player 완성도.
5. S-53~S-57 개인화: 안전 조건을 훼손하지 않는 범위에서 chip·요약·저장 feedback 강화.
6. S-40~S-44: 실제 계정·운영 데이터가 준비되면 empty, loaded, error, logout을 동일
   exact head에서 다시 캡처.

시각 개선은 화면 존재 여부를 다시 늘리는 작업이 아니라, 이미 구현된 흐름의 정보
우선순위와 표현 완성도를 높이는 다음 단계다.
