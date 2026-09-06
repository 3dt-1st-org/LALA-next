// Truthful localized unknown-state labels: raw internal enum tokens
// (`unknown`, unrecognized grade codes) must never reach users in any of the
// five locales; known grades and measured numbers stay meaningful; empty
// sources stay empty (no fabricated observations).
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/weather/weather_helpers.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';
import 'package:lala_next_app/shared/labels/dust_label.dart';

const _locales = ['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant'];

const _unknownByLocale = {
  'ko': '정보 없음',
  'en': 'Information unavailable',
  'ja': '情報なし',
  'zh-Hans': '暂无信息',
  'zh-Hant': '暫無資訊',
};

void main() {
  group('outdoorLabel', () {
    for (final locale in _locales) {
      test('unknown/unsupported status never leaks raw tokens ($locale)', () {
        for (final status in ['unknown', 'unavailable', 'weird_status']) {
          final label = outdoorLabel(status, language: locale);
          expect(label, _unknownByLocale[locale]);
          expect(label, isNot(status));
        }
      });
      test('known statuses unchanged ($locale)', () {
        expect(
          outdoorLabel('good', language: locale),
          isNot(_unknownByLocale[locale]),
        );
        expect(
          outdoorLabel('bad', language: locale),
          isNot(_unknownByLocale[locale]),
        );
      });
    }
    test('intentional blank stays blank', () {
      expect(outdoorLabel('', language: 'en'), '');
    });
  });

  group('dustGradeLabel', () {
    for (final locale in _locales) {
      test('unknown grade code never leaks raw tokens ($locale)', () {
        for (final code in ['unknown', 'moderate_alt', '???']) {
          final label = dustGradeLabel(code, '', locale);
          expect(label, _unknownByLocale[locale], reason: '$code @ $locale');
          expect(label, isNot(code));
        }
      });
      test('known grades unchanged ($locale)', () {
        expect(
          dustGradeLabel('good', '좋음', locale),
          isNot(_unknownByLocale[locale]),
        );
        expect(
          dustGradeLabel('very_bad', '매우 나쁨', locale),
          isNot(_unknownByLocale[locale]),
        );
      });
    }
    test('intentional blank stays blank in every locale', () {
      for (final locale in _locales) {
        expect(dustGradeLabel('', '', locale), '', reason: locale);
      }
    });
    test('KO keeps the Korean grade name when provided', () {
      expect(dustGradeLabel('normal', '보통', 'ko'), '보통');
    });
    test('KO unknown code with missing Korean name is localized', () {
      expect(dustGradeLabel('unknown', '', 'ko'), '정보 없음');
    });
  });

  group('publicWeatherSummary', () {
    test(
      'real temp + unknown condition/dust: no raw token, temp preserved',
      () {
        const weather = LalaWeather(
          lat: 37.26,
          lng: 127.02,
          temp: '23',
          icon: 'partly-cloudy',
          dust: LalaDust(
            pm10: '40',
            pm25: '20',
            grade: 'unknown',
            gradeKo: '',
            pm10Grade: 'unknown',
            pm10GradeKo: '',
            pm25Grade: 'unknown',
            pm25GradeKo: '',
          ),
          forecast: <LalaForecastItem>[],
          outdoorStatus: 'unknown',
          force: false,
          source: 'kma',
        );
        final result = publicWeatherSummary(weather, 'zh-Hant');
        expect(result.summary, isNotNull);
        expect(result.summary!, contains('23°C'));
        expect(result.summary!, contains('暫無資訊'));
        expect(result.summary!, isNot(contains('unknown')));
      },
    );

    test('null/placeholder weather stays honest null', () {
      expect(publicWeatherSummary(null, 'en').summary, isNull);
    });
  });
}
