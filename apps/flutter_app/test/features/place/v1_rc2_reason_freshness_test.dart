// V1-RC2: reason + freshness binding consistency across surfaces.
// - 각 LIVE 표면(MapRailPlaceCard / MapBottomDock / FeaturedPlaceHeader) 과 dormant
//   RecommendedPlaceCard 가 place.reason / place.freshness 를 동일 원문으로 렌더.
// - honest omission: reason/freshness null → 해당 줄/칩 미출력(placeholder 금지).
// - D-2: 독의 데이터셋 dataAsOf 칩은 per-place freshness 와 별개로 존재 유지.
// - 일관성: 하나의 LalaPlace → 모든 표면에서 동일 reason 텍스트.
// - SSOT: placeCardSemanticsLabel 이 reason 을 포함/제외.
// freshness 는 API 가 보낸 정적 문자열이므로 frozen-clock 불필요(픽스처 사용).
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';
import 'package:lala_next_app/features/map/widgets/map_place_carousel_overlay.dart';
import 'package:lala_next_app/features/place/place_helpers.dart';
import 'package:lala_next_app/features/place/widgets/featured_place_header.dart';
import 'package:lala_next_app/features/place/widgets/map_rail_place_card.dart';
import 'package:lala_next_app/features/place/widgets/recommended_place_card.dart';

const String _reason = '영업중 · 근접';
const String _freshness = '5분 전';

LalaPlace _place({String? reason = _reason, String? freshness = _freshness}) {
  return LalaPlace(
    placeId: 'rc2-p1',
    name: '행궁동 카페',
    nameKo: '행궁동 카페',
    nameEn: 'Haenggung Cafe',
    category: 'restaurant',
    lat: 37.28,
    lng: 127.01,
    address: '경기도 수원시 팔달구',
    regionKo: '수원',
    regionEn: 'Suwon',
    distanceM: 210,
    source: 'db',
    upstreamSource: 'tour_api',
    imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/x.jpg',
    reason: reason,
    freshness: freshness,
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

MapBottomDock _dock({required LalaPlace place, String? dataAsOf}) {
  return MapBottomDock(
    isWide: false,
    places: <LalaPlace>[place],
    source: 'db',
    dataAsOf: dataAsOf,
    topPlace: place,
    uiLanguage: 'ko',
    height: 320,
    docentScript: null,
    docentAudio: null,
    docentAction: null,
    audioLoading: false,
    audioError: null,
    canFetchAudio: false,
    showEvidence: false,
    error: null,
    placeFailureKind: null,
    recommendationRecoveryPending: false,
    onFetchAudio: () {},
    onAddToPlan: () {},
    onOpenDetail: () {},
    onRefresh: () {},
    onToggleEvidence: () {},
  );
}

/// 시맨틱 트리 전체에서 [containing] 를 label 로 갖는 노드가 있는지 탐색.
bool _hasSemanticsLabel(WidgetTester tester, {required String containing}) {
  final root = tester.getSemantics(find.byType(MaterialApp));
  bool deep(SemanticsNode node) {
    if (node.label.contains(containing)) return true;
    var found = false;
    node.visitChildren((child) {
      if (!found) found = deep(child);
      return !found;
    });
    return found;
  }

  return deep(root);
}

void main() {
  group(
    'MapRailPlaceCard reason (D-1: reason yes, freshness n/a on compact)',
    () {
      testWidgets('shows reason line when present', (tester) async {
        await tester.pumpWidget(
          _wrap(
            MapRailPlaceCard(
              place: _place(),
              language: 'ko',
              selected: false,
              compact: true,
            ),
          ),
        );
        expect(find.text(_reason), findsOneWidget);
      });

      testWidgets('omits reason line honestly when null', (tester) async {
        await tester.pumpWidget(
          _wrap(
            MapRailPlaceCard(
              place: _place(reason: null),
              language: 'ko',
              selected: false,
              compact: true,
            ),
          ),
        );
        expect(find.text(_reason), findsNothing);
        expect(find.textContaining('이유'), findsNothing); // no placeholder
      });

      testWidgets('carousel card label announces reason via SSOT', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            MapRailPlaceCard(
              place: _place(),
              language: 'ko',
              selected: false,
              compact: true,
            ),
          ),
        );
        expect(_hasSemanticsLabel(tester, containing: _reason), isTrue);
      });
    },
  );

  group('MapBottomDock reason + per-place freshness (D-2)', () {
    testWidgets('shows per-place reason and freshness when present', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_dock(place: _place(), dataAsOf: null)));
      await tester.pump();
      expect(find.text(_reason), findsOneWidget);
      expect(find.text(_freshness), findsOneWidget);
    });

    testWidgets('omits reason and per-place freshness honestly when null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_dock(place: _place(reason: null, freshness: null))),
      );
      await tester.pump();
      expect(find.text(_reason), findsNothing);
      expect(find.text(_freshness), findsNothing);
    });

    testWidgets(
      'dataset dataAsOf chip stays distinct from per-place freshness (D-2)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            _dock(
              place: _place(),
              dataAsOf: '2026-06-19T02:24:44.557686+00:00',
            ),
          ),
        );
        await tester.pump();
        // per-place freshness (장소 단위)
        expect(find.text(_freshness), findsOneWidget);
        // dataset as-of chip (별개 컨셉, 변경 없음)
        expect(find.text('데이터 기준: 2026-06-19'), findsOneWidget);
      },
    );
  });

  group('FeaturedPlaceHeader reason + freshness', () {
    testWidgets('shows reason and freshness when present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FeaturedPlaceHeader(
            place: _place(),
            language: 'ko',
            showEvidence: false,
            saved: false,
            onToggleSaved: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_reason), findsOneWidget);
      expect(find.text(_freshness), findsOneWidget);
    });

    testWidgets('omits reason and freshness honestly when null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FeaturedPlaceHeader(
            place: _place(reason: null, freshness: null),
            language: 'ko',
            showEvidence: false,
            saved: false,
            onToggleSaved: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_reason), findsNothing);
      expect(find.text(_freshness), findsNothing);
    });
  });

  group(
    'RecommendedPlaceCard reason + freshness (dormant, forward-compat)',
    () {
      testWidgets('shows reason and freshness when present', (tester) async {
        await tester.pumpWidget(
          _wrap(
            RecommendedPlaceCard(
              place: _place(),
              selected: false,
              language: 'ko',
            ),
          ),
        );
        expect(find.text(_reason), findsOneWidget);
        expect(find.text(_freshness), findsOneWidget);
      });

      testWidgets('omits reason and freshness honestly when null', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            RecommendedPlaceCard(
              place: _place(reason: null, freshness: null),
              selected: false,
              language: 'ko',
            ),
          ),
        );
        expect(find.text(_reason), findsNothing);
        expect(find.text(_freshness), findsNothing);
      });
    },
  );

  group('consistency: one LalaPlace → identical reason text across surfaces', () {
    // carousel(carousel_overlay 안의 MapRailPlaceCard) + dock + header + recommended
    // card 가 모두 동일 place.reason 원문을 렌더하는지 확인.
    testWidgets('carousel card renders the shared reason', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MapPlaceCarouselOverlay(
            places: <LalaPlace>[_place()],
            source: 'db',
            language: 'ko',
            selectedPlaceId: 'rc2-p1',
            explicitSelectedPlaceId: null,
            expanded: true,
            compact: true,
            onSelectPlace: (_) {},
            onReselectSelectedPlace: () {},
            onToggleExpanded: () {},
          ),
        ),
      );
      expect(find.text(_reason), findsOneWidget);
    });

    testWidgets('dock renders the shared reason', (tester) async {
      await tester.pumpWidget(_wrap(_dock(place: _place())));
      await tester.pump();
      expect(find.text(_reason), findsOneWidget);
    });

    testWidgets('header renders the shared reason', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FeaturedPlaceHeader(
            place: _place(),
            language: 'ko',
            showEvidence: false,
            saved: false,
            onToggleSaved: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_reason), findsOneWidget);
    });

    testWidgets('recommended card renders the shared reason', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecommendedPlaceCard(
            place: _place(),
            selected: false,
            language: 'ko',
          ),
        ),
      );
      expect(find.text(_reason), findsOneWidget);
    });
  });

  group('a11y SSOT: placeCardSemanticsLabel', () {
    final place = _place();

    test('includes reason when present', () {
      expect(placeCardSemanticsLabel(place, 'ko').contains(_reason), isTrue);
    });

    test('excludes reason when absent', () {
      final noReason = _place(reason: null);
      expect(
        placeCardSemanticsLabel(noReason, 'ko').contains(_reason),
        isFalse,
      );
      // freshness is visual-only in the label (search-tile RC1 pattern).
      expect(
        placeCardSemanticsLabel(
          _place(freshness: '방금 전'),
          'ko',
        ).contains('방금 전'),
        isFalse,
      );
    });
  });
}
