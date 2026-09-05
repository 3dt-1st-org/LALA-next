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

/// Bundled embed page served to both the web iframe and the native WebView
/// (`loadFlutterAsset`). Version-pinned MapLibre GL JS is inlined, so the
/// asset is self-contained and never loads an unpinned remote script.
const String kLalaOpenMapEmbedAssetPath = 'assets/map/open-map-embed.html';

/// URL the web iframe loads. Flutter web serves asset keys from the `assets/`
/// base, so the browser path is `/assets/` + [kLalaOpenMapEmbedAssetPath];
/// this stays in sync by construction and is pinned by tests.
const String kLalaOpenMapEmbedWebPath = 'assets/assets/map/open-map-embed.html';

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
/// active: the OpenFreeMap style/tile host only. The embed document itself
/// is a bundled asset delivered as a `file://` URL (see
/// [isBundledOpenMapEmbedAssetUri]); subresource fetches (tiles/glyphs) stay
/// on the style host; nothing else is permitted.
const Set<String> kLalaOpenMapNavigationHosts = <String>{
  'tiles.openfreemap.org',
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

/// Whether [uri] is exactly the bundled open-vector embed document as
/// produced by the installed `webview_flutter` platform implementations of
/// `loadFlutterAsset`:
///
/// - iOS (`webview_flutter_wkwebview`) resolves the asset inside the app
///   bundle and calls `WKWebView.loadFileURL`, producing a `file://` URL
///   with an empty host whose path ends in
///   `/flutter_assets/<kLalaOpenMapEmbedAssetPath>`. That programmatic
///   main-frame load IS routed through the navigation delegate, so the gate
///   must admit it.
/// - Android (`webview_flutter_android`) loads
///   `file:///android_asset/flutter_assets/<asset key>`.
///
/// The suffix match admits only this one document under a `flutter_assets`
/// directory; arbitrary `file://` paths (and the `flutter-assets://` scheme
/// that no installed platform emits) are still rejected.
bool isBundledOpenMapEmbedAssetUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'file' || uri.host.isNotEmpty) {
    return false;
  }
  return uri.path.endsWith('/flutter_assets/$kLalaOpenMapEmbedAssetPath');
}

/// Native WebView navigation gate for the open-vector embed. Allows only the
/// hosts in [kLalaOpenMapNavigationHosts] plus the exact bundled embed
/// document URI `loadFlutterAsset` produces ([isBundledOpenMapEmbedAssetUri]).
/// Anything else (including the NAVER hosts and arbitrary `file://` URLs) is
/// rejected.
bool isOpenVectorNavigationAllowed(Uri? uri) {
  if (uri == null) {
    return false;
  }
  if (kLalaOpenMapNavigationHosts.contains(uri.host.toLowerCase())) {
    return true;
  }
  return isBundledOpenMapEmbedAssetUri(uri);
}

/// Document-transition decision shared by the native WebView host and the
/// web iframe host, so a provider swap can never leave the wrong embed
/// document on screen (the NAVER embed cannot render an open-vector config,
/// and the open-vector embed never sees NAVER identity).
enum LalaMapDocumentTransition {
  /// Keep the loaded document; ordinary config changes are delivered via a
  /// config push (no reload, so no camera reset).
  keepDocument,

  /// Load the bundled open-vector embed document
  /// (`loadFlutterAsset` / iframe src swap); config follows on page load.
  swapToOpenVectorEmbed,

  /// Load the NAVER embed document (`loadRequest` / iframe src swap);
  /// config follows on page load.
  swapToNaverEmbed,
}

/// Resolves what the embed host must do when its widget updates.
///
/// - A provider change always swaps the document, in both directions.
/// - Same provider: only the NAVER embed is identity-bound to its client id
///   and SDK language, so a change there reloads the NAVER document. The
///   open-vector embed swaps locale via config only (no reload, no camera
///   reset) and is bundled, so a branch build needs no main deployment.
LalaMapDocumentTransition resolveLalaMapDocumentTransition({
  required LalaMapProviderKind oldProvider,
  required LalaMapProviderKind newProvider,
  required bool clientIdChanged,
  required bool languageChanged,
}) {
  if (oldProvider != newProvider) {
    return newProvider == LalaMapProviderKind.openVector
        ? LalaMapDocumentTransition.swapToOpenVectorEmbed
        : LalaMapDocumentTransition.swapToNaverEmbed;
  }
  if (newProvider == LalaMapProviderKind.naver &&
      (clientIdChanged || languageChanged)) {
    return LalaMapDocumentTransition.swapToNaverEmbed;
  }
  return LalaMapDocumentTransition.keepDocument;
}

/// Bridge source marker stamped by the NAVER embed (mirrors
/// [kLalaOpenMapBridgeSource] on the open-vector path).
const String kLalaNaverBridgeSource = 'lala-naver-map';

/// Source marker the embed for [provider] stamps on every bridge message.
String expectedLalaMapBridgeSource(LalaMapProviderKind provider) {
  return provider == LalaMapProviderKind.openVector
      ? kLalaOpenMapBridgeSource
      : kLalaNaverBridgeSource;
}

/// Whether a decoded embed -> Flutter message may be accepted for [provider]
/// and the live host's [bridgeId]: the source marker must match the
/// provider's embed and the bridge id must match. Bridge events cannot cross
/// providers, so a stale document after a provider swap (or any other
/// origin) is rejected.
bool isLalaMapEmbedMessageAccepted({
  required LalaMapProviderKind provider,
  required String bridgeId,
  Map<String, dynamic>? message,
}) {
  if (message == null) {
    return false;
  }
  return message['source'] == expectedLalaMapBridgeSource(provider) &&
      message['bridgeId'] == bridgeId;
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
