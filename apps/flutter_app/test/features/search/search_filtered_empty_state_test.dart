// D-2 회귀: 실제 결과가 있는 검색에서 query/카테고리 필터가 모든 결과를 걸러내면
// 빈 리스트가 아니라 로컬라이즈 빈 상태(_SearchEmptyView, 초기화 액션)를 보여준다.
// 초기화로 회복되는 것, 호환 필터에서는 여전히 결과 타일이 뜨는 것,
// transport empty(no-data) 카피와 필터 빈 상태 카피가 구분되는 것을 함께 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{'request_id': 'filtered-empty-test'},
  error: null,
  statusCode: 200,
  requestId: 'filtered-empty-test',
);

const LalaPlace _cafe = LalaPlace(
  placeId: 'filtered-empty-cafe',
  name: '행궁동 카페',
  nameKo: '행궁동 카페',
  nameEn: 'Haenggung Cafe',
  category: 'restaurant',
  lat: 37.2828,
  lng: 127.0101,
  address: '경기도 수원시 팔달구 행궁동',
  regionKo: '수원',
  regionEn: 'Suwon',
  distanceM: 320,
  source: 'db',
);

class _LoadedSearchBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    const LalaPlacesResponse(
      count: 1,
      places: <LalaPlace>[_cafe],
      query: LalaPlacesQuery(
        lat: 37.2828,
        lng: 127.0101,
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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'not used in filtered-empty: ${invocation.memberName}',
  );
}

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: 37.2828, lng: 127.0101)),
  );
}

/// 카테고리 칩 바의 특정 라벨 칩(결과 타일의 동일 문구 배지와 구분).
Finder _categoryChip(WidgetTester tester, String label) {
  return find
      .descendant(of: find.byType(FilterChip), matching: find.text(label))
      .first;
}

void main() {
  setUp(() {
    RegionContextStore.clear();
    OnboardingState.reset();
    OnboardingState.selectLanguage('ko');
  });

  tearDown(() {
    RegionContextStore.clear();
    OnboardingState.reset();
  });

  Future<void> pumpLoadedResults(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          locationProvider: _FoundLocationProvider(),
          backendFactory: (config) => _LoadedSearchBackend(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('행궁동 카페'), findsOneWidget);
  }

  testWidgets(
    'a query that matches nothing shows the localized filtered-empty view',
    (tester) async {
      await pumpLoadedResults(tester);

      await tester.enterText(find.byType(TextField), '없는 지역');
      await tester.pump();

      // 빈 리스트가 아니라 필터 빈 상태 + 초기화 액션.
      expect(
        find.byKey(const ValueKey('search-filtered-empty-view')),
        findsOneWidget,
      );
      expect(find.text('조건에 맞는 장소가 없어요.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-empty-reset-filters')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('search-empty-icon')), findsOneWidget);
      // transport no-data 카피와는 다른 문구다.
      expect(find.text('이 주변엔 아직 추천이 없어요.'), findsNothing);
      expect(find.text('이 주변 추천을 준비 중입니다.'), findsNothing);
    },
  );

  testWidgets(
    'an incompatible category shows the localized filtered-empty view',
    (tester) async {
      await pumpLoadedResults(tester);

      // 결과는 맛집(restaurant)뿐 — 명소(attraction) 칩은 모든 결과를 걸러낸다.
      // (타일 배지가 아닌 카테고리 '칩'을 정확히 탭한다.)
      await tester.tap(_categoryChip(tester, '명소'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('search-filtered-empty-view')),
        findsOneWidget,
      );
      expect(find.text('조건에 맞는 장소가 없어요.'), findsOneWidget);
      expect(find.text('이 주변 추천을 준비 중입니다.'), findsNothing);
      expect(find.text('행궁동 카페'), findsNothing);
    },
  );

  testWidgets('reset filters recovers the filtered-out results', (tester) async {
    await pumpLoadedResults(tester);

    await tester.enterText(find.byType(TextField), '없는 지역');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('search-filtered-empty-view')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('search-empty-reset-filters')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('search-filtered-empty-view')),
      findsNothing,
    );
    expect(find.text('행궁동 카페'), findsOneWidget);
  });

  testWidgets('a compatible filter still renders the result tiles', (
    tester,
  ) async {
    await pumpLoadedResults(tester);

    // 이름 매칭 검색어 + 호환 카테고리(맛집) — 결과 유지, 빈 상태 없음.
    await tester.enterText(find.byType(TextField), '행궁');
    await tester.pump();
    await tester.tap(_categoryChip(tester, '맛집'));
    await tester.pump();

    expect(find.text('행궁동 카페'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('search-filtered-empty-view')),
      findsNothing,
    );
    expect(find.text('조건에 맞는 장소가 없어요.'), findsNothing);
  });
}
