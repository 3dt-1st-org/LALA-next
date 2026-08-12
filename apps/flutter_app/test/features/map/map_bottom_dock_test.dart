// P6H truthfulness: map bottom dock 의 data-as-of 신선도 라벨 검증.
// - data_as_of present → "데이터 기준: YYYY-MM-DD" 표시(영어: "Data as of: ...").
// - data_as_of null/불파식 → 라벨 부재(honest absence).
// 실제 snapshot generated_at 의 날짜 부분만 사용하고, 값이 없으면 절대 표시하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';

const LalaPlace _place = LalaPlace(
  placeId: 'p1',
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
  source: 'public_mvp_snapshot',
  upstreamSource: 'snapshot',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

MapBottomDock _dock({String? dataAsOf, String uiLanguage = 'ko'}) {
  return MapBottomDock(
    isWide: false,
    places: const <LalaPlace>[_place],
    source: 'public_mvp_snapshot',
    dataAsOf: dataAsOf,
    topPlace: _place,
    uiLanguage: uiLanguage,
    height: 240,
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

void main() {
  testWidgets(
    'freshness label shows the snapshot date when dataAsOf is present',
    (tester) async {
      await tester.pumpWidget(
        _wrap(_dock(dataAsOf: '2026-06-19T02:24:44.557686+00:00')),
      );
      await tester.pump();

      // 날짜 부분(YYYY-MM-DD)만 표시.
      expect(find.text('데이터 기준: 2026-06-19'), findsOneWidget);
    },
  );

  testWidgets(
    'freshness label is absent when dataAsOf is null (honest absence)',
    (tester) async {
      await tester.pumpWidget(_wrap(_dock(dataAsOf: null)));
      await tester.pump();

      expect(find.textContaining('데이터 기준'), findsNothing);
    },
  );

  testWidgets(
    'freshness label is absent when dataAsOf is not a parseable date',
    (tester) async {
      await tester.pumpWidget(_wrap(_dock(dataAsOf: 'not-a-date')));
      await tester.pump();

      expect(find.textContaining('데이터 기준'), findsNothing);
    },
  );

  testWidgets('english freshness label is exclusive (no Korean mixed in)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _dock(dataAsOf: '2026-06-19T02:24:44.557686+00:00', uiLanguage: 'en'),
      ),
    );
    await tester.pump();

    expect(find.text('Data as of: 2026-06-19'), findsOneWidget);
    // KO·EN 배타: 한국어 라벨이 섞이지 않는다.
    expect(find.textContaining('데이터 기준'), findsNothing);
  });
}
