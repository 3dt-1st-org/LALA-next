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
- 빈 결과의 "준비 중" 사본 정정: 검색(쿼리 없음)은 "이 주변엔 아직 추천이 없어요" /
  "No recommendations here yet", 플랜(빈 슬롯)은 "표시할 일정이 없어요" /
  "No plan slots to show" 로 변경. 데이터가 도착한 빈 결과를 영구 "준비 중"으로
  표시하던 오해 제거(로딩 카드/맵 대기 메시지는 로딩 중에만 "준비 중"을 쓰므로 그대로 유지).

### Cold-start 영속화 (`core/persistence/onboarding_preferences.dart`, `app/bootstrap.dart` — 후속, P0)
- **문제(실제 재시작으로 확인)**: `OnboardingState`·`RegionContextStore` 가 메모리 전용이라 프로세스 재시작 시 (1) 완료된 온보딩이 다시 떠오르고, (2) 수동으로 고른 지역이 사라졌다.
- **해결**: 완료 여부·선택 언어·관광객 유형·수동 지역 id 만을 버전 접두사 키(`lala.onboarding.v1.*`)로 SharedPreferences 에 영속화하는 작고 테스트 가능한 추상(`OnboardingPreferences` + 저장 백엔드 인터페이스). `bootstrapAppState()` 가 `runApp` **이전**에 영속화된 스냅샷을 정적 홀더에 주입(hydrate)한다.
  - GoRouter.redirect 가 첫 프레임부터 참된 완료 플래그를 본다 → 완료 사용자의 온보딩으로의 일시적 리다이렉트 점멸이 없다.
  - 검색/플랜/지도 탭이 첫 백엔드 시드를 *복원된 수동 지역* 좌표로 잡는다(`RegionContextStore.current` 가 이미 채워져 있어 기기 위치를 요청하지 않는다).
- **쓰기 순서**: 완료 게이트(`OnboardingState.completeAndFlush`)는 라우터가 보는 `_completed` 플래그를 뒤집기 *전에* 영속화를 `await` 한다. 탭 직후 kill 되어도 restart 상태를 잃지 않는다.
- **프라이버시 정책(현위치 좌표)**: `RegionSource.current`(정확한 기기 좌표)은 **절대** 저장하지 않는다. `set(current)` 는 저장된 수동 id 만 지운다. 그 결과 cold start 시 현위치 컨텍스트는 null 이 되고, 기존 하이브리드 위치 provider 가 다시 요청할 수 있다. 수동 선택만이 안정 regionId 로 복원된다.
- **검증**: 유효하지 않거나 제거된 수동 regionId → 무시 + 해당 키 제거(크래시/가짜 지역 없음). 저장 읽기/쓰기 실패 → 깨끗한 first-run 상태로 안전하게 저하(앱은 항상 시작). 관광객 유형은 코드 문자열로 저장하고 enum 매핑은 `OnboardingState` 가 소유해 순환 import 를 피함.
- **재온보딩/reset**: `OnboardingState.reset()`·`RegionContextStore.clear()` 가 각자의 영속 슬라이스도 지운다.

### 탭 간 region 컨텍스트 즉시 전파 (`search_page.dart`, `plan_page.dart` — 후속 수정)
- 기존엔 두 탭이 `RegionContextStore.current` 를 최초 1회 시드한 뒤 `_load()` 때마다
  `requestCurrentLocation` 를 호출했다. 온보딩/다른 탭에서 수동 지역을 고른 뒤 탭을 전환하면
  반영이 안 되거나, 뒤늦은 기기 위치 응답이 수동 선택을 덮어쓸 수 있었다.
- 이제 `initState` 에서 `RegionContextStore.listenable` 리스너를 등록(`dispose` 해제)한다.
  리스너는 공유 컨텍스트를 로컬 상태로 복사한 뒤, **기기 위치를 다시 요청하지 않고** 해당 좌표
  (또는 공개된 기본 지역)로 백엔드를 재구성해 새로고침한다(`mounted` 일 때만). 자기 자신이
  게시한 값은 `==` 가드로 무시해 중복 리로드/피드백 루프를 막는다.
- 단조 증가 `_loadGeneration` 토큰으로 stale 리로드를 방지: 초기 로드 중 기기 위치 요청이
  진행 중일 때 store 가 바뀌면, 뒤늦은 기기 응답이 새 컨텍스트를 덮어쓰지 못한다.
- **추가 정제(후속)**: `_load()` 의 기기 위치 요청을 `_region == null` 일 때로 한정한다. 온보딩이
  남긴 수동 선택(또는 다른 탭이 게시한 현재 위치)이 이미 store 에 있으면 초기 로드조차
  `requestCurrentLocation` 을 부르지 않으므로, 의도적 수동 선택이 첫 위치 응답에 덮어씌워지지
  않는다(실제 컨텍스트가 없을 때만 최초 1회 요청). 마운트 이후 변화는 여전히 리스너 경로.

### 영구 거절(permanentlyDenied) 복구 UI (`home_page.dart`, `location_consent_page.dart`,
`permanently_denied_recovery.dart`, `app_settings_opener*.dart` — 후속)
- 기존엔 `permanentlyDenied` 를 일반 `denied`/`unavailable` 과 동일(재시도 토스트 / 대기 복귀)으로
  렌더해, OS 영구 거절 사용자가 차이나 복구 경로를 볼 수 없었다.
- 이제 permanentlyDenied 전용 평온한 복구 카드를 추가: 시스템/브라우저 설정에서 위치가 꺼져 있음을
  설명하고, 수동 지역 선택(항상 노출)을 유지하며, **지원되는 플랫폼에서만** 실제 “설정 열기” 액션을 제공.
- **플랫폼 경계 추상화**: `app_settings_opener.dart` 가 기존 `browser_location` 과 동일한
  `dart.library.io` 조건부 import 로 분기. native(io)는 `app_settings` 패키지(8.0.3)로 OS 앱 설정
  페이지(앱별 위치 토글이 있는 곳)를 열고 `canOpenAppSettings == true`. web/미지원(stub)은
  `canOpenAppSettings == false` 이며 가짜 액션 없이 브라우저 사이트 설정 안내 + 수동 선택으로 정직 폴백.
- 핸드오프가 실패/미지원이어도 흐름은 막히지 않는다: `openAppSettings()` 는 예외(`MissingPluginException`
  포함)를 잡아 `false` 로 반환하고, 복구 카드는 항상 수동 선택(native 에선 “재시도”까지)을 노출.
- 홈은 맵 위 비차단 오버레이(맵은 그대로 사용 가능), 온보딩은 액션 영역을 복구 카드로 교체.
  위치가 다시 잡히거나 수동 선택/재시도하면 `_locationPermanentlyDenied` 를 해제.

### 날씨/대기 진실성 (변경 불필요 — 확인만)
- 기존 구현이 이미 정직: `publicWeatherOrNull` + `isPlaceholderWeatherSource` 가
  skeleton/fallback/unavailable/`*_fallback` 소스를 모두 `null` 로 억제. `WeatherUnavailableCard` 가
  유일한 null 상태 UI(“날씨 데이터 준비 중”). 조작값/영구 spinner 없음. provider 키는 서버사이드.

## 데이터 경계 (요약)

| 관심 | 경계 | 상태 |
|---|---|---|
| 주변 장소 | DB/PostGIS + API(`getPlaces`) | 번들/목업 시작 장소 없음. pending/empty/unavailable 구분. |
| 날씨/대기 | 서버사이드 공식 서비스(API `getWeather`) | 실제 타임스탬프 스냅샷만 표시. placeholder→unavailable. 클라이언트 provider 키 없음. |
| 지역 컨텍스트 | SharedPreferences(cold-start) + in-memory store(process-local) | 수동 선택 regionId 만 영속화·복원. 현위치 좌표/RegionSource.current 는 미저장. |
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
  `test/features/location/permanently_denied_recovery_test.dart`(영구 거절 복구 카드: native-capable /
  web-non-supported / ko·en 배타 / 수동 탈출 + `app_settings_opener` 추상화),
  `test/features/weather/weather_helpers_test.dart` 에 placeholder/실소소스 억제 테스트 추가.
- `widget_test.dart` 에 `setUp(RegionContextStore.clear)` 추가 — 프로세스 로컬 store 가 탭 간에 새어
  좌표 시드를 오염시키지 않도록 각 테스트 격리. 검색/플랜 페이지 테스트에도 `setUp`/`tearDown` 으로
  정적 store 를 매 케이스마다 초기화해 격리.
- `flutter analyze`: 이슈 없음. `flutter test`: 178개 통과(159 + cold-start 영속화 19건 추가) —
  직렬화 라운드트립(완료+언어+관광객 유형+유효 수동 지역), cold-start 라우팅(완료 사용자 → 지도 쉘, 온보딩 점멸 없음),
  복원된 수동 Busan 이 Search/Plan 첫 로드 시드 + 기기 위치 미요청, 현위치 미저장, 무효 region id/저장 실패 안전 저하,
  reset 영속 데이터 청소, completeAndFlush 내구성/실패 시 인메모리 완료.
  (이전 슬라이스 누적 검증: 탭 간 전파 리로드, 마운트 전 수동 선택 보존 — 초기 위치 요청이 덮어쓰지 않음 —
  검증 2건, permanentlyDenied 복구 + 설정 열기 추상화 검증 6건.)

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

## 진짜 블로컈 (Wave-1 잔여, 비차단)

- `OnboardingState`·`RegionContextStore` 의 cold-start 영속화는 **이제 구현됨**(위 “Cold-start 영속화” 참고).
  완료·언어·관광객 유형·수동 지역 id 가 restart 에 복원된다. **잔여 한계(진실)**:
  - `RegionSource.current`(정확한 기기 좌표)는 의도적으로 영속화하지 않는다. 온보딩/탭에서 “현재 위치 사용”
    만 고른 사용자는 restart 시 실제 컨텍스트가 없고 기본 지역으로 폴백하며, provider 가 현위치를 다시
    요청할 수 있다(프라이버시 우선). 마지막 *수동* 선택만 복원 대상이다.
  - 앱이 시작조차 못 하는 극단적 저장 고장 시 first-run 으로 저하한다. 일시적 쓰기 실패는 해당 세션의
    인메모리 상태에는 영향을 주지 않지만 cold restart 에는 기억되지 않을 수 있다(저장은 best-effort).
  - 검증 방식: 단위/위젯 테스트(`flutter test`)로 직렬화 라운드트립·복원 라우팅·수동 Busan 시드·현위치
    미저장·무효 id/저장 실패 저하·reset 청소를 증명했다. **실기기 재시작 프로브는 이 슬라이스에서 직접
    수행하지 않았다** — 동작은 테스트로 보장되며, 실기기 재시작 검증은 별도 확인으로 남긴다.
- `LalaAppConfig` 기본 좌표(수원)가 여전히 하드코딩된 “공개된 기본 지역”. 이제 정직 표시기로 공개되므로
  은폐 아님. 별도 작업에서 기본 지역 자체를 env/설정 가능하게 분리 가능.
- splash copy(“당신의 수원을 안내합니다” → “여행을 안내해 드릴게요 / We'll guide your trip”)와
  `locationLabel` 의 null 기본값(수원 → “기본 지역 / Default region”)은 **이제 정직한 사본으로 교체**됨.
  위치가 확정되기 전 특정 지역/“주변”을 약속하지 않는다.
