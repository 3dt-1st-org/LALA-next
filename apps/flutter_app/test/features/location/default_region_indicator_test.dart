// Wave-1 location/weather: focused widget tests for honest default-region
// disclosure and manual-context propagation in the search tab.
//
// - When no real region context exists (location denied), the disclosed default
//   region indicator is shown and the default coordinates drive the call.
// - When a current location resolves, the indicator is hidden.
// - A manual choice retained in RegionContextStore drives the call coordinates
//   (the onboarding choice is not discarded).
// - The indicator copy stays in a single language.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/location/widgets/default_region_indicator.dart';
import 'package:lala_next_app/features/place/widgets/place_thumb.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';
import 'package:lala_next_app/manual_location_options.dart';

const ManualLocationOption _busanHaeundae = ManualLocationOption(
  id: 'busan-haeundae',
  provinceId: 'busan',
  provinceKo: '부산광역시',
  provinceEn: 'Busan',
  labelKo: '해운대구',
  labelEn: 'Haeundae-gu',
  lat: 35.16,
  lng: 129.16,
);

class _DeniedLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.denied();
}

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(LalaLocation(lat: 37.2636, lng: 127.0286));
}

class _EmptyPlacesBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope();

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

LalaEnvelope<LalaPlacesResponse> _envelope() {
  return LalaEnvelope<LalaPlacesResponse>(
    ok: true,
    data: LalaPlacesResponse(
      count: 0,
      places: const <LalaPlace>[],
      query: const LalaPlacesQuery(
        lat: 0,
        lng: 0,
        radiusM: 2000,
        limit: 60,
        category: 'all',
        language: 'ko',
      ),
      source: 'db',
      locationEngine: 'postgis',
    ),
    meta: const <String, dynamic>{'request_id': 'test'},
    error: null,
    statusCode: 200,
    requestId: 'test',
  );
}

void main() {
  // The store is a process-local singleton; isolate every case.
  setUp(RegionContextStore.clear);

  group('DefaultRegionIndicator copy', () {
    testWidgets('Korean copy is exclusive', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DefaultRegionIndicator(language: 'ko')),
        ),
      );
      expect(find.text('현재 위치 대신 기본 지역(수원) 추천을 보여드려요'), findsOneWidget);
      expect(find.textContaining('Showing the default region'), findsNothing);
    });

    testWidgets('English copy is exclusive', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DefaultRegionIndicator(language: 'en')),
        ),
      );
      expect(
        find.text('Showing the default region (Suwon), not your location'),
        findsOneWidget,
      );
      expect(find.textContaining('기본 지역'), findsNothing);
    });
  });

  group('SearchPage region context', () {
    testWidgets(
      'shows the default indicator and uses default coords when location is denied',
      (tester) async {
        final configs = <LalaAppConfig>[];
        await tester.pumpWidget(
          MaterialApp(
            home: SearchPage(
              locationProvider: _DeniedLocationProvider(),
              backendFactory: (config) {
                configs.add(config);
                return _EmptyPlacesBackend();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('현재 위치 대신 기본 지역(수원) 추천을 보여드려요'), findsOneWidget);
        // No real context → disclosed default coordinates drive the call.
        expect(configs.last.lat, 37.2636);
        expect(configs.last.lng, 127.0286);
      },
    );

    testWidgets('hides the default indicator when location is found', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) => _EmptyPlacesBackend(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DefaultRegionIndicator), findsNothing);
    });

    testWidgets('a retained manual context drives the call coordinates', (
      tester,
    ) async {
      RegionContextStore.set(RegionContext.manual(_busanHaeundae));
      final configs = <LalaAppConfig>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            // Denied geolocation must not overwrite the retained manual choice.
            locationProvider: _DeniedLocationProvider(),
            backendFactory: (config) {
              configs.add(config);
              return _EmptyPlacesBackend();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The onboarding manual choice is retained into the shell.
      expect(configs.last.lat, 35.16);
      expect(configs.last.lng, 129.16);
      expect(find.byType(DefaultRegionIndicator), findsNothing);
    });

    testWidgets('empty backend shows empty state, never bundled places', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _DeniedLocationProvider(),
            backendFactory: (config) => _EmptyPlacesBackend(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No query/category filter → neutral empty copy, not invented places.
      expect(find.text('이 주변 추천을 준비 중입니다.'), findsWidgets);
      expect(find.byType(PlaceThumb), findsNothing);
    });
  });
}
