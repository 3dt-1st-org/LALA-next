# Devlog - 2026-07-25 Wave-1 위치·날씨 정직성 슬라이스

위치 권한 경계, 지역 컨텍스트 전파, “수원 = 주변” 은폐 제거, 전국 영문 지역 폴백 수정,
그리고 PR CI에서 Flutter analyze/test 가 실제로 보장되도록 CI를 보강. 모두 단순 추가/수정이며
DB 마이그레이션·배포·DNS·비밀키 변경은 없다(아래 “롤백” 참고).

## 목표 (Locked scope)

- Geolocator + browser_location 조건부 import 경계 유지. `denied` 와 구분되는 정직한
  `permanentlyDenied` 상태 추가(경계가 허락하는 곳에서만). denied/unsupported/error 경계 진실 유지.
- 좌표·안정 region id·ko/en 라벨·source(`current`/`manual`/`default`)를 갖는 결정론적 region context 도입.
  온보딩 수동 선택을 앱 쉘로 이관(폐기 금지).
- 검색/플랜 탭이 수원을 “주변”으로 은폐 사용하지 않도록 수정. 의도적 기본 컨텍스트가 남으면
  정직한 현지화 기본 지역 표시기를 노출. 수동/현재 컨텍스트가 장소·날씨 호출을 구동.
- 장소 호출은 DB/PostGIS/API 경계 유지. 번들/목업 시작 장소 없음. pending/empty/unavailable 구분.
- 날씨/대기는 기존 공식 서버사이드 서비스 경계 유지: 실제 타임스탬프 스냅샷 또는 진실된 unavailable/stale.
  조작값/영구 준비중 없음. 클라이언트 provider 키 없음.
- `db_repository._english_region` / `public_mvp_data._english_region` 의 경기도 한정 영문 폴백 수정.
- 권한·수동 컨텍스트 전파·기본 표시·날씨 데이터 상태·번들 폴백 부재에 대한 집중 Flutter 테스트. ko/en 배타.
- 날짜 devlog 작성.
- PR CI에서 Flutter analyze/test 가 실제로 보장되도록 `.github/workflows/ci.yml` 점검/수리.

## 바뀐 흐름

### 위치 권한 경계 (`lib/core/location/lala_location.dart`)
- `LalaLocationResultStatus` 에 `permanentlyDenied` 추가(`found`/`denied`/`unavailable` 유지).
- `GeolocatorLalaLocationProvider` 가 `LocationPermission.deniedForever` 를 더 이상 `denied` 로
  합치지 않고 `permanentlyDenied` 로 보고. OS 영구 거절은 시스템 다이얼로그가 재노출되지 않으므로
  UI가 “재요청” 대신 설정 유도로 갈 수 있도록 분리.
- **진실성 경계**: web Geolocation API 는 영구 거절을 신뢰성 있게 구분할 수 없으므로, web 경로는
  기존대로 `denied` 를 유지(거짓으로 `permanentlyDenied` 라고 단정하지 않음). native Geolocator만
  `deniedForever` 를 `permanentlyDenied` 로 보고.

### Region context (`lib/core/location/region_context.dart` — 신규)
- `RegionContext`(불변 값 객체): `lat/lng`, 안정 `regionId`, 배타적 `labelKo/labelEn`, `source`.
  `RegionContext.current(...)` / `RegionContext.manual(option)` 팩토리.
- `RegionContextStore`: `OnboardingState` 패턴과 동일한 in-memory 싱글톤(`ValueNotifier<RegionContext?>`).
  `null` = “실제 컨텍스트 없음 → 공개된 기본 지역 사용”. 영속화(Prefs)는 의도적 범위외(메모리 only).
- 온보딩(`location_consent_page.dart`)이 현재 위치/수동 선택을 store 로 이관(기존엔 폐기됨).
- home/search/plan 이 store 에서 시드. `found` 면 current 로, 수동 선택이면 manual 로 store 갱신 →
  탭 간 동일 컨텍스트 공유.

### “수원 = 주변” 은폐 제거 (`search_page.dart`, `plan_page.dart`, `home_page.dart`)
- 검색/플랜 탭이 실제 컨텍스트 없이 수원 좌표를 조용히 “주변”으로 쓰던 동작 제거.
  store 컨텍스트가 없으면 공개된 기본 지역(LalaAppConfig 기본값)으로 폴백하되,
  `DefaultRegionIndicator` 로 “현재 위치 대신 기본 지역(수원) 추천을 보여드려요 /
  Showing the default region (Suwon), not your location” 를 정직하게 표시.
- 수동/현재 컨텍스트가 잡히면 표시기는 숨겨지고 그 좌표가 장소·날씨 호출을 구동.
- denied/permanentlyDenied/unavailable 모두 기존 컨텍스트(수동 선택 또는 기본 지역)를 유지.
  임의 좌표를 끼워 넣지 않음.

### 날씨/대기 진실성 (변경 불필요 — 확인만)
- 기존 구현이 이미 정직: `publicWeatherOrNull` + `isPlaceholderWeatherSource` 가
  skeleton/fallback/unavailable/`*_fallback` 소스를 모두 `null` 로 억제. `WeatherUnavailableCard` 가
  유일한 null 상태 UI(“날씨 데이터 준비 중”). 조작값/영구 spinner 없음. provider 키는 서버사이드.

## 데이터 경계 (요약)

| 관심 | 경계 | 상태 |
|---|---|---|
| 주변 장소 | DB/PostGIS + API(`getPlaces`) | 번들/목업 시작 장소 없음. pending/empty/unavailable 구분. |
| 날씨/대기 | 서버사이드 공식 서비스(API `getWeather`) | 실제 타임스탬프 스냅샷만 표시. placeholder→unavailable. 클라이언트 provider 키 없음. |
| 지역 컨텍스트 | in-memory store(process-local) | current/manual/default. 영속화는 범위외. |
| 권한 | Geolocator(영구 구분) + browser_location(구분 불가→denied) | 4상태. |

## 검증

### Backend (API)
- `apps/api/tests/test_db_repository.py`, `test_public_mvp_data.py` 에 전국 영문 지역/주소 합성 테스트 추가
  (Busan/Jeju/Gangwon/Jeollanam-do/Gyeongsangbuk-do 해상도, 경기/서울 회귀, 모호 지역(중구)은
  province 위조 없이 region-only, 빈 행은 빈 주소).
- `region_catalog.province_name_en_for_region`(시/군/구→도 역매핑, 모호하면 None) 으로 region-only 행도
  실제 도를 해상도.
- 타깃 + 전체 API 테스트 통과(`pytest apps/api/tests`).

### Flutter
- 집중 테스트 추가: `test/core/location/region_context_test.dart`(값 의미·store·permanentlyDenied 구분),
  `test/features/location/default_region_indicator_test.dart`(기본 표시 show/hide·수동 좌표 구동·빈 상태·ko/en 배타),
  `test/features/weather/weather_helpers_test.dart` 에 placeholder/실소소스 억제 테스트 추가.
- `widget_test.dart` 에 `setUp(RegionContextStore.clear)` 추가 — 프로세스 로컬 store 가 탭 간에 새어
  좌표 시드를 오염시키지 않도록 각 테스트 격리.
- `flutter analyze`: 이슈 없음. `flutter test`: 149개 통과. `dart format --set-exit-if-changed` 통과.

## CI/배포 평가

### CI (`ci.yml`) — 보강
- **문제**: `scripts/{unix,windows}/verify_flutter_app.{sh,ps1}` 가 Flutter 부재시 조용히 skip(exit 0).
  windows-latest(및 ubuntu 기본)엔 Flutter 가 없어 PR CI에서 앱이 사실상 analyze/test 되지 않음.
  `verify_repo.sh` 도 `verify_flutter_app.sh` 를 호출해 같은 skip 경로.
- **조치**: 전용 `flutter-app` job(ubuntu-latest) 추가. `subosito/flutter-action@v2`(stable, cache)로
  Flutter 설치 후 `flutter pub get` / `flutter analyze` / `flutter test` 를 **명시적으로** 실행.
  비밀키 불필요(analyze/test엔 공식 web build key 미사용). 기존 wrapper 단계는 보조로 유지.
- ci.yml YAML 유효성 확인.

### 배포 동작 (확인, 변경 없음)
- **API 배포**: `deploy.yml` 은 `workflow_run` 으로 **main** 의 CI 성공시에만 SSM→EC2 배포.
  이 Draft PR 에서는 배포 트리거 없음.
- **Web 배포**: `scripts/unix/deploy_flutter_web_vercel.sh` 의 dart-define 은 공개값만 —
  `LALA_API_BASE_URL`(공개 API URL), `LALA_BUILD_SHA`(빌드 SHA), `KAKAO_JAVASCRIPT_KEY`(의도적 공개 JS 키).
  provider 키 없음. `deployed-web-smoke.yml` 은 `dev` 브랜치 스모크(배포 아님).
- **provider 키**: 날씨/대기는 서버사이드 API. 클라이언트 provider 키 없음.

## 롤백 (no-migration)

- DB 마이그레이션·스키마 변경·데이터 이관 없음. 전부 코드/테스트/CI 추가·수정.
- 롤백 = 해당 커밋 revert. 런타임 상태/데이터 부작용 없음. `RegionContextStore` 는 메모리 전용.

## 진짜 블로커 (Wave-1 잔여, 비차단)

- `RegionContextStore` 영속화(Prefs) 미구현 — 앱 재시작시 컨텍스트 초기화. 의도적 범위외(온보딩 상태와 동일 패턴).
- `LalaAppConfig` 기본 좌표(수원)가 여전히 하드코딩된 “공개된 기본 지역”. 이제 정직 표시기로 공개되므로
  은폐 아님. 별도 작업에서 기본 지역 자체를 env/설정 가능하게 분리 가능.
- splash copy(“당신의 수원을 안내합니다”)·`locationLabel` 의 null 기본값(수원)은 라벨 헬퍼 영역이라
  이 슬라이스의 “탭 은폐” 범위 밖. 표시기가 이미 기본 지역을 정직 공개하므로 모순 아님.
