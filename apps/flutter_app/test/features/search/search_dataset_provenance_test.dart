// 검색 결과 카드의 dataset 출처/신선도 표시 회귀(lala-functional-ui-contract
// 02-screen-contracts S2 + 03-state-and-data-bindings §2).
// - 응답 envelope 의 실제 source/data_as_of 만 표시하고, 없으면 칩을 숨긴다.
// - 발명된 freshness/popularity/거리 값을 만들지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';

void main() {
  setUp(() {
    RegionContextStore.clear();
    OnboardingState.selectLanguage('ko');
  });

  testWidgets('loaded tile shows the real dataset source and data_as_of', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      backend: _ProvenanceBackend(
        source: 'db',
        dataAsOf: '2026-06-19T02:24:44.557686+00:00',
      ),
    );
    await tester.pumpAndSettle();

    // envelope.source='db' → 실제 라벨만(발명 문구 아님).
    expect(find.text('실시간 추천'), findsOneWidget);
    // data_as_of 의 날짜 부분만 표시.
    expect(find.text('데이터 기준: 2026-06-19'), findsOneWidget);
    // 원본 타임스탬프 전체를 그대로 노출하지 않는다.
    expect(find.textContaining('557686'), findsNothing);
  });

  testWidgets('empty source/data_as_of hides the provenance area (honest)', (
    tester,
  ) async {
    await _pumpSearch(tester, backend: _ProvenanceBackend(source: ''));
    await tester.pumpAndSettle();

    expect(find.text('실시간 추천'), findsNothing);
    expect(find.textContaining('데이터 기준'), findsNothing);
    // 빈 source 가 bare '-' 칩으로 새어 나가지 않는다.
    expect(find.text('-'), findsNothing);
  });

  testWidgets('unparseable data_as_of hides the freshness chip', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      backend: _ProvenanceBackend(source: 'db', dataAsOf: 'not-a-date'),
    );
    await tester.pumpAndSettle();

    expect(find.text('실시간 추천'), findsOneWidget);
    expect(find.textContaining('데이터 기준'), findsNothing);
  });

  testWidgets('EN locale shows localized provenance labels', (tester) async {
    await _pumpSearch(
      tester,
      backend: _ProvenanceBackend(
        source: 'db',
        dataAsOf: '2026-06-19T02:24:44.557686+00:00',
      ),
    );
    await tester.pumpAndSettle();

    OnboardingState.selectLanguage('en');
    await tester.pumpAndSettle();

    expect(find.text('Live recommendations'), findsOneWidget);
    expect(find.text('Data as of: 2026-06-19'), findsOneWidget);
    expect(find.text('실시간 추천'), findsNothing);
  });

  tearDown(() {
    RegionContextStore.clear();
    OnboardingState.reset();
  });
}

Future<void> _pumpSearch(WidgetTester tester, {required LalaBackend backend}) {
  return tester.pumpWidget(
    MaterialApp(
      home: SearchPage(
        locationProvider: _FoundLocationProvider(),
        backendFactory: (config) => backend,
      ),
    ),
  );
}

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(LalaLocation(lat: 37.2636, lng: 127.0286));
}

/// envelope 의 source/dataAsOf 만 제어하는 테스트용 백엔드.
class _ProvenanceBackend implements LalaBackend {
  _ProvenanceBackend({required this.source, this.dataAsOf});

  final String source;
  final String? dataAsOf;

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
      source: source,
      locationEngine: 'postgis',
      dataAsOf: dataAsOf,
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

LalaPlace _cafe() {
  return const LalaPlace(
    placeId: 'search-provenance-cafe',
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
