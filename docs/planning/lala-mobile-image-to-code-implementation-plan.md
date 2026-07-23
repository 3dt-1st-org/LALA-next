# LALA 모바일 UI 리디자인 — image-to-code 구현 계획 (수정본)

> 상태: 활성 구현 계획. 초안(`~/.codex/attachments/.../pasted-text.txt`)을 대체한다.
> 작업 브랜치: `geondongkim/lala-mobile-image-to-code` (독립 워크트리, main/dev 미병합).

## 0. 시각 진실의 원천 (Source of truth)

**시각 기준: 선택된 참조 이미지 한 장**
`/Users/geondongkim/.codex/generated_images/019eb5c9-.../exec-f201cd1d-....png`

이미지 자체(6화면: 온보딩 3 + 지도 + 검색 + 일정)가 시각 SSOT다. **OCR/비전 툴이 읽어낸 한국어 문구는 환각이 심해(예: "위쿡인 관광객", "추천 주요을", "맛소문") 신뢰하지 않는다** — 이는 안드로이드 기기 캡쳐 검수 규칙(`android-device-capture-method`)과 동일한 교훈. 따라서:

- **레이아웃/구조/밀도/계층/색/형태**는 이미지 분석(신뢰 구간)을 따른다.
- **문구(copy)**는 이미지 분석이 아니라, (a) 작업 지시의 명시적 수용 기준(1~9번) + (b) 기존 코드의 진실된 lalaCopy 문자열을 소스로 정한다. 새 문구를 지어내지 않는다.

참조 이미지 구조 요약(비전 구조 분석, 텍스트 제외):
1. 온보딩 1 — 2개 선택 행 + 하단 풀폭 버튼, 상단 1/3 진행 세그먼트.
2. 온보딩 2 — 2개 언어 행(왼쪽 KO/EN 코드 + 오른쪽 텍스트, 선택 시 체크), 하단 버튼, 2/3.
3. 온보딩 3 — 상단 절반 지도 미리보기 + 하단 타이틀/본문 + 2개 버튼(위 primary, 아래 outline), 3/3.
4. 지도 — 상단 카테고리 칩(+설정), 중단 얇은 사진 레일, 하단 바텀시트(도슨트 미리보기), **우하단 세로 컨트롤 스택**, 개별 다색 핀(클러스터 아님).
5. 검색 — 검색바 + 카테고리 칩 + **결과 카드형 스켈레톤 블록들**(빈 스피너 아님).
6. 일정 — 타이틀 + 진행 표시 + **단일 로딩 카드**, 하단 탭 3개.

## 1. 초안 계획 문제 9종 — 명시적 정정

아래 각 항목은 초안이 틀렸거나 과했던 부분을 바로잡는다.

### 1.1 이미지를 SSOT로 + 6화면별 수용 기준 (초안 문제 1 시정)
초안은 "목업 이미지 OCR 불가 → 코드 탐색을 소스로 사용"이라며 이미지를 포기했다. **틀림.** 이미지가 SSOT다. 코드 탐색은 구현 사실 확인용이지 디자인 결정의 원천이 아니다.

**화면별 수용 기준(acceptance criteria):**

- **온보딩 1 (start)**: (a) 선택 행 2개 표시; (b) 탭해도 자동 이동 없음(선택만); (c) 명시적 "다음" 액션 존재; (d) 진행 표시 `1/3`; (e) 행 반경 8, 정상 안드로이드 폭에서 타이틀/본문 줄바꿈 없음.
- **온보딩 2 (language)**: (a) 국기 이모지 영구 제거; (b) KO/EN 텍스트 배지; (c) 선택 행만 강조(단일 테두리/체크); (d) 진행 `2/3`.
- **온보딩 3 (location)**: (a) 실제 카카오 타일 지도 미리보기 존재(키 없으면 기존 명시적 fallback 유지); (b) "현재 위치 사용" + "지역 직접 선택" 둘 다 첫 렌더부터 노출; (c) 진행 `3/3`; (d) 타이틀 30sp 이하 한 줄.
- **지도**: (a) 상단=카테고리 칩+설정; (b) 중단=얇은 사진 레일; (c) 하단=선택 장소 바텀시트(도슨트 미리보기); (d) 컨트롤=**우하단 세로 스택**(대형 흑색 원형 ❌); (e) 마커=개별 다색 핀(상세 줌에서 클러스터 ❌); (f) 이중 테두리 ❌, 반복 점수/근거 ❌, "꿈"/로봇/이모지 ❌.
- **검색**: (a) 로딩=결과 카드형 스켈레톤 3개(빈 스피너 ❌); (b) 최근/인기/모의 장소 ❌(실제 이력만, 없으면 진실된 빈 안내).
- **일정**: (a) 타이틀 "오늘 일정"; (b) 로딩 카드 **1개만**(중복 ❌); (c) 타이머 기반 가짜 단계 ❌, 진실된 중립 준비 상태 + 접근 가능한 진행 표시; (d) 재시도는 실패 화면에만.
- **하단 탭**: 라벨 "검색 / 지도 / 일정", 컴팩트 높이, 영문 지원.

### 1.2 온보딩 (초안 문제 2 시정 및 강화)
초안은 "4세그먼트 유지"를 제안했으나 **3 콘텐츠 단계(1/3~3/3)** 로 바꾼다(지시가 명시). 스플래시는 콘텐츠 단계에서 제외(브랜드 인트로). start_page는 탭 자동 이동을 없애고 **명시적 다음 액션** 추가(초안도 언급했으나 명시 강제). language_page는 **KO/EN 텍스트 배지**(초안은 "또는 번역 아이콘"이라 모호했음 → 배지로 확정). location은 "현재 위치 사용"+"지역 직접 선택"을 **첫 렌더부터 상시**(초안은 조건부→상시로 제안, 맞음).

### 1.3 위치 지도 미리보기 (초안 문제 3 시정)
초안은 "buildKakaoMapView에 interactive:false 옵션 추가(또는 별도 위젯)"라 모호했다. **별도 KakaoMapPreview 래퍼**로 확정: 기존 조건부 import 시스템(buildKakaoMapView)을 places:[], 콜백 미전달로 재사용하고 IgnorePointer+ClipRRect로 감싼다. **새 가짜 지도 드로잉 ❌**, **플랫폼 WebView 전용 회귀 ❌**. 키 누락 시 기존 `KakaoMapFallbackView` 명시 메시지 유지.

### 1.4 일정 로딩 (초안 문제 4 시정 — 핵심 정정)
초안은 "경과시간 추정 타이머로 단계 전환(장소 고르는 중→동선 정리 중→날씨 반영 중), 5초 초과 시 취소/재시도"를 제안했다. **틀림.** 이는 타이머 기반 클라이언트 추정을 백엔드 실제 진행으로 위장하는 것이다(지시 4번이 명시적으로 금지). 대신: **단일 카드 + 진실된 중립 준비 상태 + 접근 가능한 비율 미정(indeterminate) 진행 바 + Semantics**. 단계 문구 없음. 재시도는 실패 뷰에만(이미 `_PlanErrorView`에 존재). "가짜 취소" 액션 ❌.

### 1.5 검색 스켈레톤 + 빈 상태 (초안 문제 5 시정)
초안은 "최근 검색/가까운 지역/인기 장소"를 제안했다. **틀림(부분).** 인기/가까운/모의 장소는 지시 5번이 금지. 실제 쿼리 이력만 렌더(데이터 있을 때), 없으면 진실된 빈 안내(기존 EmptyPlaceState 재사용). 로딩은 결과 카드형 스켈레톤 3개. SkeletonBox는 재사용 위젯으로 신규(쉬머 전무).

### 1.6 지도 마커/클러스터링 (초안 문제 6 시정 — 코드 탐색으로 입증)
초안은 "개별 마커 우선 유지, 클러스터는 줌 아웃 시"라 모호했다. **코드 탐색으로 입증된 사실:** `clusterMapPlacesForMap`의 임계치는 `shouldUseClusters = places.length >= 80 && mapLevel >= 10`(map_helpers.dart:65). 즉:
- 상세 줌(level < 10): 장소 수와 무관하게 **항상 개별 마커**.
- 저상세(level ≥ 10) + 80곳 이상일 때만 클러스터(동일 버킷 3곳 이상).

이미지/지시 요구("상세 줌에서는 개별 핀, 클러스터는 실제 중첩/저상세 그룹만")를 **이미 만족**. 따라서 **임계치 변경 ❌** (지시가 "if code inspection proves it" — 입증 결과 변경 불필요). 대신 불변량을 단위 테스트로 고정하고 QA 문서에 근거를 기록.

### 1.7 지도 계층/컨트롤/제거항목 (초안 문제 7 시정)
3-레이어(상단 칩+설정 / 얇은 사진 레일 / 하단 바텀시트+도슨트)는 **이미 dashboard.dart Stack에 존재**. 초안이 "3단계화"를 새로 만드는 것처럼 썼으나 실제는 정돈/컴팩트화가 과제. 구체적 제거/수정:
- **대형 원형 컨트롤 제거**: `auto_docent_fab.dart`(74px) → 48px; `map_fab.dart`(46px 흑색) → 44px 중성/primary, 흑색 배경 제거.
- **컨트롤 위치**: `floating_map_controls.dart` Row → **Column(세로)**; `dashboard.dart`에서 중앙 풀폭 → **우하단(right:16)**.
- **이중 테두리 제거**: `map_rail_place_card.dart` 선택 시 외곽 category색 + 내측 alpha0.18 이중 보더 → **단일 category색 2px 보더**.
- **"꿈"/로봇/이모지/반복 텍스트**: 현재 코드에 해당 항목 없음(확인 완료) → 유지.
- **도슨트 결합**: 도슨트는 바텀시트 내 `DockDocentPreview`에 이미 결합되어 있음(플로팅 아님) → 유지.

### 1.8 용어 통일 (초안 문제 8 시정)
- 하단 탭 라벨: `'플랜'` → `'일정'` (lala_bottom_nav_bar.dart:40). 영문은 OnboardingState.language SSOT로 'Search'/'Map'/'Plan'.
- 페이지 타이틀: `'오늘의 일정'` → `'오늘 일정'` (plan_page.dart:177).
- 컨텍스트 액션: 지시가 "such as '일정에 추가'"로 예시. 현재 dock 버튼은 "하루 일정 보기/View plan"(=일정 보기)이며 onAddToPlan→planner 시트 오픈. **의미가 '추가'가 아닌 '보기'이므로 그대로 유지** (강제 변경 시 의미 왜곡 + 테스트 2건 파손). 영문화 정상 작동은 lalaCopy 경로 유지로 보장.
- 영문 지원: 변경 라벨은 모두 lalaCopy/OnboardingState.language 경유 이중언어 처리.

### 1.9 측정 목표 + 테스트 전략 (초안 문제 9 시정 및 구체화)
**측정 목표(구현 시 토큰/위젯에 반영):**
- 카드 반경 8px, 바텀시트 상단 반경 20px, 터치 타겟 ≥44px.
- 타이틀 30~32sp(제한적), 섹션 20~22, 본문 15~17, 칩 13~14, 하단탭 라벨 12~13sp.
- 접근성: 충분 대비(노란 카드 #F5C842 위는 어두운 텍스트), 아이콘 전용 버튼에 Semantics(label/selected), 진행 표시에 Semantics.

**테스트 전략(필수 최소):**
1. `planner_loading_card_test.dart` — 단일 카드, 중립 준비 문구, 접근 가능 진행(Semantics+LinearProgressIndicator), 가짜 단계 문구 부재.
2. `bottom_nav_bar_test.dart` — 라벨 '일정' 존재·'플랜' 부재, 영문 'Plan', 44px 타겟/컴팩트.
3. `onboarding_language_no_flags_test.dart` — 국기 이모지 부재, KO/EN 배지 존재.
4. `map/clustering_invariant_test.dart` — 상세 줌(level<10) 개별 마커, level≥10+80곡 이상만 클러스터.
5. 변경으로 깨지는 기존 단정 3건 갱신: `Size(74,74)`→`Size(48,48)`, `category-border-*` 키 → `map-rail-place-card-*` 키.
6. `search_skeleton_test.dart` — SkeletonBox 렌더 + 결과 카드형 스켈레톤 3개 + 빈 상태 진실 안내.

순차 실행: `flutter analyze` → `flutter test`.

## 2. 구현 범위 (커밋 그룹)

단일 브랜치에서 **집중 커밋(conventional commits)**, 완료 후 **PR 1개 오픈**(main/dev 미병합).

### Group A — 토큰 + 네비/일정 (가장 안전·가시적)
- `lib/app/lala_metrics.dart`(신규): cardRadius=8, sheetTopRadius=20, minTouchTarget=44, 타이포 목표 상수.
- `lala_bottom_nav_bar.dart`: '일정' + 영문 + 컴팩트 높이/라벨 + Semantics.
- `plan_page.dart`: 타이틀 '오늘 일정', `_PlanLoadingView` 카드 1개화.
- `planner_loading_card.dart`: 진실된 중립 준비 상태 + 접근 가능 진행 바.
- 테스트: planner_loading_card_test, bottom_nav_bar_test.

### Group B — 온보딩 밀도
- `onboarding_progress.dart` + `onboarding_scaffold.dart`: 3세그먼트(1/3~3/3), 스플래시 분리.
- `start_page.dart`: StatefulWidget, '국내 여행'/'해외 방문' 선택 행(반경 8), 명시적 다음(탭 자동이동 제거), 1/3.
- `language_page.dart`: KO/EN 배지(국기 제거), 단일 테두리+체크, 2/3.
- `location_consent_page.dart`: KakaoMapPreview 미리보기, '현재 위치 사용'+'지역 직접 선택' 상시, 3/3.
- `lib/shared/widgets/kakao_map_preview.dart`(신규): buildKakaoMapView 재사용 래퍼(IgnorePointer+ClipRRect).
- 테스트: onboarding_language_no_flags_test.

### Group C — 지도 계층/컨트롤/마커
- `map_rail_place_card.dart`: 이중 테두리→단일.
- `floating_map_controls.dart`: Row→Column. `map_fab.dart`: 44px/비흑색. `auto_docent_fab.dart`: 48px.
- `dashboard.dart`: 컨트롤 우하단 배치.
- 클러스터링: 변경 ❌, 불변량 테스트만.
- 테스트: clustering_invariant_test + 기존 3건 단정 갱신.

### Group D — 검색 스켈레톤
- `lib/shared/widgets/skeleton_box.dart`(신규): 쉬머 재사용 위젯.
- `search_page.dart`: `_SearchLoadingView`→결과 카드형 스켈레톤 3개; 빈 상태는 실제 이력만/없으면 진실 안내.
- 테스트: search_skeleton_test.

## 3. 보존 불변량 (invariants)
- 카카오 맵 조건부 import 구조(`kakao_map_view.dart` stub/web/native dispatch) 유지.
- Logto SDK 인증 경계 미변경.
- Geolocator + browser location 하이브리드 유지.
- 실시간 DB/API 데이터만(정상 경로에 모의/데모/스냅샷 미표시) 유지.
- 지도 API/데이터/클러스터링 계약 미변경(임계치 그대로).

## 4. 검증 (validation)
1. `cd apps/flutter_app && flutter analyze` → 0 issues.
2. `flutter test` → all pass (신규 + 갱신 포함).
3. 시각 QA: 가능하면 동일 뷰포트에서 6개 상태 캡쳐 후 참조와 비교 → `docs/planning/lala-mobile-image-to-code-design-qa.md` 작성. **캡쳐 없는 시각 검증 주장 ❌.** 기기/시뮬레이터·카카오 키·백엔드가 불가능하면 위젯 테스트 수준 근거로 대체하고 한계를 명시.
4. `git diff` 검수: 시크릿/키/로컬 스크린샷 커밋 여부 확인.
5. conventional commits, push, PR 오픈(main/dev 미병합).

## 5. 위험 + 완화
- **기존 위젯 테스트 파손**: 지도 컨트롤/카드 변경 시 3건 단정 갱신(Group C에 명시). 전체 `flutter test`로 회귀 확인.
- **온보딩 진행 단계 재계산**: OnboardingScaffold assert 완화 시 스플래시/3단계 모두 점검.
- **지도 미리보기 플랫폼 회귀**: KakaoMapPreview는 buildKakaoMapView만 감싸고 새 드로잉/시그니처 추가 ❌.
- **언어 SSOT 분리**: 네비는 OnboardingState.language 사용(설정 변경 즉시 반영은 기존 아키텍처 한계 → QA에 명시).
