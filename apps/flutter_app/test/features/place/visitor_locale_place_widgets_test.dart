// Round 2 Lane A gate: place-feature surfaces must render real visitor-locale
// copy (ja / zh-Hans / zh-Hant), not the honest EN fallback, and must not leak
// a single Hangul codepoint. Extends the v6 no-Korean contract to the widgets
// migrated off the legacy two-language `lalaCopy` entry point.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/place/widgets/empty_place_state.dart';
import 'package:lala_next_app/features/place/widgets/event_info_card.dart';
import 'package:lala_next_app/features/place/widgets/event_status_pill.dart';
import 'package:lala_next_app/features/place/widgets/featured_place_panel.dart';
import 'package:lala_next_app/features/place/widgets/place_rail.dart';
import 'package:lala_next_app/features/place/widgets/public_data_proof_row.dart';
import 'package:lala_next_app/features/place/widgets/signal_grid.dart';

const _visitorLocales = <String>['ja', 'zh-Hans', 'zh-Hant'];

final RegExp _hangul = RegExp(
  '[\u{AC00}-\u{D7AF}\u{1100}-\u{11FF}]',
  unicode: true,
);

/// A fully-sourced place (db + score evidence) so the proof row takes the
/// "official data evidence" branch, and an event-flavored twin for the event
/// widgets.
LalaPlace _place(String locale) => LalaPlace(
  placeId: 'place-$locale',
  name: '수원 박물관',
  nameKo: '수원 박물관',
  nameEn: 'Suwon Museum',
  category: 'attraction',
  lat: 37.26,
  lng: 127.03,
  address: '경기도 수원시 영통구',
  distanceM: 800,
  source: 'db',
  regionKo: '수원시 영통구',
  regionEn: 'Yeongtong-gu, Suwon',
  score: const LalaPlaceScore(
    finalScore: 0.84,
    formulaVersion: 'test-v1',
    dataBasis: 'test evidence',
    features: <String, dynamic>{},
    components: LalaPlaceScoreComponents(
      localSpendingScore: 0.82,
      smallMerchantFitScore: 0.77,
      demandDispersionScore: 0.7,
      weatherFitScore: 0.91,
      reviewQualityScore: 0.75,
      cultureRelevanceScore: 0.68,
      accessibilityFitScore: null,
    ),
  ),
);

LalaPlace _eventPlace(String locale) => LalaPlace(
  placeId: 'event-$locale',
  name: '수원 화성 문화제',
  nameKo: '수원 화성 문화제',
  nameEn: 'Suwon Hwaseong Cultural Festival',
  category: 'event',
  lat: 37.28,
  lng: 127.01,
  address: '경기도 수원시 팔달구',
  distanceM: 1400,
  source: 'db',
  regionKo: '수원시 팔달구',
  regionEn: 'Paldal-gu, Suwon',
  isOngoing: true,
  eventStartDate: '2026-09-01T00:00:00+09:00',
  eventEndDate: '2026-09-30T00:00:00+09:00',
  eventUrl: 'https://example.org/festival',
);

List<String> _visibleTexts(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
}

void _expectNoKorean(WidgetTester tester, String locale, String surface) {
  final offenders = _visibleTexts(
    tester,
  ).where((text) => _hangul.hasMatch(text)).toList(growable: false);
  expect(
    offenders,
    isEmpty,
    reason:
        'Korean copy leaked onto the $surface surface for locale "$locale": '
        '$offenders',
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // FeaturedPlacePanel can embed the restaurant communication entry card,
    // whose store reads SharedPreferences.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final locale in _visitorLocales) {
    group('visitor copy at $locale', () {
      testWidgets('signal grid renders localized signal labels', (
        tester,
      ) async {
        await _pump(
          tester,
          SingleChildScrollView(
            child: SignalGrid(
              language: locale,
              localSpending: 0.82,
              demandDispersion: 0.7,
              cultureRelevance: 0.68,
              weatherFit: 0.91,
            ),
          ),
        );
        _expectNoKorean(tester, locale, 'signal grid');
        // The migration's point: real translations, not the EN fallback.
        expect(find.text('Local spending'), findsNothing);
        expect(find.text('No data yet'), findsNothing);
        final localizedLabel = switch (locale) {
          'ja' => '地元民の消費',
          'zh-Hans' => '本地人消费',
          _ => '本地人消費',
        };
        expect(find.text(localizedLabel), findsOneWidget);
      });

      testWidgets('signal grid empty state is localized', (tester) async {
        await _pump(
          tester,
          SignalGrid(
            language: locale,
            localSpending: null,
            demandDispersion: null,
            cultureRelevance: null,
            weatherFit: null,
          ),
        );
        _expectNoKorean(tester, locale, 'signal grid empty state');
        expect(find.text('No data yet'), findsNothing);
        final emptyLabel = switch (locale) {
          'ja' => 'データなし',
          'zh-Hans' => '暂无数据',
          _ => '暫無資料',
        };
        expect(find.text(emptyLabel), findsOneWidget);
      });

      testWidgets('event info card renders localized chrome', (tester) async {
        await _pump(
          tester,
          SingleChildScrollView(
            child: EventInfoCard(place: _eventPlace(locale), language: locale),
          ),
        );
        _expectNoKorean(tester, locale, 'event info card');
        expect(find.text('Event info'), findsNothing);
        final title = switch (locale) {
          'ja' => 'イベント情報',
          'zh-Hans' => '活动信息',
          _ => '活動資訊',
        };
        expect(find.text(title), findsOneWidget);
        final ongoing = switch (locale) {
          'ja' => '開催中',
          'zh-Hans' => '进行中',
          _ => '進行中',
        };
        expect(find.text(ongoing), findsOneWidget);
      });

      testWidgets('event status pill localizes the ended state', (
        tester,
      ) async {
        await _pump(
          tester,
          EventStatusPill(isOngoing: false, language: locale),
        );
        _expectNoKorean(tester, locale, 'event status pill');
        expect(find.text('Ended'), findsNothing);
        final ended = switch (locale) {
          'ja' => '終了',
          'zh-Hans' => '已结束',
          _ => '已結束',
        };
        expect(find.text(ended), findsOneWidget);
      });

      testWidgets('place rail header and count meta are localized', (
        tester,
      ) async {
        await _pump(
          tester,
          SingleChildScrollView(
            child: PlaceRail(
              places: <LalaPlace>[_place(locale), _eventPlace(locale)],
              source: 'db',
              language: locale,
            ),
          ),
        );
        _expectNoKorean(tester, locale, 'place rail');
        expect(find.text('Recommended places'), findsNothing);
        final header = switch (locale) {
          'ja' => 'おすすめスポット',
          'zh-Hans' => '推荐地点',
          _ => '推薦地點',
        };
        expect(find.text(header), findsOneWidget);
      });

      testWidgets('public data proof row localizes the evidence title', (
        tester,
      ) async {
        await _pump(
          tester,
          SingleChildScrollView(
            child: PublicDataProofRow(
              place: _place(locale),
              language: locale,
              source: 'db',
              weather: null,
              score: _place(locale).score,
            ),
          ),
        );
        _expectNoKorean(tester, locale, 'public data proof row');
        expect(find.text('Official data evidence'), findsNothing);
        final title = switch (locale) {
          'ja' => '公式データ根拠',
          'zh-Hans' => '官方数据依据',
          _ => '官方數據依據',
        };
        expect(find.text(title), findsOneWidget);
      });

      testWidgets('empty place state is localized', (tester) async {
        await _pump(tester, EmptyPlaceState(language: locale));
        _expectNoKorean(tester, locale, 'empty place state');
        expect(
          find.text('Recommendations are still being prepared here.'),
          findsNothing,
        );
        final label = switch (locale) {
          'ja' => 'この周辺のおすすめを準備中です。',
          'zh-Hans' => '正在准备这附近的推荐。',
          _ => '正在準備這附近的推薦。',
        };
        expect(find.text(label), findsOneWidget);
      });

      testWidgets('featured place panel toggle and preparing copy', (
        tester,
      ) async {
        await _pump(
          tester,
          SingleChildScrollView(
            child: FeaturedPlacePanel(
              place: null,
              language: locale,
              weather: null,
              intervention: null,
              dailyPlan: null,
              docentScript: null,
              docentAudio: null,
              audioLoading: false,
              audioError: null,
              liveSpeechEnabled: false,
              source: null,
              showEvidence: false,
              savedPlaceIds: const <String>{},
              detailDocentPlayedPlaceIds: const <String>{},
              onToggleEvidence: () {},
              onToggleSavedPlace: (_) {},
              onAddToPlan: () {},
              onFetchAudio: () {},
            ),
          ),
        );
        _expectNoKorean(tester, locale, 'featured place panel (empty)');
        expect(
          find.textContaining(
            'Recommendations are still being prepared here. Move the map',
          ),
          findsNothing,
        );

        await _pump(
          tester,
          SingleChildScrollView(
            child: FeaturedPlacePanel(
              place: _place(locale),
              language: locale,
              weather: null,
              intervention: null,
              dailyPlan: null,
              docentScript: null,
              docentAudio: null,
              audioLoading: false,
              audioError: null,
              liveSpeechEnabled: false,
              source: 'db',
              showEvidence: false,
              savedPlaceIds: const <String>{},
              detailDocentPlayedPlaceIds: const <String>{},
              onToggleEvidence: () {},
              onToggleSavedPlace: (_) {},
              onAddToPlan: () {},
              onFetchAudio: () {},
            ),
          ),
        );
        _expectNoKorean(tester, locale, 'featured place panel (loaded)');
        expect(find.text('Show signals'), findsNothing);
        final toggle = switch (locale) {
          'ja' => 'スコア・根拠を見る',
          'zh-Hans' => '查看评分和依据',
          _ => '查看評分和依據',
        };
        expect(find.text(toggle), findsOneWidget);
      });
    });
  }
}
