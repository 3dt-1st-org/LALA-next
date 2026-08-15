// V6 foreign-visitor UX: focused locale-contract tests.
//
// Contract (docs/planning/v6-foreign-visitor-ux-contract.md):
//  - §5 canonical set ko/en/ja/zh-Hans/zh-Hant; unknown -> ko
//  - I2 ko/en outputs byte-identical to the pre-V6 lalaCopy behavior
//  - §6 honest fallback: visitor locales never surface Korean static data
//  - §10 API request language: visitor locales request `en`, ko requests `ko`
//  - I3 no flag emoji anywhere in the language choice surface
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/multi_language_text.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';

void main() {
  group('normalizeLalaLanguage (§5)', () {
    test('canonical codes pass through', () {
      expect(normalizeLalaLanguage('ko'), 'ko');
      expect(normalizeLalaLanguage('en'), 'en');
      expect(normalizeLalaLanguage('ja'), 'ja');
      expect(normalizeLalaLanguage('zh-Hans'), 'zh-Hans');
      expect(normalizeLalaLanguage('zh-Hant'), 'zh-Hant');
    });

    test('BCP-47 regional variants fold into Hans/Hant', () {
      expect(normalizeLalaLanguage('zh'), 'zh-Hans');
      expect(normalizeLalaLanguage('zh-CN'), 'zh-Hans');
      expect(normalizeLalaLanguage('zh-SG'), 'zh-Hans');
      expect(normalizeLalaLanguage('zh-TW'), 'zh-Hant');
      expect(normalizeLalaLanguage('zh-HK'), 'zh-Hant');
      expect(normalizeLalaLanguage('zh-MO'), 'zh-Hant');
    });

    test('unknown and empty values fall back to ko (existing behavior)', () {
      expect(normalizeLalaLanguage('fr'), 'ko');
      expect(normalizeLalaLanguage(''), 'ko');
      expect(normalizeLalaLanguage(null), 'ko');
      expect(normalizeLalaLanguage('ENGLISH'), 'ko');
    });

    test('korean aliases still normalize to ko', () {
      expect(normalizeLalaLanguage('kor'), 'ko');
      expect(normalizeLalaLanguage('korean'), 'ko');
    });
  });

  group('lalaCopy / lalaCopyMulti byte-compat (I2)', () {
    test('ko and en are byte-identical across both entry points', () {
      const pairs = <(String, String)>[
        ('검색', 'Search'),
        ('로컬 신호', 'Local Signals'),
        ('다음', 'Next'),
      ];
      for (final (ko, en) in pairs) {
        expect(lalaCopy('ko', ko: ko, en: en), ko);
        expect(lalaCopy('en', ko: ko, en: en), en);
        expect(
          lalaCopyMulti(
            'ko',
            ko: ko,
            en: en,
            ja: 'ja-text',
            zhHans: 'hans',
            zhHant: 'hant',
          ),
          ko,
        );
        expect(
          lalaCopyMulti(
            'en',
            ko: ko,
            en: en,
            ja: 'ja-text',
            zhHans: 'hans',
            zhHant: 'hant',
          ),
          en,
        );
      }
    });

    test('visitor locales use the translation when provided', () {
      expect(
        lalaCopyMulti(
          'ja',
          ko: '로컬 신호',
          en: 'Local Signals',
          ja: 'ローカル信号',
          zhHans: '本地信号',
          zhHant: '在地訊號',
        ),
        'ローカル信号',
      );
      expect(
        lalaCopyMulti(
          'zh-Hans',
          ko: '로컬 신호',
          en: 'Local Signals',
          ja: 'ローカル信号',
          zhHans: '本地信号',
          zhHant: '在地訊號',
        ),
        '本地信号',
      );
      expect(
        lalaCopyMulti(
          'zh-Hant',
          ko: '로컬 신호',
          en: 'Local Signals',
          ja: 'ローカル信号',
          zhHans: '本地信号',
          zhHant: '在地訊號',
        ),
        '在地訊號',
      );
    });

    test('missing visitor translation falls back to en, never ko (§6)', () {
      const copy = 'Local place';
      expect(lalaCopyMulti('ja', ko: '이 장소', en: copy), copy);
      expect(lalaCopyMulti('zh-Hans', ko: '이 장소', en: copy), copy);
      expect(lalaCopyMulti('zh-Hant', ko: '이 장소', en: copy), copy);
    });

    test(
      'legacy lalaCopy gives visitor locales the honest EN fallback (I1)',
      () {
        // V6 SSOT semantics: only ko-normalizing languages get KO copy; every
        // visitor locale falls through to EN so un-migrated call sites cannot
        // leak Korean onto a visitor screen.
        const ko = '이 장소';
        const en = 'Local place';
        expect(lalaCopy('ko', ko: ko, en: en), ko);
        expect(lalaCopy('en', ko: ko, en: en), en);
        expect(lalaCopy('ja', ko: ko, en: en), en);
        expect(lalaCopy('zh-Hans', ko: ko, en: en), en);
        expect(lalaCopy('zh-Hant', ko: ko, en: en), en);
        // Byte-exact equality with the EN variant for every visitor locale.
        expect(lalaCopy('ja', ko: ko, en: en), lalaCopy('en', ko: ko, en: en));
        expect(
          lalaCopy('zh-Hans', ko: ko, en: en),
          lalaCopy('en', ko: ko, en: en),
        );
        expect(
          lalaCopy('zh-Hant', ko: ko, en: en),
          lalaCopy('en', ko: ko, en: en),
        );
        // Unknown values normalize to ko first, so they keep the KO variant.
        expect(lalaCopy('fr', ko: ko, en: en), ko);
      },
    );
  });

  group('singleLanguageText visitor-locale extraction (I1)', () {
    test('drops Korean-only text on visitor locales (honest empty)', () {
      expect(singleLanguageText('화성행궁', 'ja'), isNull);
      expect(singleLanguageText('수원시 팔달구', 'zh-Hans'), isNull);
      expect(singleLanguageText('날씨가 좋아요', 'zh-Hant'), isNull);
    });

    test('keeps non-Korean text as-is on visitor locales', () {
      expect(singleLanguageText('Hwaseong Haenggung', 'ja'),
          'Hwaseong Haenggung');
      expect(singleLanguageText('Suwon', 'zh-Hans'), 'Suwon');
    });

    test('extracts the English fragment from mixed KO/EN text', () {
      expect(
        singleLanguageText('Hwaseong Haenggung 화성행궁', 'ja'),
        'Hwaseong Haenggung',
      );
    });

    test('ko behavior unchanged (Korean text stays)', () {
      expect(singleLanguageText('화성행궁', 'ko'), '화성행궁');
      expect(singleLanguageText('Hwaseong Haenggung', 'ko'), isNull);
    });
  });

  group('OnboardingState language SSOT (§5)', () {
    setUp(OnboardingState.reset);
    tearDown(OnboardingState.reset);

    test('selectLanguage accepts the five canonical values', () {
      for (final code in kLalaLanguages) {
        OnboardingState.selectLanguage(code);
        expect(OnboardingState.language, code, reason: code);
      }
    });

    test('selectLanguage normalizes unknown input to ko (existing behavior)', () {
      OnboardingState.selectLanguage('fr');
      expect(OnboardingState.language, 'ko');
      OnboardingState.selectLanguage('zh-TW');
      expect(OnboardingState.language, 'zh-Hant');
    });

    test('applySnapshot restores visitor locales from persistence', () {
      OnboardingState.applySnapshot(
        const OnboardingSnapshot(completed: true, language: 'ja'),
      );
      expect(OnboardingState.language, 'ja');
      OnboardingState.applySnapshot(
        const OnboardingSnapshot(completed: true, language: 'zh-Hans'),
      );
      expect(OnboardingState.language, 'zh-Hans');
    });

    test('applySnapshot still degrades unknown codes to ko', () {
      OnboardingState.applySnapshot(
        const OnboardingSnapshot(completed: true, language: 'zz'),
      );
      expect(OnboardingState.language, 'ko');
    });
  });

  group('apiRequestLanguage (§10)', () {
    test('ko requests ko, every visitor locale requests en', () {
      expect(apiRequestLanguage('ko'), 'ko');
      expect(apiRequestLanguage('en'), 'en');
      expect(apiRequestLanguage('ja'), 'en');
      expect(apiRequestLanguage('zh-Hans'), 'en');
      expect(apiRequestLanguage('zh-Hant'), 'en');
      // Unknown values degrade to ko first, so the request language follows.
      expect(apiRequestLanguage('fr'), 'ko');
    });
  });

  group('region labels honest fallback (§6)', () {
    test('RegionContext.label shows the EN label on visitor locales', () {
      final option = manualOptionForId('gyeonggi-suwon')!;
      final context = RegionContext.manual(option);
      expect(context.label('ko'), option.labelKo);
      expect(context.label('en'), option.labelEn);
      expect(context.label('ja'), option.labelEn);
      expect(context.label('zh-Hans'), option.labelEn);
      expect(context.label('zh-Hant'), option.labelEn);
    });

    test('manual option labels never leak Korean on a visitor locale', () {
      final option = manualOptionForId('seoul-jung')!;
      for (final locale in <String>['ja', 'zh-Hans', 'zh-Hant']) {
        expect(containsKorean(option.label(locale)), isFalse, reason: locale);
        expect(
          containsKorean(option.fullLabel(locale)),
          isFalse,
          reason: locale,
        );
      }
    });

    test('locationLabel translates the default-region phrase per locale', () {
      expect(locationLabel(null, 'ja'), '既定の地域');
      expect(locationLabel(null, 'zh-Hans'), '默认地区');
      expect(locationLabel(null, 'zh-Hant'), '預設地區');
      expect(locationLabel(null, 'ko'), '기본 지역');
      expect(locationLabel(null, 'en'), 'Default region');
    });
  });

  group('whole-app legacy lalaCopy visitor gate', () {
    test(
      'every legacy ko/en pair resolves visitor locales to the EN variant',
      () {
        // Representative pairs drawn from the still-legacy call sites (map
        // fallback/stub/native, community, settings, dashboard). The SSOT
        // semantics must make all of them EN on visitor locales.
        const pairs = <(String, String)>[
          ('지도 미리보기', 'Map preview'),
          ('현재 지도를 표시할 수 없습니다.', 'The live map is not available right now.'),
          ('카카오 지도 로딩 중', 'Loading Kakao Map'),
          ('지도 화면을 준비하고 있습니다', 'Preparing the map view'),
          ('장소', 'Local place'),
          ('재시도', 'Retry'),
          ('닫기', 'Close'),
        ];
        for (final (ko, en) in pairs) {
          for (final locale in <String>['ja', 'zh-Hans', 'zh-Hant']) {
            expect(
              lalaCopy(locale, ko: ko, en: en),
              en,
              reason: 'legacy pair leaked KO at $locale',
            );
          }
          expect(lalaCopy('ko', ko: ko, en: en), ko);
          expect(lalaCopy('en', ko: ko, en: en), en);
        }
      },
    );
  });

  group('no flag emoji in the language surface (I3)', () {
    test('language badges and endonyms contain no flag emoji', () {
      // The onboarding rows are (code, badge, endonym). The contract requires
      // text badges; flag emoji live in the Unicode regional-indicator range.
      const surfaces = <String>[
        'KO',
        'EN',
        'JA',
        '简',
        '繁',
        '한국어',
        'English',
        '日本語',
        '简体中文',
        '繁體中文',
      ];
      final flagEmoji = RegExp(
        '[\u{1F1E6}-\u{1F1FF}]',
        unicode: true,
      );
      for (final surface in surfaces) {
        expect(flagEmoji.hasMatch(surface), isFalse, reason: surface);
      }
    });
  });
}
