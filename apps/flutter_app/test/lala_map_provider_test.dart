// Locale-aware hybrid map provider contract (Draft #187 checkpoint).
// - Korean (and anything that normalizes to Korean) stays on the NAVER path.
// - en/ja/zh-Hans/zh-Hant select the no-secret open-vector path.
// - Label fallback order is honest and data-driven (OpenMapTiles name:*),
//   with no fabricated translations.
// - Navigation stays minimal: only the OpenFreeMap host plus the WebView
//   asset-loader hosts; the NAVER hosts are NOT allowed on the open path.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/lala_map_models.dart';
import 'package:lala_next_app/lala_map_provider.dart';

void main() {
  group('selectLalaMapProvider', () {
    test('Korean and Korean-normalizing inputs stay on NAVER', () {
      expect(selectLalaMapProvider('ko'), LalaMapProviderKind.naver);
      expect(selectLalaMapProvider('kor'), LalaMapProviderKind.naver);
      expect(selectLalaMapProvider('korean'), LalaMapProviderKind.naver);
      expect(selectLalaMapProvider(''), LalaMapProviderKind.naver);
      expect(selectLalaMapProvider(null), LalaMapProviderKind.naver);
      expect(selectLalaMapProvider('fr'), LalaMapProviderKind.naver);
    });

    test('visitor locales select the open-vector path', () {
      expect(selectLalaMapProvider('en'), LalaMapProviderKind.openVector);
      expect(selectLalaMapProvider('ja'), LalaMapProviderKind.openVector);
      expect(
        selectLalaMapProvider('zh-Hans'),
        LalaMapProviderKind.openVector,
      );
      expect(
        selectLalaMapProvider('zh-Hant'),
        LalaMapProviderKind.openVector,
      );
      // BCP-47 prefix folding through the shared normalizer.
      expect(selectLalaMapProvider('zh-CN'), LalaMapProviderKind.openVector);
      expect(selectLalaMapProvider('zh-TW'), LalaMapProviderKind.openVector);
    });
  });

  group('openVectorLabelFieldExpression — honest fallback order', () {
    test('en: name:en -> name:latin -> name', () {
      expect(openVectorLabelFieldExpression('en'), <Object>[
        'coalesce',
        <Object>['get', 'name:en'],
        <Object>['get', 'name:latin'],
        <Object>['get', 'name'],
      ]);
    });

    test('ja: name:ja -> name:en -> name', () {
      expect(openVectorLabelFieldExpression('ja'), <Object>[
        'coalesce',
        <Object>['get', 'name:ja'],
        <Object>['get', 'name:en'],
        <Object>['get', 'name'],
      ]);
    });

    test('zh-Hans: name:zh-Hans -> name:zh -> name', () {
      expect(openVectorLabelFieldExpression('zh-Hans'), <Object>[
        'coalesce',
        <Object>['get', 'name:zh-Hans'],
        <Object>['get', 'name:zh'],
        <Object>['get', 'name'],
      ]);
    });

    test('zh-Hant: name:zh-Hant -> name:zh -> name', () {
      expect(openVectorLabelFieldExpression('zh-Hant'), <Object>[
        'coalesce',
        <Object>['get', 'name:zh-Hant'],
        <Object>['get', 'name:zh'],
        <Object>['get', 'name'],
      ]);
    });

    test('locale prefixes fold through the shared normalizer', () {
      expect(
        openVectorLabelFieldExpression('zh-SG'),
        openVectorLabelFieldExpression('zh-Hans'),
      );
      expect(
        openVectorLabelFieldExpression('zh-HK'),
        openVectorLabelFieldExpression('zh-Hant'),
      );
    });

    test('every expression is a pure coalesce over name fields (no fabrication)', () {
      for (final language in <String>['en', 'ja', 'zh-Hans', 'zh-Hant']) {
        final expression = openVectorLabelFieldExpression(language);
        expect(expression.first, 'coalesce');
        for (final operand in expression.skip(1)) {
          expect(operand, isA<List<Object>>());
          final get = operand as List<Object>;
          expect(get, hasLength(2));
          expect(get.first, 'get');
          expect(get.last, matches(r'^name(:[A-Za-z-]+)?$'));
        }
      }
    });
  });

  group('open-vector constants', () {
    test('style URL is the replaceable provider boundary', () {
      expect(
        kLalaOpenMapStyleUrl,
        'https://tiles.openfreemap.org/styles/liberty',
      );
    });

    test('bridge source and embed asset path are explicit', () {
      expect(kLalaOpenMapBridgeSource, 'lala-open-map');
      expect(kLalaOpenMapEmbedAssetPath, 'assets/map/open-map-embed.html');
      expect(kLalaOpenMapConfigSource, 'lala-flutter-map-config');
    });
  });

  group('isOpenVectorNavigationAllowed — minimal navigation surface', () {
    test('allows the OpenFreeMap host and WebView asset loader only', () {
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('https://tiles.openfreemap.org/styles/liberty'),
        ),
        isTrue,
      );
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('https://appassets.androidplatform.net/assets/map/x.html'),
        ),
        isTrue,
      );
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('flutter-assets:///assets/map/open-map-embed.html'),
        ),
        isTrue,
      );
    });

    test('rejects NAVER hosts, arbitrary hosts, and malformed input', () {
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('https://oapi.map.naver.com/openapi/v3/maps.js'),
        ),
        isFalse,
      );
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('https://lala-next.cloud/naver-map-embed.html'),
        ),
        isFalse,
      );
      expect(
        isOpenVectorNavigationAllowed(Uri.parse('https://evil.example.com/')),
        isFalse,
      );
      expect(isOpenVectorNavigationAllowed(null), isFalse);
    });
  });

  group('buildOpenVectorMapConfigPayload — shared bridge payload SSOT', () {
    final places = <LalaMapPlace>[
      const LalaMapPlace(
        id: 'place-1',
        name: 'Gyeongbokgung',
        category: 'attraction',
        lat: 37.5796,
        lng: 126.9770,
      ),
      const LalaMapPlace(
        id: 'cluster-2',
        name: 'cluster',
        category: 'restaurant',
        lat: 37.5,
        lng: 126.9,
        clusterCount: 7,
        clusterMemberIds: <String>['a', 'b', 'c', 'd', 'e', 'f', 'g'],
      ),
    ];

    test('carries labelField, styleUrl and the full place contract', () {
      final payload = buildOpenVectorMapConfigPayload(
        bridgeId: 'bridge-1',
        language: 'ja',
        centerLat: 37.5,
        centerLng: 126.9,
        level: 6,
        places: places,
      );
      expect(payload, containsPair('bridgeId', 'bridge-1'));
      expect(payload, containsPair('language', 'ja'));
      expect(payload, containsPair('interactive', true));
      expect(payload, containsPair('lat', 37.5));
      expect(payload, containsPair('lng', 126.9));
      expect(payload, containsPair('level', 6));
      expect(payload, containsPair('styleUrl', kLalaOpenMapStyleUrl));
      expect(
        payload['labelField'],
        openVectorLabelFieldExpression('ja'),
      );
      expect(payload.containsKey('source'), isFalse);

      final mappedPlaces = payload['places'] as List<Map<String, Object?>>;
      expect(mappedPlaces, hasLength(2));
      expect(mappedPlaces.first, containsPair('id', 'place-1'));
      expect(mappedPlaces.first, containsPair('name', 'Gyeongbokgung'));
      expect(mappedPlaces.first, containsPair('category', 'attraction'));
      expect(mappedPlaces.first, containsPair('selected', false));
      expect(
        mappedPlaces.last,
        containsPair('clusterMemberIds', <String>['a', 'b', 'c', 'd', 'e', 'f', 'g']),
      );
      expect(mappedPlaces.last, containsPair('clusterCount', 7));
    });

    test('includeConfigSource adds the web bridge source marker', () {
      final payload = buildOpenVectorMapConfigPayload(
        bridgeId: 'bridge-2',
        language: 'zh-Hans',
        centerLat: 37.5,
        centerLng: 126.9,
        level: 4,
        places: const <LalaMapPlace>[],
        includeConfigSource: true,
      );
      expect(
        payload,
        containsPair('source', kLalaOpenMapConfigSource),
      );
    });

    test('level is clamped to the LALA level contract', () {
      final payload = buildOpenVectorMapConfigPayload(
        bridgeId: 'bridge-3',
        language: 'en',
        centerLat: 37.5,
        centerLng: 126.9,
        level: 42,
        places: const <LalaMapPlace>[],
      );
      expect(payload, containsPair('level', lalaMapMaximumLevel));

      final lowPayload = buildOpenVectorMapConfigPayload(
        bridgeId: 'bridge-4',
        language: 'en',
        centerLat: 37.5,
        centerLng: 126.9,
        level: -3,
        places: const <LalaMapPlace>[],
      );
      expect(lowPayload, containsPair('level', lalaMapMinimumLevel));
    });

    test('payload is JSON-encodable for both bridge transports', () {
      // Regression guard: the payload crosses postMessage (web) and a JS
      // evaluate (native) as JSON text.
      final encoded = jsonEncode(buildOpenVectorMapConfigPayload(
        bridgeId: 'bridge-5',
        language: 'zh-Hant',
        centerLat: 37.5,
        centerLng: 126.9,
        level: 5,
        places: places,
        includeConfigSource: true,
      ));
      expect(encoded, contains('"bridgeId":"bridge-5"'));
      expect(encoded, contains('"labelField"'));
      expect(encoded, contains('"styleUrl"'));
    });
  });
}
