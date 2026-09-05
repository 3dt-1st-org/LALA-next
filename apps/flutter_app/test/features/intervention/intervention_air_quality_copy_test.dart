// P4: 미세먼지(AQ) 개입 트리거의 사용자 노출 검증.
// - 배지 라벨 SSOT(interventionTriggerBadgeLabel): 전 트리거 × 5개 로케일.
// - 나쁜 대기질이 '날씨 변화'(또는 그 번역)로만 표시되는 일이 없다.
// - honest fallback 카피(interventionToastLabel): AQ 트리거 × 5개 로케일 단일 언어.
// - S-20: 320dp + TextScaler.linear(2) 오버플로 없음(AQ 배지 + 대안 없음 + 재생성).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/features/intervention/widgets/intervention_toast.dart';

LalaIntervention _intervention({
  String? triggerType,
  String reason = '',
  String recommendedAction = '',
  LalaPlace? place,
}) {
  return LalaIntervention(
    center: const LalaCoordinate(lat: 37.0, lng: 127.0),
    radiusM: 1000,
    shouldIntervene: true,
    reason: reason,
    recommendedAction: recommendedAction,
    source: 'test',
    triggerType: triggerType,
    place: place,
  );
}

const List<String> _kLanguages = <String>[
  'ko',
  'en',
  'ja',
  'zh-Hans',
  'zh-Hant',
];

void main() {
  group('P4 — interventionTriggerBadgeLabel covers every trigger in 5 locales', () {
    const badgeByTrigger = <String, String>{
      'closure_detected': '폐업 의심',
      'bad_air_quality': '미세먼지 나쁨',
      'bad_weather': '날씨 변화',
      'bad_weather_and_closure': '날씨 + 폐업',
      'bad_weather_and_air_quality': '날씨 + 미세먼지',
      'bad_air_quality_and_closure': '미세먼지 + 폐업',
      'bad_weather_and_air_quality_and_closure': '날씨 + 미세먼지 + 폐업',
    };

    test('KO badge per trigger (exact copy)', () {
      badgeByTrigger.forEach((trigger, koLabel) {
        expect(interventionTriggerBadgeLabel(trigger, 'ko'), koLabel);
      });
    });

    test('every trigger has a non-empty single-language badge in 5 locales', () {
      for (final trigger in badgeByTrigger.keys) {
        for (final language in _kLanguages) {
          final label = interventionTriggerBadgeLabel(trigger, language);
          expect(label, isNotNull, reason: '$trigger/$language');
          expect(label!.trim(), isNotEmpty, reason: '$trigger/$language');
          if (language != 'ko') {
            expect(RegExp(r'[가-힣]').hasMatch(label), isFalse,
                reason: '$trigger/$language must not leak Korean');
          }
        }
      }
    });

    test('AQ-only trigger never renders the weather badge label', () {
      const weatherOnlyLabels = <String>{
        '날씨 변화',
        'Weather change',
        '気象の変化',
        '天气变化',
        '天氣變化',
      };
      for (final language in _kLanguages) {
        final label = interventionTriggerBadgeLabel('bad_air_quality', language);
        expect(weatherOnlyLabels, isNot(contains(label)),
            reason: 'AQ-only badge must be distinct in $language');
      }
    });

    test('null/unknown trigger keeps no badge (honest)', () {
      expect(interventionTriggerBadgeLabel(null, 'ko'), isNull);
      expect(interventionTriggerBadgeLabel('something_new', 'en'), isNull);
    });
  });

  group('P4 — interventionToastLabel honest fallback for AQ triggers', () {
    test('bad_air_quality KO → AQ copy, no weather wording', () {
      final label = interventionToastLabel(_intervention(triggerType: 'bad_air_quality'), 'ko');
      expect(label, contains('미세먼지가 나빠요'));
      expect(label, isNot(contains('날씨가 바뀌었어요')));
      expect(label, isNot(contains('날씨와')));
    });

    test('bad_air_quality EN → AQ copy, single-language', () {
      final label = interventionToastLabel(_intervention(triggerType: 'bad_air_quality'), 'en');
      expect(label, contains('Air quality is poor'));
      expect(label, isNot(contains('Weather changed')));
      expect(RegExp(r'[가-힣]').hasMatch(label), isFalse);
    });

    test('bad_air_quality + place KO mentions the place', () {
      final label = interventionToastLabel(
        _intervention(
          triggerType: 'bad_air_quality',
          place: LalaPlace(
            placeId: 'p1',
            name: '카페 솔',
            nameKo: '카페 솔',
            nameEn: 'Cafe Sol',
            category: 'cafe',
            lat: 37.0,
            lng: 127.0,
            address: '서울',
            distanceM: 120,
            source: 'test',
          ),
        ),
        'ko',
      );
      expect(label, contains('미세먼지가 나빠요'));
      expect(label, contains('카페 솔'));
    });

    test('combined weather+AQ fallback mentions both causes (KO/EN exclusive)', () {
      final ko = interventionToastLabel(
        _intervention(triggerType: 'bad_weather_and_air_quality'),
        'ko',
      );
      final en = interventionToastLabel(
        _intervention(triggerType: 'bad_weather_and_air_quality'),
        'en',
      );
      expect(ko, contains('날씨와 미세먼지가 모두 좋지 않아요'));
      expect(en, contains('Weather and air quality are both poor'));
      expect(RegExp(r'[가-힣]').hasMatch(en), isFalse);
    });

    test('AQ+closure fallback mentions both causes', () {
      final ko = interventionToastLabel(
        _intervention(triggerType: 'bad_air_quality_and_closure'),
        'ko',
      );
      final en = interventionToastLabel(
        _intervention(triggerType: 'bad_air_quality_and_closure'),
        'en',
      );
      expect(ko, contains('미세먼지가 나쁘고'));
      expect(ko, contains('영업 중이 아닐'));
      expect(en, contains('Air quality is poor'));
      expect(en, contains('may be closed'));
    });

    test('weather+AQ+closure fallback mentions all three causes', () {
      final ko = interventionToastLabel(
        _intervention(triggerType: 'bad_weather_and_air_quality_and_closure'),
        'ko',
      );
      final en = interventionToastLabel(
        _intervention(triggerType: 'bad_weather_and_air_quality_and_closure'),
        'en',
      );
      expect(ko, contains('날씨와 미세먼지가 좋지 않고'));
      expect(ko, contains('영업 중이 아닐'));
      expect(en, contains('Weather and air quality are poor'));
      expect(en, contains('may be closed'));
    });

    test('AQ fallback is single-language across 5 locales', () {
      for (final language in _kLanguages) {
        if (language == 'ko') {
          continue;
        }
        for (final trigger in <String>[
          'bad_air_quality',
          'bad_weather_and_air_quality',
          'bad_air_quality_and_closure',
          'bad_weather_and_air_quality_and_closure',
        ]) {
          final label = interventionToastLabel(_intervention(triggerType: trigger), language);
          expect(label.trim(), isNotEmpty, reason: '$trigger/$language');
          expect(RegExp(r'[가-힣]').hasMatch(label), isFalse,
              reason: '$trigger/$language must not leak Korean');
        }
      }
    });

    test('API reason/action still win over the AQ fallback (copy priority intact)', () {
      final label = interventionToastLabel(
        _intervention(
          triggerType: 'bad_air_quality',
          reason: '미세먼지가 나빠져 실내 대안을 추천해요.',
          recommendedAction: '실내 전시로 바꿔보세요.',
        ),
        'ko',
      );
      expect(label, contains('미세먼지가 나빠져'));
      expect(label, isNot(contains('실내 동선을 확인해보세요')));
    });
  });

  group('S-20 — AQ toast overflow safety', () {
    Future<void> pumpToast(
      WidgetTester tester, {
      String language = 'ko',
      TextScaler textScaler = TextScaler.noScaling,
      Size size = const Size(402, 874),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: InterventionToast(
                label: interventionToastLabel(
                  _intervention(triggerType: 'bad_air_quality'),
                  language,
                ),
                language: language,
                onOpenPlanner: () {},
                onDismiss: () {},
                triggerBadge: interventionTriggerBadgeLabel('bad_air_quality', language),
                noAlternativeLabel: language == 'ko' ? '지금은 대체 장소가 없어요.' : 'No alternative right now.',
                regenerateLabel: language == 'ko' ? '일정 다시 짜기' : 'Regenerate',
                onRegenerate: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('320dp width: AQ badge + honest no-alternative, no overflow', (tester) async {
      await pumpToast(tester, size: const Size(320, 640));
      expect(find.text('미세먼지 나쁨'), findsOneWidget);
      expect(find.text('지금은 대체 장소가 없어요.'), findsOneWidget);
      final width = tester.getSize(find.byType(InterventionToast)).width;
      expect(width, lessThanOrEqualTo(430));
      expect(tester.takeException(), isNull);
    });

    testWidgets('320dp + TextScaler.linear(2): AQ toast wraps without overflow', (tester) async {
      await pumpToast(
        tester,
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 800),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('320dp + TextScaler.linear(2) in EN stays single-language', (tester) async {
      await pumpToast(
        tester,
        language: 'en',
        textScaler: const TextScaler.linear(2),
        size: const Size(320, 800),
      );
      expect(find.text('Poor air quality'), findsOneWidget);
      expect(find.text('날씨 변화'), findsNothing);
      expect(find.text('Weather change'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
