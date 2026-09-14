# 화면·API·데이터 연결과 확인 질문

9/15에 읽은 진희님 API 명세와 찬혜님 9/13 디자인 문구를 `main 765570a2`의 코드와 대조하였다. 이후 발견한 찬혜님 9/15 작업 보고는 아래 별도 표에 반영하였다. 화면 ID는 진희님 문서의 기존 선정 화면 ID다. 찬혜님 새 온보딩 시안과 최종 ID의 일대일 대응은 팀 검토가 필요하다. 아래 “존재”는 코드/DB 구조 확인이며 앱 통합 동작 완료가 아니다.

## 핵심 흐름 연결

모든 상대 API 경로 앞에는 `/api/v1`이 붙는다. 계정 경로는 검증된 Logto 사용자 식별자를 사용한다.

| 사용자 목적·화면 | 현재 API | 데이터·상태 | 이번에 확인한 것·남은 질문 |
|---|---|---|---|
| 첫 진입·계정 연결 S-01/06/50/51 | GET /me | identity.users; 기기 온보딩 상태 | GET도 계정 provision을 수행한다. SDK 로그인과 계정 동기화 성공을 분리 |
| 탈퇴 S-51/58 | DELETE /me | users/deleted_users 및 소유 데이터 FK | DB CASCADE 선언 확인. Logto 삭제·서버/기기 정리는 실행 검증 전 |
| 취향·식당 카드·음성 설정 S-52~55/57 | GET/PUT /me/preferences | profile.user_travel_preferences.payload | soft/hard/locale·revision 존재. 식당 카드는 저장된 조건을 앱에서 표시 |
| 탐색·지도·장소 상세 S-04/05/10/11/12/15 | GET /places | travel.public_places → travel.places; 관련 점수 | 독립 GET /places/{id}는 없다. 목록 DTO로 상세 표시. 저장 ID 재조회 계약은 신규 후보 |
| 저장·목록 S-12/23 | GET /me/saved-places; PUT/DELETE /me/saved-places/{place_id} | planning.user_saved_places + 기기 ID 집합 | 응답은 place_id/saved/changed, 목록은 ID/source/saved_at. 정보 없는 ID 보존 |
| 일정 만들기 S-15/20/22 | POST /plans/daily | 장소·날씨·제한된 soft 입력으로 생성 | 생성 API 자체가 계정 일정 저장 API는 아님. 별도 저장 필요 |
| 일정 저장·복원·지난 일정 S-20/24 | GET /me/plans; GET/PUT/DELETE /me/plans/{plan_date} | planning.user_plans.envelope | 사용자·날짜당 한 일정. 복사는 원본 GET + 다른 날짜 PUT |
| 여행별 설정 S-22 | GET/PUT/DELETE /me/plans/{plan_date}/preferences | planning.trip_preference_overrides | expected_revision·409 계약. 허용 항목만 기본 취향에 적용 |
| 방문 결과 S-25 | GET /me/plans/{plan_date}/visits; PUT …/visits/{slot_period} | planning.slot_visits | planned/visited/not_visited, 미방문 이유·추천 활용 선택. request status 생략은 visited |
| 도슨트 S-30/57 | POST /docents/script; POST /docents/audio | 근거 RAG·조건부 원고 캐시·클라이언트 재생 상태 | 본문 생성, 음성 합성, 실제 재생 성공은 각각 다른 단계 |
| 날씨 S-10/12/14/20 | GET /weather | travel.weather_observations/latest_weather | 실제 관측과 코드가 만드는 합성 forecast를 구분 |
| 일정 재계획 S-14/20 | GET /plans/intervention | 날씨·장소에 따른 대안 계산 | 보류 기능으로 보존. 지금 삭제·숨김을 적용하지 않음 |

근거: [여행·계정 router](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/api/app/routers/v1.py), [TripLibraryRemote](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/flutter_app/lib/features/trip_library/data/trip_library_remote.dart), [저장 목록 화면](https://github.com/3dt-1st-org/LALA-next/blob/765570a21ff5ab5207c627d3659e8051be6dbd98/apps/flutter_app/lib/features/trip_library/presentation/pages/saved_places_page.dart).

## 찬혜님 시안에 답할 데이터 질문

| ID | 시안의 요구 | 현재 구조와의 대응 | 제시할 안·확인할 결정 |
|---|---|---|---|
| U-01 | 국가 선택으로 언어 자동 설정 | 기기에 UI language는 있지만 국가 필드·서버 동기화 계약 없음. API 콘텐츠 정규화는 ko/en | 국가를 언어 프리셋용 기기 선택으로 먼저 다룰지 결정. 국가를 국적·거주지로 해석하지 않음. 서버 확장은 목적이 정해진 뒤 |
| U-02 | 5개 관심 카테고리 중 1~3개 | soft.interests는 최대 5개, 별도의 12개 enum | 화면 5개 묶음과 기존 enum 매핑표를 찬혜·진희가 검토. 화면 선택 개수와 API 허용 최대값을 같다고 가정하지 않음 |
| U-03 | 지금 주변 탐색 / 앞으로의 여행 계획 | 기존 touristType는 localTourist/foreignTourist. 수동 지역 ID는 기기 저장 | 이용 목적과 관광객 유형은 다른 값. 기존 필드를 재해석하지 말고 라우팅 상태·영속화 필요성을 결정 |
| U-04 | 자동 도슨트 기본 ON | API·현재 기본 취향 locale.docent_autoplay는 false | 기본값 충돌 안건. 이번에는 false 유지, 시안의 ON 채택 여부는 팀 결정. ON과 OS 위치 권한은 별도 |
| U-05 | 배속 0.8 / 1.0 / 1.2 | locale.narration_speed 값 집합과 대응 | 저장 계약 재사용. 합성 응답 성공과 실제 배속 적용·재생은 기기 검증 |
| U-06 | 반경 50/100/200m·백그라운드 재생·캐시 삭제 | 취향 payload에 이 필드 없음 | 기기 제어인지 계정 간 동기화가 필요한지 구분. 새 DB 컬럼을 먼저 만들지 않음 |
| U-07 | 위치 권한은 나중에 설정 가능 | 기기 위치 추천 선택과 OS 권한 상태는 별개 | 거부/미설정 때 수동 지역·빈 결과 화면을 연결. DB 동의 이력은 별도 필요성 검토 |
| U-08 | 게스트 저장 후 로그인 연결 | 기기 저장·계정 저장과 합집합 연결 구현 | 로그아웃·A→B 전환·오프라인 해제·재시도·기기 데이터 유지 정책 검증 |
| U-09 | 언어·표시·접근성 설정 | 앱 UI 언어와 API 콘텐츠 언어, locale 음성 설정이 서로 다른 경계 | 요청 언어/실제 제공 언어를 구분. 확대 글씨·접근성은 화면/기기 확인 |

`U-01`~`U-09`는 새 결정 질문 번호이며 기존 화면 ID 또는 구현 이슈 번호가 아니다. 디자인 문구에 적힌 “구현 완료”, “법적 필수” 표현을 이 조사에서 별도 실증·법률 확인한 것으로 인용하지 않는다.

## 추가 확인: 찬혜님 9/15 작업 보고

[9/15 회의 준비](https://app.notion.com/p/9-15-3dba803276a48081aa00c9d91861499b)는 9/13 시안 이후의 **작성자 작업 보고**다. 홈·MY 설정 및 기기 저장 연결을 완료했다고 설명한다. 이 작업의 브랜치·SHA와 테스트 출력은 이번에 인수하지 않았으므로, 위 고정 main 분석이나 이번 DB 대조의 검증 결과로 합치지 않는다.

| 보고된 변경 | 보고서가 밝힌 범위·한계 | DB/API 인계에서 추가 확인할 것 |
|---|---|---|
| 국가·선호 언어·복수 취향·여행 방식·위치·도슨트 설정을 기기에 저장/복원 | 로그인·계정 동기화는 미구현. 일본어·중국어 선호는 저장하되 메인 UI는 영어 fallback | 기기 저장 키·형식·버전과 기존 main 저장소의 이관/공존, U-01~U-03·U-08~U-09 |
| 홈 검색·지역·장소 카드·저장한 장소 표시 | 현재 조회된 장소/지역 목록 검색과 저장 필터. 전국 통합 검색·전국 저장 목록 새 구현 아님 | 조회 범위 밖 저장 ID 복원, 상세 ID 조회 계약, B03~B05·B10 |
| MY의 5개 취향 묶음 최대 3개 선택·홈 큰 분류 정렬 | 세부 취향 추천 엔진은 미완료 | API의 12개 enum 매핑, 복수 선택 보존·빈 선택 처리, U-02 |
| 자동 도슨트 준비 상태와 배속 선호 저장 | 음성 재생 전체 완료 아님. 실제 속도 적용은 재생기 연결 필요 | U-04~U-05 기본값/기기 적용과 M-08의 실제 재생 성공 측정 |
| 반응형·설정 복원·안내창 관련 테스트 수행 보고 | 전체 저장소 테스트·폴더블 힌지 실기기 검증 아님. 마지막 장소 조회 확인 때 로컬 API가 꺼져 재시도 상태 | 작업 SHA·테스트 범위·사용 API 주소 인수, 공용 개발 API 연동·실기기 검증 |

찬혜님 작업에서 국가·설정의 **기기 저장을 연결했다는 보고**와 고정 main에 **서버 동기화 계약이 없다는 사실**은 서로 다른 범위다. 위 U 질문의 현재 구조 칸은 고정 main을 가리킨다. 회의에서는 작업 SHA를 받아 차이표를 확정하고, 사용자 설정을 새 구조로 옮길 때의 보존 규칙부터 맞춘다.

## 진희님 B01~B15와 인계

| 기존 안건 | 데이터 관점의 현재 판단 | 회의 결과로 남길 것 |
|---|---|---|
| B01 취향·여행 맥락 | 기존 취향 API 재사용, 국가/새 목적·언어 동기화는 추가 범위 결정 | 필드 의미·기기/서버 경계 |
| B02 5언어 | 현재 API ko/en; UI 선택 언어와 다름 | requested/resolved language·fallback·음성 범위 |
| B03 지역 카탈로그 | 앱 내부 지역 데이터 존재, 독립 API 없음 | 서버 카탈로그 필요 여부·ID·버전 |
| B04 검색·추천 | 주변/bounds 조회·일정 soft 조건 있음 | 검색·정렬·페이지·미확인 값 계약 |
| B05 장소 상세 | 독립 ID 조회 없음 | 저장 ID 정보 누락·삭제/통합 상태 제공 범위 |
| B06 식당 카드 | 취향 구조 존재 | 원본 의도·번역·발음/음성·큰 글씨 검증 |
| B07 날씨 | 관측과 합성 forecast 공존 | 사실/추정·단위·신선도 표시 |
| B08 일정 | 날짜당 1개, envelope 내부 엄격 검증 없음 | 복수 일정 필요 여부·수정 보존·날짜 기준 |
| B09 동선 | 추정 이동시간·authority 구분 존재 | 실제 경로 요구·재정렬 후 재계산 |
| B10 저장 장소 | PK로 현재 집합 유지, 해제하면 행 삭제 | 반복 요청·오프라인 삭제·정보 없는 장소 |
| B11 재사용 | GET/PUT 조합, 대상 날짜 덮어쓰기 가능 | 원본 보존·대상 충돌·장소/날씨 갱신 |
| B12 방문 | 결과·이유·추천 활용 필드 실제 DB에 존재 | 미정↔planned, status 생략·반복 확인·시각 의미 |
| B13 동의·탈퇴 | 계정 소유 FK·기기 위치 선택 있음 | 동의 이력 추가 필요·기기/계정 삭제·보관 범위 |
| B14 동기화 | 취향/override revision; 나머지 쓰기는 다른 정책 | 계정 전환·미전송 작업·충돌·삭제 tombstone 필요성 |
| B15 도슨트 | 근거·본문·음성 생성 경계 존재 | 인용·언어 fallback·본문 성공/음성 실패·실제 재생 |

신규 API·DB 필드·trip ID를 이 표만으로 확정하지 않는다. 각 안건은 `재사용 / 보강·검증 / 신규 후보 / 후순위`를 회의에서 선택한다.
