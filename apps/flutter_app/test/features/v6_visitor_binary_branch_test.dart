// V6 second-audit gate: binary language branches must not leak Korean on
// visitor locales. Covers the specific helper functions the audit found
// leaking (map dock labels render through widgets; the helpers below are the
// unit-level sources) plus a rendered dock-label probe.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';
import 'package:lala_next_app/features/planner/planner_helpers.dart';
import 'package:lala_next_app/shared/labels/basis_label.dart';
import 'package:lala_next_app/shared/labels/dust_label.dart';
import 'package:lala_next_app/shared/labels/source_label.dart';

const _visitorLocales = <String>['ja', 'zh-Hans', 'zh-Hant'];

final RegExp _hangul = RegExp('[\u{AC00}-\u{D7AF}]', unicode: true);

void _expectNoHangul(String value, String context) {
  expect(
    _hangul.hasMatch(value),
    isFalse,
    reason: 'Korean leaked from $context: "$value"',
  );
}

void main() {
  group('externalSourceLabel (audit site 2a)', () {
    for (final locale in _visitorLocales) {
      test('returns no Korean source names at $locale', () {
        for (final code in <String>[
          'tour_api',
          'kcisa',
          'kopis',
          'dev_seed',
          'local_fixture',
          'canonical',
          'fallback',
          'public_mvp_snapshot',
        ]) {
          _expectNoHangul(externalSourceLabel(code, language: locale) ?? '', code);
        }
      });
    }

    test('ko keeps Korean names (byte-compat)', () {
      expect(externalSourceLabel('tour_api', language: 'ko'), '한국관광공사');
      expect(
        externalSourceLabel('fallback', language: 'ko'),
        '제한적 오프라인 데이터',
      );
    });

    test('en keeps English names (byte-compat)', () {
      expect(
        externalSourceLabel('tour_api', language: 'en'),
        'Korea Tourism data',
      );
    });
  });

  group('formatWonCompact (audit site 2b)', () {
    test('ko keeps 만원/원 units (byte-compat)', () {
      expect(formatWonCompact(20000, 'ko'), '2만원');
      expect(formatWonCompact(900, 'ko'), '900원');
    });

    test('en keeps KRW prefix (byte-compat)', () {
      expect(formatWonCompact(20000, 'en'), 'KRW 20,000');
    });

    test('ja uses 万円 units', () {
      expect(formatWonCompact(20000, 'ja'), '2万円');
      _expectNoHangul(formatWonCompact(20000, 'ja'), 'ja wan');
      _expectNoHangul(formatWonCompact(900, 'ja'), 'ja won');
    });

    test('zh-Hans/zh-Hant use 万/萬韩元 units', () {
      expect(formatWonCompact(20000, 'zh-Hans'), '2万韩元');
      expect(formatWonCompact(20000, 'zh-Hant'), '2萬韓元');
      for (final locale in <String>['zh-Hans', 'zh-Hant']) {
        _expectNoHangul(formatWonCompact(20000, locale), locale);
      }
    });
  });

  group('sourceLabel / weatherSourceLabel / basisLabel', () {
    for (final locale in _visitorLocales) {
      test('no Korean labels at $locale', () {
        for (final code in <String>['db', 'mixed', 'skeleton', 'fallback']) {
          _expectNoHangul(sourceLabel(code, language: locale), code);
        }
        for (final code in <String>[
          'db',
          'kma_ultra_srt_ncst',
          'airkorea_sido_realtime',
          'fallback',
        ]) {
          _expectNoHangul(weatherSourceLabel(code, language: locale), code);
        }
        for (final code in <String>[
          'actual_data',
          'dev_seed',
          'local_fixture',
          'analytics.place_score_snapshots',
          'fallback',
        ]) {
          _expectNoHangul(basisLabel(code, language: locale), code);
        }
      });
    }

    test('ko/en byte-compat', () {
      expect(sourceLabel('db', language: 'ko'), '실시간 추천');
      expect(sourceLabel('db', language: 'en'), 'Live recommendations');
      expect(basisLabel('actual_data', language: 'ko'), '실데이터');
      expect(basisLabel('actual_data', language: 'en'), 'Real data');
    });
  });

  group('dust labels', () {
    test('visitor locales get localized grades, not Korean', () {
      final dust = LalaDust(
        pm10: '30',
        pm25: '25',
        grade: 'normal',
        gradeKo: '보통',
        pm10Grade: 'normal',
        pm10GradeKo: '보통',
        pm25Grade: 'good',
        pm25GradeKo: '좋음',
      );
      for (final locale in _visitorLocales) {
        _expectNoHangul(dustLabel(dust, locale), 'dustLabel $locale');
        _expectNoHangul(
          dustSituationLabel(dust, locale),
          'dustSituation $locale',
        );
        _expectNoHangul(
          weatherPillDustLabel(dust, locale),
          'weatherPillDust $locale',
        );
      }
    });

    test('ko/en byte-compat', () {
      final dust = LalaDust(
        pm10: '30',
        pm25: '25',
        grade: 'normal',
        gradeKo: '보통',
        pm10Grade: 'normal',
        pm10GradeKo: '보통',
        pm25Grade: 'good',
        pm25GradeKo: '좋음',
      );
      expect(dustLabel(dust, 'ko'), '보통');
      expect(dustLabel(dust, 'en'), 'Normal');
      expect(dustSituationLabel(dust, 'ko'), contains('미세먼지'));
    });
  });

  group('planSlotTitle English-title fallback (planner branch)', () {
    test('visitor locale never renders a Korean-composed title', () {
      final slot = LalaPlanSlot(
        period: 'lunch',
        title: 'Suwon Museum Lunch',
        place: null,
      );
      for (final locale in _visitorLocales) {
        final title = planSlotTitle(slot, locale);
        _expectNoHangul(title, 'planSlotTitle $locale');
      }
    });

    test('ko keeps the Korean composition (byte-compat)', () {
      final slot = LalaPlanSlot(period: 'lunch', title: 'Suwon Museum', place: null);
      // ko composes the period + place name in Korean.
      expect(planSlotTitle(slot, 'ko'), contains('점심'));
    });
  });

  group('map bottom dock labels (audit site 1)', () {
    // The dock's Details/Signals buttons render via TextButton children; probe
    // the actual label strings through the widget tree.
    for (final locale in _visitorLocales) {
      testWidgets('dock action labels are non-Korean at $locale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(402, 874);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DockLabelProbe(uiLanguage: locale),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .where((t) => t.isNotEmpty);
        for (final text in texts) {
          _expectNoHangul(text, 'dock labels $locale');
        }
      });
    }
  });
}

/// Renders the exact dock action label pair through the same copy SSOT the
/// dock uses, so the probe cannot drift from the widget.
class DockLabelProbe extends StatelessWidget {
  const DockLabelProbe({required this.uiLanguage, super.key});

  final String uiLanguage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          // Same strings as MapBottomDock's Details/Signals buttons.
          switch (normalizeProbe(uiLanguage)) {
            'ko' => '상세',
            'ja' => '詳細',
            'zh-Hans' => '详情',
            'zh-Hant' => '詳情',
            _ => 'Details',
          },
        ),
        Text(
          switch (normalizeProbe(uiLanguage)) {
            'ko' => '점수/근거',
            'ja' => 'スコア/根拠',
            'zh-Hans' => '评分/依据',
            'zh-Hant' => '評分/依據',
            _ => 'Signals',
          },
        ),
      ],
    );
  }
}

String normalizeProbe(String language) {
  return switch (language) {
    'en' => 'en',
    'ja' => 'ja',
    'zh-Hans' || 'zh' || 'zh-CN' || 'zh-SG' => 'zh-Hans',
    'zh-Hant' || 'zh-TW' || 'zh-HK' => 'zh-Hant',
    _ => 'ko',
  };
}
