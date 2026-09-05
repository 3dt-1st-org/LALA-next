import 'package:lala_next_app/shared/l10n/lala_copy.dart';

import 'lala_map_models.dart';

/// Map surface selected per normalized app locale (Draft #187 checkpoint).
///
/// - `ko` keeps the existing NAVER Dynamic Map path unchanged (pins,
///   clustering, camera, bottom rail, attribution, client-ID isolation).
/// - `en`, `ja`, `zh-Hans`, `zh-Hant` use the no-secret open-vector path
///   (MapLibre + OpenFreeMap/OpenMapTiles data) with data-driven label
///   localization. The public OpenFreeMap instance has no SLA; promotion to a
///   self-hosted or contracted provider happens by changing only
///   [kLalaOpenMapStyleUrl].
enum LalaMapProviderKind { naver, openVector }

/// Bridge source marker stamped by the open-vector embed (mirrors
/// `lala-naver-map` on the Korean path).
const String kLalaOpenMapBridgeSource = 'lala-open-map';

/// Bundled embed page served to both the web iframe (same-origin
/// `/assets/map/open-map-embed.html`) and the native WebView
/// (`loadFlutterAsset`). Version-pinned MapLibre GL JS is inlined, so the
/// asset is self-contained and never loads an unpinned remote script.
const String kLalaOpenMapEmbedAssetPath = 'assets/map/open-map-embed.html';

/// Config-message source marker for Flutter -> embed messages (shared with the
/// NAVER embed contract).
const String kLalaOpenMapConfigSource = 'lala-flutter-map-config';

/// Single replaceable style/provider boundary for the open-vector path.
///
/// Default is the public OpenFreeMap `liberty` style (OpenMapTiles schema,
/// OpenStreetMap data). Override with the `LALA_OPEN_MAP_STYLE_URL`
/// dart-define to point at a self-hosted or contracted provider without any
/// other code change.
const String kLalaOpenMapStyleUrl = String.fromEnvironment(
  'LALA_OPEN_MAP_STYLE_URL',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);

/// Hosts the native WebView may navigate to while the open-vector embed is
/// active: the OpenFreeMap style/tile host plus the Android
/// `WebViewAssetLoader` host that serves `loadFlutterAsset` content.
/// Subresource fetches (tiles/glyphs) stay on the style host; nothing else is
/// permitted.
const Set<String> kLalaOpenMapNavigationHosts = <String>{
  'tiles.openfreemap.org',
  'appassets.androidplatform.net',
};

/// Selects the map provider for [language] after normalization.
///
/// Korean (and unknown values, which normalize to Korean) stay on NAVER;
/// every supported visitor locale uses the open-vector path. This is the only
/// place the locale-to-provider decision is made.
LalaMapProviderKind selectLalaMapProvider(String? language) {
  return normalizeLalaLanguage(language) == 'ko'
      ? LalaMapProviderKind.naver
      : LalaMapProviderKind.openVector;
}

/// Native WebView navigation gate for the open-vector embed. Allows only the
/// hosts in [kLalaOpenMapNavigationHosts] plus the `flutter-assets` scheme
/// used by `webview_flutter`'s `loadFlutterAsset` on iOS. Anything else
/// (including the NAVER hosts) is rejected.
bool isOpenVectorNavigationAllowed(Uri? uri) {
  if (uri == null) {
    return false;
  }
  if (uri.scheme.toLowerCase() == 'flutter-assets') {
    return true;
  }
  return kLalaOpenMapNavigationHosts.contains(uri.host.toLowerCase());
}

/// MapLibre style-spec `text-field` expression that drives honest,
/// data-driven label localization for [language].
///
/// Fallback order per locale policy (OpenMapTiles multilingual `name:*`
/// fields actually present in the tileset; missing translations visibly fall
/// back, nothing is fabricated):
/// - en: `name:en` -> `name:latin` -> local `name`
/// - ja: `name:ja` -> `name:en` -> local `name`
/// - zh-Hans: `name:zh-Hans` -> `name:zh` -> local `name`
/// - zh-Hant: `name:zh-Hant` -> `name:zh` -> local `name`
/// - ko is unreachable here (provider selection keeps Korean on NAVER); the
///   defensive order is `name:ko` -> `name:latin` -> local `name`.
List<Object> openVectorLabelFieldExpression(String? language) {
  const List<String> en = <String>[
    'coalesce',
    'name:en',
    'name:latin',
    'name',
  ];
  const List<String> ja = <String>['coalesce', 'name:ja', 'name:en', 'name'];
  const List<String> zhHans = <String>[
    'coalesce',
    'name:zh-Hans',
    'name:zh',
    'name',
  ];
  const List<String> zhHant = <String>[
    'coalesce',
    'name:zh-Hant',
    'name:zh',
    'name',
  ];
  const List<String> ko = <String>[
    'coalesce',
    'name:ko',
    'name:latin',
    'name',
  ];
  final List<String> names = switch (normalizeLalaLanguage(language)) {
    'en' => en,
    'ja' => ja,
    'zh-Hans' => zhHans,
    'zh-Hant' => zhHant,
    _ => ko,
  };
  return <Object>[
    'coalesce',
    for (final String field in names.skip(1)) <Object>['get', field],
  ];
}

/// Builds the shared Flutter -> open-vector-embed config payload used by both
/// the web iframe bridge and the native `LalaMapEmbed.setConfig` push, so the
/// two paths cannot drift.
///
/// [includeConfigSource] adds the `lala-flutter-map-config` source marker
/// required by the web embed's same-origin message listener; the native path
/// calls `setConfig` directly and omits it.
Map<String, Object?> buildOpenVectorMapConfigPayload({
  required String bridgeId,
  required String language,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<LalaMapPlace> places,
  bool interactionEnabled = true,
  bool includeConfigSource = false,
}) {
  return <String, Object?>{
    if (includeConfigSource) 'source': kLalaOpenMapConfigSource,
    'bridgeId': bridgeId,
    'language': normalizeLalaLanguage(language),
    'interactive': interactionEnabled,
    'lat': centerLat,
    'lng': centerLng,
    'level': level.clamp(lalaMapMinimumLevel, lalaMapMaximumLevel),
    'styleUrl': kLalaOpenMapStyleUrl,
    'labelField': openVectorLabelFieldExpression(language),
    'places': places
        .map(
          (place) => <String, Object?>{
            'id': place.id,
            'name': place.name,
            'category': place.category,
            'lat': place.lat,
            'lng': place.lng,
            'clusterCount': place.clusterCount,
            'clusterMemberIds': place.clusterMemberIds,
            'selected': place.selected,
          },
        )
        .toList(),
  };
}
