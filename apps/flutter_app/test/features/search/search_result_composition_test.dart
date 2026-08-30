// 검색 결과 행 재구성(S2 계약) 구조 회귀 — 픽셀 골든 없이 위젯 구조로 검증:
// - 카드/InkWell/미디어 프레임 반경 8dp(controlRadius).
// - 좌측 고정 미디어 프레임: 공식 이미지가 없으면 카테고리색 place 아이콘
//   placeholder(다른 장소 사진 대체 금지), 치수는 이미지 유무와 무관하게 동일.
// - 세로 순서: 장소명 → 한 줄 reason → compact 메타 → 실제 dataset 출처/신선도.
// - 결과 목록 gutter 24dp(pageGutter).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/place/widgets/category_badge.dart';
import 'package:lala_next_app/features/place/widgets/place_image.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';

void main() {
  setUp(() {
    RegionContextStore.clear();
    OnboardingState.selectLanguage('ko');
  });

  testWidgets('result card, inkwell, and media frame use the 8dp radius', (
    tester,
  ) async {
    await _pumpSearch(tester, backend: _CompositionBackend(withImage: true));
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('search-place-tile-search-cafe'));
    expect(tile, findsOneWidget);

    final card = tester.widget<Container>(tile);
    final decoration = card.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(LalaVisualTokens.controlRadius),
    );

    // InkWell 은 카드 Container 의 상위(탭 키로 직접 참조).
    final inkwell = tester.widget<InkWell>(
      find.byKey(const ValueKey('search-place-tile-tap-search-cafe')),
    );
    expect(
      inkwell.borderRadius,
      BorderRadius.circular(LalaVisualTokens.controlRadius),
    );

    final mediaFrame = tester.widget<Container>(
      find.byKey(const ValueKey('search-place-media-search-cafe')),
    );
    final mediaDecoration = mediaFrame.decoration! as BoxDecoration;
    expect(
      mediaDecoration.borderRadius,
      BorderRadius.circular(LalaVisualTokens.controlRadius),
    );
  });

  testWidgets('official image renders inside the fixed left media frame', (
    tester,
  ) async {
    await _pumpSearch(tester, backend: _CompositionBackend(withImage: true));
    await tester.pumpAndSettle();

    final frame = find.byKey(const ValueKey('search-place-media-search-cafe'));
    expect(tester.getSize(frame), const Size(96, 88));
    // 공식 이미지 슬롯만 존재(빌려온/발명 이미지 아님).
    expect(
      find.descendant(of: frame, matching: find.byType(PlaceImage)),
      findsOneWidget,
    );
  });

  testWidgets('missing image keeps the frame size with an honest placeholder', (
    tester,
  ) async {
    await _pumpSearch(tester, backend: _CompositionBackend(withImage: false));
    await tester.pumpAndSettle();

    final frame = find.byKey(const ValueKey('search-place-media-search-cafe'));
    // 이미지 부재에도 치수가 흔들리지 않는다.
    expect(tester.getSize(frame), const Size(96, 88));

    // 실제 이미지 위젯은 없고 카테고리색 place 아이콘 placeholder 를 둔다.
    expect(
      find.descendant(of: frame, matching: find.byType(PlaceImage)),
      findsNothing,
    );
    final placeholderIcon = tester.widget<Icon>(
      find.descendant(of: frame, matching: find.byType(Icon)),
    );
    expect(placeholderIcon.icon, Icons.place_rounded);
    expect(placeholderIcon.color, LalaVisualColors.restaurant);
  });

  testWidgets(
    'row reads name, one-line reason, compact meta, then provenance',
    (tester) async {
      await _pumpSearch(tester, backend: _CompositionBackend(withImage: false));
      await tester.pumpAndSettle();

      final nameTop = tester.getTopLeft(find.text('행궁동 카페')).dy;
      final reasonTop = tester.getTopLeft(find.text('영업중 · 근접')).dy;
      final metaTop = tester.getTopLeft(find.byType(CategoryBadge)).dy;
      final provenanceTop = tester.getTopLeft(find.text('실시간 추천')).dy;

      expect(nameTop, lessThan(reasonTop));
      expect(reasonTop, lessThan(metaTop));
      expect(metaTop, lessThan(provenanceTop));
    },
  );

  testWidgets('results list uses the 24dp page gutter', (tester) async {
    await _pumpSearch(tester, backend: _CompositionBackend(withImage: false));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('search-results-view')),
    );
    expect(
      list.padding,
      const EdgeInsets.fromLTRB(
        LalaVisualTokens.pageGutter,
        8,
        LalaVisualTokens.pageGutter,
        24,
      ),
    );
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

/// 재구성 검증용 백엔드 — 공식 이미지 유무만 제어(출처/기준시각은 실제 값).
class _CompositionBackend implements LalaBackend {
  _CompositionBackend({required this.withImage});

  final bool withImage;

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
    LalaPlacesResponse(
      count: 1,
      places: <LalaPlace>[_cafe(withImage)],
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
      dataAsOf: '2026-06-19T02:24:44.557686+00:00',
    ),
  );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

LalaPlace _cafe(bool withImage) {
  return LalaPlace(
    placeId: 'search-cafe',
    name: '행궁동 카페',
    nameKo: '행궁동 카페',
    nameEn: 'Haenggung Cafe',
    category: 'restaurant',
    lat: 37.2828,
    lng: 127.0101,
    address: '경기도 수원시 팔달구 행궁동',
    regionKo: '수원',
    regionEn: 'Suwon',
    imageUrl: withImage
        ? 'https://tong.visitkorea.or.kr/cms/resource/photo.jpg'
        : null,
    distanceM: 320,
    reason: '영업중 · 근접',
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
