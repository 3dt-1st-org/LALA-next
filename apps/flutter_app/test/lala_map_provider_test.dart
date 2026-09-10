// Locale-aware hybrid map provider contract (Draft #187 checkpoint).
// - Korean (and anything that normalizes to Korean) stays on the NAVER path.
// - en/ja/zh-Hans/zh-Hant select the no-secret open-vector path.
// - Label fallback order is honest and data-driven (OpenMapTiles name:*),
//   with no fabricated translations.
// - Navigation stays minimal: the OpenFreeMap style host plus exactly the
//   bundled embed document URI the installed webview_flutter platforms load
//   for loadFlutterAsset (file:// bundle URLs); the NAVER hosts, arbitrary
//   file paths, and phantom schemes/hosts are NOT allowed on the open path.
// - Provider swaps swap embed documents; same-provider updates are
//   config-only (no camera reset), and bridge events cannot cross providers.
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

    test('web iframe URL is the asset key under the assets base', () {
      // Flutter web serves asset keys from the `assets/` base directory, so
      // the iframe must load /assets/ + asset key. Pinning the relationship
      // guards against silently breaking the web embed URL.
      expect(kLalaOpenMapEmbedWebPath, 'assets/$kLalaOpenMapEmbedAssetPath');
      expect(kLalaOpenMapEmbedWebPath, startsWith('assets/assets/map/'));
    });
  });

  group('isOpenVectorNavigationAllowed — minimal navigation surface', () {
    test('allows the OpenFreeMap style host', () {
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('https://tiles.openfreemap.org/styles/liberty'),
        ),
        isTrue,
      );
    });

    test('allows the exact bundled embed URIs loadFlutterAsset produces', () {
      // iOS (webview_flutter_wkwebview): Bundle.url(forResource:) file URL
      // with an empty host, ending in flutter_assets/<asset key>.
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse(
            'file:///private/var/containers/Bundle/Application/11111111-2222-3333-4444-555555555555/Runner.app/Frameworks/App.framework/flutter_assets/assets/map/open-map-embed.html',
          ),
        ),
        isTrue,
      );
      // Android (webview_flutter_android): file:///android_asset/... URL.
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse(
            'file:///android_asset/flutter_assets/assets/map/open-map-embed.html',
          ),
        ),
        isTrue,
      );
    });

    test('rejects schemes/hosts no installed platform emits', () {
      // The `flutter-assets` scheme appears nowhere in the installed
      // webview_flutter 4.14.0 / wkwebview 3.26.0 / android 4.13.0 packages.
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('flutter-assets:///assets/map/open-map-embed.html'),
        ),
        isFalse,
      );
      // webview_flutter_android loads file:///android_asset/... directly,
      // not through the WebViewAssetLoader virtual host.
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('https://appassets.androidplatform.net/assets/map/x.html'),
        ),
        isFalse,
      );
    });

    test('rejects arbitrary file paths, foreign hosts, and other assets', () {
      expect(
        isOpenVectorNavigationAllowed(Uri.parse('file:///etc/passwd')),
        isFalse,
      );
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse('file:///var/mobile/Library/evil.html'),
        ),
        isFalse,
      );
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse(
            'file:///android_asset/flutter_assets/assets/map/other.html',
          ),
        ),
        isFalse,
      );
      expect(
        isOpenVectorNavigationAllowed(
          Uri.parse(
            'file://localhost/flutter_assets/assets/map/open-map-embed.html',
          ),
        ),
        isFalse,
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

  group('resolveLalaMapDocumentTransition — provider/document transitions', () {
    LalaMapDocumentTransition resolve(
      LalaMapProviderKind oldProvider,
      LalaMapProviderKind newProvider, {
      bool clientIdChanged = false,
      bool languageChanged = false,
    }) {
      return resolveLalaMapDocumentTransition(
        oldProvider: oldProvider,
        newProvider: newProvider,
        clientIdChanged: clientIdChanged,
        languageChanged: languageChanged,
      );
    }

    test('full locale chain KO->EN->JA->zh-Hans->zh-Hant->KO', () {
      // KO -> EN must swap to the bundled open-vector document (regression:
      // the NAVER document used to be reused and receive a clientId-less
      // open-vector config, rendering the NAVER unavailable overlay).
      expect(
        resolve(LalaMapProviderKind.naver, LalaMapProviderKind.openVector,
            languageChanged: true),
        LalaMapDocumentTransition.swapToOpenVectorEmbed,
      );
      // Same-provider locale swaps are config-only: no reload, so no camera
      // reset on ordinary updates.
      const openVector = LalaMapProviderKind.openVector;
      for (final language in <String>['en', 'ja', 'zh-Hans', 'zh-Hant']) {
        expect(
          resolve(openVector, openVector, languageChanged: true),
          LalaMapDocumentTransition.keepDocument,
          reason: 'language: $language',
        );
      }
      // zh-Hant -> KO must swap back to the NAVER document.
      expect(
        resolve(LalaMapProviderKind.openVector, LalaMapProviderKind.naver,
            languageChanged: true),
        LalaMapDocumentTransition.swapToNaverEmbed,
      );
    });

    test('NAVER stays identity-bound to its client id and SDK language', () {
      const naver = LalaMapProviderKind.naver;
      expect(
        resolve(naver, naver, clientIdChanged: true),
        LalaMapDocumentTransition.swapToNaverEmbed,
      );
      expect(
        resolve(naver, naver, languageChanged: true),
        LalaMapDocumentTransition.swapToNaverEmbed,
      );
    });

    test('open-vector is not identity-bound; ordinary updates keep the doc', () {
      const openVector = LalaMapProviderKind.openVector;
      expect(
        resolve(openVector, openVector, clientIdChanged: true),
        LalaMapDocumentTransition.keepDocument,
      );
      expect(
        resolve(openVector, openVector),
        LalaMapDocumentTransition.keepDocument,
      );
      expect(
        resolve(LalaMapProviderKind.naver, LalaMapProviderKind.naver),
        LalaMapDocumentTransition.keepDocument,
      );
    });
  });

  group('isLalaMapEmbedMessageAccepted — bridge events cannot cross providers',
      () {
    test('accepts only the live provider marker with the live bridge id', () {
      expect(
        isLalaMapEmbedMessageAccepted(
          provider: LalaMapProviderKind.openVector,
          bridgeId: 'bridge-1',
          message: <String, dynamic>{
            'source': 'lala-open-map',
            'bridgeId': 'bridge-1',
            'type': 'cameraIdle',
          },
        ),
        isTrue,
      );
      expect(
        isLalaMapEmbedMessageAccepted(
          provider: LalaMapProviderKind.naver,
          bridgeId: 'bridge-2',
          message: <String, dynamic>{
            'source': 'lala-naver-map',
            'bridgeId': 'bridge-2',
            'type': 'placeTap',
          },
        ),
        isTrue,
      );
    });

    test('a stale document from the other provider is rejected after a swap',
        () {
      // Late cameraIdle from the NAVER document while open-vector is live
      // (naver -> openVector swap) must be dropped...
      expect(
        isLalaMapEmbedMessageAccepted(
          provider: LalaMapProviderKind.openVector,
          bridgeId: 'bridge-1',
          message: <String, dynamic>{
            'source': 'lala-naver-map',
            'bridgeId': 'bridge-1',
            'type': 'cameraIdle',
          },
        ),
        isFalse,
      );
      // ...and symmetrically for open-vector -> naver.
      expect(
        isLalaMapEmbedMessageAccepted(
          provider: LalaMapProviderKind.naver,
          bridgeId: 'bridge-1',
          message: <String, dynamic>{
            'source': 'lala-open-map',
            'bridgeId': 'bridge-1',
            'type': 'mapError',
            'code': 'style_timeout',
          },
        ),
        isFalse,
      );
    });

    test('bridge id mismatches and malformed input are rejected', () {
      expect(
        isLalaMapEmbedMessageAccepted(
          provider: LalaMapProviderKind.openVector,
          bridgeId: 'bridge-1',
          message: <String, dynamic>{
            'source': 'lala-open-map',
            'bridgeId': 'other-bridge',
            'type': 'placeTap',
          },
        ),
        isFalse,
      );
      expect(
        isLalaMapEmbedMessageAccepted(
          provider: LalaMapProviderKind.openVector,
          bridgeId: 'bridge-1',
          message: null,
        ),
        isFalse,
      );
      expect(expectedLalaMapBridgeSource(LalaMapProviderKind.openVector),
          kLalaOpenMapBridgeSource);
      expect(
        expectedLalaMapBridgeSource(LalaMapProviderKind.naver),
        kLalaNaverBridgeSource,
      );
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
