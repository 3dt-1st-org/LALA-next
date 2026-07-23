# LALA 모바일 image-to-code — 디자인 QA

> 참조(시각 SSOT): `/Users/geondongkim/.codex/generated_images/019eb5c9-.../exec-f201cd1d-....png`
> 비교용 before: `/tmp/lala-ui-audit-contact-sheet.png`
> 구현 계획: `docs/planning/lala-mobile-image-to-code-implementation-plan.md`
> 브랜치: `geondongkim/lala-mobile-image-to-code`

## 1. 참조 해석 원칙
- 비전/OCR 툴의 한국어 읽기는 환각이 심해(예: "위쿡인 관광객", "추천 주요을") **신뢰하지 않는다**(기기 캡쳐 검수 규칙과 동일).
- 레이아웃/구조/색/계층/밀도는 이미지 분석을 따르고, 문구는 작업 지시의 명시 수용기준 + 기존 코드의 진실된 lalaCopy 문자열을 소스로 했다.

## 2. 화면별 구현 결과 (참조 수용기준 대비)

### 온보딩 1 (start) — 1/3
- ✅ 선택 행 2개(국내 여행 / 해외 방문), 반경 8, 단일 테두리 + 체크.
- ✅ 탭해도 자동 이동 ❌ → 명시적 “다음” 버튼(StatefulWidget 선택 상태).
- ✅ 진행 표시 1/3(3세그먼트). 타이틀 headlineSmall(≈24sp) 한 줄.
- 매핑: 국내 여행→localTourist(ko), 해외 방문→foreignTourist(en).

### 온보딩 2 (language) — 2/3
- ✅ 국기 이모지 제거 → KO/EN 텍스트 배지.
- ✅ 선택 행 단일 테두리 + 체크. 진행 2/3.
- 테스트: `onboarding_language_no_flags_test`(🇰🇷/🇺🇸 부재, KO/EN 존재).

### 온보딩 3 (location) — 3/3
- ✅ 장식 아이콘 제거 → 실제 카카오 타일 미리보기(`KakaoMapPreview`, 조건부 import 재사용, IgnorePointer+ClipRRect). 키 누락 시 기존 `KakaoMapFallbackView` 명시 메시지 유지.
- ✅ “현재 위치 사용” + “지역 직접 선택” 첫 렌더부터 상시(거부 후 전용이 아님).
- ✅ 스크롤 가능(작은 화면/배너 대응). 진행 3/3.

### 지도
- ✅ 3-레이어 유지: 상단 카테고리 칩+설정(`TopMapChrome`) / 얇은 사진 레일(`MapPlaceCarouselOverlay`) / 하단 바텀시트+도슨트(`MapBottomDock`/`DockDocentPreview`).
- ✅ 컨트롤: 가로 중앙 Row → **우하단 세로 스택**(`FloatingMapControls` Column). 대형 흑색 원형 제거(`AutoDocentFab` 74→48, `MapFab` 46→44 비흑색).
- ✅ 레일 카드 이중 테두리 → 카테고리색 단일 2px(반경 8). 바텀시트 상단 반경 28→20.
- ✅ 마커/클러스터링: 임계치 `places.length>=80 && mapLevel>=10` 는 **코드 탐색으로 이미 요구 만족**(상세 줌 개별 핀). 변경 ❌, 불변량 테스트로 고정.
- ✅ “꿈”/로봇/이모지/반복 점수 텍스트: 기존에 부재 확인 → 유지.

### 검색
- ✅ 로딩: 빈 스피너 → 결과 카드형 스켈레톤 3개(`SearchResultsSkeleton` + 재사용 `SkeletonBox`, 결과 타일과 동형).
- ✅ 최근/인기/모의 장소 ❌. 빈 상태는 기존 진실 안내(`EmptyPlaceState`) 유지.

### 일정
- ✅ 타이틀 “오늘 일정”(오늘의 일정→). 로딩 카드 **1장**(중복 2장 제거).
- ✅ 타이머 기반 가짜 단계 ❌ → 진실된 중립 준비 상태 + 비율 미정 진행 바 + 접근성 Semantics. 재시도는 실패 뷰에만.

### 하단 탭
- ✅ 라벨 검색/지도/일정(플랜→일정), 영문 Search/Map/Plan(OnboardingState.language SSOT). 컴팩트 NavigationBarTheme(높이 68, 12sp). Semantics.

## 3. 측정 목표 적용
- 카드 반경 8(`LalaMetrics.cardRadius`), 바텀시트 상단 20(`sheetTopRadius`), 터치타겟 ≥44(`minTouchTarget`), 칩/행 반경 8(`choiceRowRadius`), 컨트롤 44/48. 타이포: 타이틀 headlineSmall(≤32), 본문 bodyMedium(~16), 칩 labelSmall(~13), 하단탭 12. 토큰 SSOT: `lib/app/lala_metrics.dart`.

## 4. 검증(자동화)
- `flutter analyze` → **No issues found!**
- `flutter test` → **122 passed**(기존 112 + 신규 10: planner loading, nav bar, 언어 국기 없음, 클러스터링 불변량 3, 스켈레톤 2... 정확히는 아래 목록).
  - 신규/갱신: `planner_loading_card_test`(단일·중립·접근성), `lala_bottom_nav_bar_test`(일정/Plan), `onboarding_language_no_flags_test`, `clustering_invariant_test`(3), `search_results_skeleton_test`(2). 갱신: widget_test 내 온보딩 플로우 5 + 지도 단정 3(Size 74→48, category-border→map-rail-place-card ×2).
- 비밀/키/스크린샷 커밋: diff 스캔 **해당 없음**(소스·문서·테스트만).

## 5. 시각 캡쳐 (capture)
- **실기기 캡쳐(Android, 유선 연결): 성공** — 사용자 스마트폰(R3CX20PCDWY, 1080×2340 @480dpi)에 디버그 APK 설치/실행. `LALA_API_BASE_URL=https://api.lala-next.cloud`로 **실시간 프로덕션 데이터** 로드. `adb exec-out screencap` + tesseract(kor) OCR + PIL pixel-diff 로 ground-truth 검증(비전 툴 환각 금지 원칙 준수). 캡쳐 PNG는 로컬 유지(커밋 ❌).
- **보조: 웹 캡쳐(390×844)** — `flutter run -d web-server --release` 로 빌드/서빙 성공, Playwright 로 6상태 캡쳐 + 접근성 스냅샷 교차 검증. 웹은 CORS 로 실시간 데이터 미수신(모바일은 영향 없음) → 구조 검증용 보조 증거.

## 6. 실기기 캡쳐 결과 — 6상태 전부 실시간 데이터로 검증(주 증거)

`lala-device-0{1..6}-*.png`(로컬). OCR/pixel-diff 로 확인한 렌더링 내용:

1. **01-onboarding-start** — “국내 여행/해외 방문” 선택행 + “기본 언어: 한국어” + “다음”. 진행 1/3.
2. **02-onboarding-language** — “한국어/영어” 옵션(KO/EN 배지, 국기 없음). 진행 2/3.
3. **03-onboarding-location** — 상단 지도 미리보기(fallback) + “위치 권한 허용/지역 직접 선택/나중에 하기”. 진행 3/3.
4. **04-map** — 카테고리 칩 + 레일(실제 장소 “평택시 1559m”) + “하루 일정” 필 + “날씨 데이터 준비 중”(날씨 미가용을 솔직히 표시) + “상세” 독 + 3 컨트롤 + 하단탭 **검색/지도[selected]/일정**(플랜→일정 정상). (카카오 키 미주입 → fallback 타일; 구조는 정상.)
5. **05-search** — 실시간 결과: 카페포렌·불갈비·평택시… 거리(m)와 함께 정상 목록.
6. **06-plan** — 실시간 일정: 타임슬롯 + “날씨에 맞춰 조정” + “일정 재생성”. 타이틀 “오늘 일정”.

pixel-diff(01 vs 02) bbox `(60,54,1020,2193)` → 화면 전환이 확인됨(정적 이미지 아님).

### 보조 웹 캡쳐(`lala-web-0{1..6}-*.png`, 로컬)
390×844 뷰포트. 접근성 스냅샷으로 온보딩 `3 / 3` 진행 · “지도 미리보기 현재 지도를 표시할 수 없습니다.” · 하단탭 `검색/지도/일정` · 플랜 타이틀 “오늘 일정” 교차 검증. 웹은 CORS 로 데이터 미수신 → 구조 검증용.

## 7. 차이/한계 (discrepancies)
- **언어 SSOT 분리**: 네비는 `OnboardingState.language`를 따름(온보딩 페이지들과 동일). 설정에서 언어 변경은 현재 지도 config에만 반영되고 OnboardingState에는 반영되지 않는 기존 아키텍처 한계 → 네비 라벨은 온보딩 언어를 따른다. (기존엔 네비가 항상 한국어였음 → 개선.)
- **검색 결과 타일 반경**: 결과 카드는 기존 18px 유지(스켈레톤도 동일하게 미러링). “8px 카드” 목표는 레일 카드/온보딩 행에 적용; 검색 타일은 전환 호흡 일치를 위해 18 유지(저위험, 후속 조정 가능).
- **지도 미리보기(웹)**: 웹에서 KakaoMapPreview는 조건부 import를 그대로 쓰나, 웹 브릿지는 전체 뷰포트 배경에 타일을 그리는 구조라 미리보기 영역이 웹에서는 전체 화면 배경으로 나타날 수 있음(모바일 네이티브 WebView에서는 ClipRRect 영역 안에서 정상). 모바일 타깃 기준 동작에는 영향 없음.
- **클러스터링 임계치**: 코드 탐색으로 이미 요구 만족이 입증되어 변경하지 않음(계약 보존).

## 8. 최종 결과 — **PASSED**

- 6개 모바일 상태를 **실기기(Android, 1080×2340)에서 실시간 프로덕션 데이터**로 캡쳐·검증(OCR + pixel-diff ground-truth). 작업 지시의 9가지 수용기준 전부 충족.
- `flutter analyze` 0 이슈 / `flutter test` 122 통과(기존 112 + 신규 10).
- 비밀/키/스크린샷 커밋 없음(캡쳐·키는 로컬 유지).
- 잔존 한계(블로커 아님): (a) 실기기 캡쳐 환경에 카카오 JS 키 미주입 → 지도 타일은 fallback(구조/마커 정상, 실제 타일은 키 주입 시). (b) 언어 SSOT 분리로 설정 언어 변경이 네비에 즉시 반영 안 됨(기존 아키텍처 한계, 온보딩 언어는 반영). (c) 검색 결과 타일 반경 18 유지(레일/온보딩은 8 적용).
