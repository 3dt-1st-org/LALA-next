// 모바일 비주얼 계약(Slice D / S5 + remediation D): 검색 상태 검증.
// - pending: 결과 모양 중성 스켈레톤 정확히 3줄.
// - 에러 도착 후: 스켈레톤은 완전히 사라지고 재시도로 전환.
// - loaded: 스켈레톤 제거 + 실제 장소명/지역/거리/공식 이미지 슬롯.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/place/widgets/place_image.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';
import 'package:lala_next_app/manual_location_options.dart';

void main() {
  // RegionContextStore is a process-local singleton; reset it before each test
  // so a manual/current choice from another test cannot leak into this tab's
  // seed coordinates.
  setUp(() {
    RegionContextStore.clear();
    OnboardingState.selectLanguage('ko');
  });

  testWidgets(
    'search pending shows exactly three neutral skeleton rows then removes them',
    (tester) async {
      final backend = _PendingPlacesBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _FoundLocationProvider(),
            // _load 가 백엔드를 재생성하므로 동일 인스턴스를 반환한다.
            backendFactory: (config) => backend,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      // 진행 중(getPlaces 미해결): 결과 모양 스켈레톤 3줄.
      expect(
        find.byKey(const ValueKey('search-skeleton-row')),
        findsNWidgets(3),
      );

      // 에러 도착 → 스켈레톤 제거, 재시도 노출.
      backend.completeError();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-skeleton-row')), findsNothing);
      expect(find.text('재시도'), findsOneWidget);
    },
  );

  testWidgets(
    'search loaded renders the real place name, region, distance and official image',
    (tester) async {
      final backend = _LoadedPlacesBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) => backend,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // loaded: 스켈레톤은 완전히 제거(에러 경로로 대체하지 않는다).
      expect(find.byKey(const ValueKey('search-skeleton-row')), findsNothing);
      // 실제 장소명/지역/거리.
      expect(find.text('행궁동 카페'), findsOneWidget);
      expect(find.text('수원'), findsWidgets);
      expect(find.text('320m'), findsOneWidget);
      // 공식 이미지 슬롯(빌려온/발명 이미지가 아님) — 좌측 고정 미디어 프레임 안.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('search-place-media-search-test-cafe')),
          matching: find.byType(PlaceImage),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'store-driven manual region reloads the backend without re-requesting location',
    (tester) async {
      final configs = <LalaAppConfig>[];
      final locationProvider = _CountingLocationProvider(
        const LalaLocationResult.unavailable(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: locationProvider,
            // _load/_reloadFromStore 모두 백엔드를 재생성하므로 동일 인스턴스를
            // 반환하되, 호출될 때마다 사용된 config 를 기록한다.
            backendFactory: (config) {
              configs.add(config);
              return _LoadedPlacesBackend();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 초기 로드는 기기 위치를 정확히 한 번 요청한다(기존 동작).
      expect(locationProvider.requests, 1);

      // 온보딩/다른 탭에서 수동 지역이 공유 store 에 게시되면 리스너가 발동한다.
      RegionContextStore.set(RegionContext.manual(_busanOption()));
      await tester.pumpAndSettle();

      // 수동 선택이 발생한 리로드는 기기 위치를 다시 요청하지 않는다.
      expect(locationProvider.requests, 1);
      // 가장 마지막 백엔드는 수동 선택의 좌표로 구성되었다.
      expect(configs.last.lat, 35.16);
      expect(configs.last.lng, 129.16);
    },
  );

  testWidgets(
    'a manual region retained from onboarding is not overwritten by the initial location request',
    (tester) async {
      // 온보딩이 수동 선택을 store 에 남긴 채 탭이 마운트되는 상황.
      RegionContextStore.set(RegionContext.manual(_busanOption()));
      final configs = <LalaAppConfig>[];
      // found provider(서울 인근) — 이 결과가 수동 선택을 덮어쓰면 안 된다.
      final locationProvider = _CountingLocationProvider(
        const LalaLocationResult.found(
          LalaLocation(lat: 37.2636, lng: 127.0286),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: locationProvider,
            backendFactory: (config) {
              configs.add(config);
              return _LoadedPlacesBackend();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Why: with a real context already in the store, the initial _load() must
      // NOT request device location at all, so the deliberate manual choice can't
      // be clobbered by a later geolocation fix.
      expect(locationProvider.requests, 0);
      expect(configs.last.lat, 35.16);
      expect(configs.last.lng, 129.16);
      // 기본 지역 표시기도 등장하지 않는다(실제 수동 컨텍스트 있음).
      expect(find.text('현재 위치 대신 기본 지역(수원) 추천을 보여드려요'), findsNothing);
    },
  );

  testWidgets(
    'selected language updates Search immediately and reloads in EN',
    (tester) async {
      RegionContextStore.set(RegionContext.manual(_busanOption()));
      final configs = <LalaAppConfig>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _CountingLocationProvider(
              const LalaLocationResult.unavailable(),
            ),
            backendFactory: (config) {
              configs.add(config);
              return _LoadedPlacesBackend();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('장소·지역 검색'), findsOneWidget);

      OnboardingState.selectLanguage('en');
      await tester.pumpAndSettle();

      expect(find.text('Search places or areas'), findsOneWidget);
      expect(find.text('장소·지역 검색'), findsNothing);
      expect(configs.last.lang, 'en');
    },
  );

  testWidgets(
    'search always exposes the active region and a nationwide picker entry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _CountingLocationProvider(
              const LalaLocationResult.unavailable(),
            ),
            backendFactory: (config) => _LoadedPlacesBackend(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('search-region-picker')),
        findsOneWidget,
      );
      expect(find.text('탐색 지역'), findsOneWidget);
      expect(find.text('기본 지역 · 수원'), findsOneWidget);
      expect(find.text('변경'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('search-region-picker')));
      await tester.pumpAndSettle();

      expect(find.text('지역 선택'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('manual-location-search')),
        findsOneWidget,
      );
    },
  );

  testWidgets('search region context fits the mobile contract viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          locationProvider: _CountingLocationProvider(
            const LalaLocationResult.unavailable(),
          ),
          backendFactory: (config) => _LoadedPlacesBackend(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final picker = find.byKey(const ValueKey('search-region-picker'));
    expect(picker, findsOneWidget);
    expect(tester.getSize(picker).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search region row reacts to a shared manual selection', (
    tester,
  ) async {
    RegionContextStore.set(RegionContext.manual(_busanOption()));
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          locationProvider: _CountingLocationProvider(
            const LalaLocationResult.unavailable(),
          ),
          backendFactory: (config) => _LoadedPlacesBackend(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('해운대구'), findsOneWidget);
    expect(find.text('기본 지역 · 수원'), findsNothing);

    RegionContextStore.set(
      RegionContext.manual(
        const ManualLocationOption(
          id: 'seoul-jongno',
          provinceId: 'seoul',
          provinceKo: '서울특별시',
          provinceEn: 'Seoul',
          labelKo: '종로구',
          labelEn: 'Jongno-gu',
          lat: 37.573,
          lng: 126.9794,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('종로구'), findsOneWidget);
    expect(find.text('해운대구'), findsNothing);
  });

  testWidgets(
    'manual region selection still works when location permission is denied',
    (tester) async {
      // 권한 거부(soft denial) 상태에서도 수동 선택 경로가 막히지 않아야 한다.
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _CountingLocationProvider(
              const LalaLocationResult.denied(),
            ),
            backendFactory: (config) => _LoadedPlacesBackend(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('search-region-picker')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('manual-location-search')),
        '세종',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('manual-location-option-sejong-sejong')),
      );
      await tester.pumpAndSettle();

      // 행 탭은 pending만 바꾸고, 명시 CTA를 눌러야 실제 context가 바뀐다.
      expect(RegionContextStore.current, isNull);
      await tester.tap(find.byKey(const ValueKey('manual-location-apply')));
      await tester.pumpAndSettle();

      // 거부와 무관하게 수동 선택이 store 에 확정되고 region 행에 반영된다.
      expect(RegionContextStore.current?.regionId, 'sejong-sejong');
      expect(find.text('세종특별자치시'), findsOneWidget);
      expect(find.text('기본 지역 · 수원'), findsNothing);
    },
  );

  tearDown(() {
    RegionContextStore.clear();
    OnboardingState.reset();
  });
}

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(LalaLocation(lat: 37.2636, lng: 127.0286));
}

/// getPlaces 를 Completer 로 지연시키는 테스트용 백엔드. pending 관측 후 에러로 종료.
class _PendingPlacesBackend implements LalaBackend {
  final Completer<LalaEnvelope<LalaPlacesResponse>> _placesCompleter =
      Completer<LalaEnvelope<LalaPlacesResponse>>();

  void completeError() =>
      _placesCompleter.completeError(StateError('search backend unavailable'));

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() =>
      _placesCompleter.future;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in search: ${invocation.memberName}');
}

/// 실제 장소(공식 이미지 포함)를 반환하는 테스트용 백엔드.
class _LoadedPlacesBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    LalaPlacesResponse(
      count: 1,
      places: <LalaPlace>[_cafe()],
      query: const LalaPlacesQuery(
        lat: 37.2636,
        lng: 127.0286,
        radiusM: 2000,
        limit: 60,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'postgis',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in search: ${invocation.memberName}');
}

LalaPlace _cafe() {
  return const LalaPlace(
    placeId: 'search-test-cafe',
    name: '행궁동 카페',
    nameKo: '행궁동 카페',
    nameEn: 'Haenggung Cafe',
    category: 'restaurant',
    lat: 37.2828,
    lng: 127.0101,
    address: '경기도 수원시 팔달구 행궁동',
    regionKo: '수원',
    regionEn: 'Suwon',
    imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/photo.jpg',
    distanceM: 320,
    source: 'db',
    upstreamSource: 'tour_api',
  );
}

LalaEnvelope<T> _envelope<T>(T data) {
  return LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const <String, dynamic>{'request_id': 'test-request-id'},
    error: null,
    statusCode: 200,
    requestId: 'test-request-id',
  );
}

/// Counts how many times the tab asked for device location. Used to prove a
/// store-driven reload does NOT re-request location.
class _CountingLocationProvider implements LalaLocationProvider {
  _CountingLocationProvider(this._result);

  final LalaLocationResult _result;
  int requests = 0;

  @override
  Future<LalaLocationResult> requestCurrentLocation() async {
    requests += 1;
    return _result;
  }
}

ManualLocationOption _busanOption() {
  return const ManualLocationOption(
    id: 'busan-haeundae',
    provinceId: 'busan',
    provinceKo: '부산광역시',
    provinceEn: 'Busan',
    labelKo: '해운대구',
    labelEn: 'Haeundae-gu',
    lat: 35.16,
    lng: 129.16,
  );
}
