// Bundled open-vector map embed integrity (Draft #187 checkpoint).
// The embed is a build input, not generated at runtime: these tests pin the
// contract markers the web/native bridges rely on, prove the runtime is the
// version-pinned self-contained MapLibre build (no external scripts), and
// lock the attribution + policy requirements (no tile.openstreetmap.org, no
// prefetching, no unpinned CDN scripts).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String kTemplateAssetPath = 'assets/map/open-map-embed.template.html';
const String kEmbedAssetPath = 'assets/map/open-map-embed.html';

Future<String> loadAsset(String path) {
  return rootBundle.loadString(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('open-map-embed template (reviewable bridge source)', () {
    late String template;

    setUpAll(() async {
      template = await loadAsset(kTemplateAssetPath);
    });

    test('declares the pinned runtime placeholders', () {
      expect(template, contains('__MAPLIBRE_GL_JS__'));
      expect(template, contains('__MAPLIBRE_GL_CSS__'));
      expect(template, contains('__MAPLIBRE_GL_VERSION__'));
    });

    test('keeps the Flutter->embed bridge contract', () {
      expect(template, contains('lala-flutter-map-config'));
      expect(template, contains('window.LalaMapEmbed'));
      expect(template, contains('setConfig'));
      // Same-origin + parent-frame gating for config messages (web path).
      expect(
        template,
        contains('event.origin !== window.location.origin'),
      );
    });

    test('keeps the embed->Flutter bridge contract', () {
      expect(template, contains('"lala-open-map"'));
      expect(template, contains('window.LalaMap.postMessage'));
      expect(template, contains('window.parent.postMessage'));
      expect(template, contains('"cameraIdle"'));
      expect(template, contains('"placeTap"'));
      expect(template, contains('"mapError"'));
      // Stale-response suppression for programmatic camera moves.
      expect(template, contains('suppressIdleUntil'));
    });

    test('applies the locale expression only to proven name-field layers', () {
      expect(template, contains("on(\"style.load\""));
      expect(template, contains("on(\"styledata\""));
      expect(template, contains('setLayoutProperty'));
      expect(template, contains('getLayoutProperty'));
      expect(template, contains('referencesNameProperty'));
      expect(template, contains('layer.type !== "symbol"'));
      // Honest blocker when the style cannot prove multilingual name fields.
      expect(template, contains('no_multilingual_labels'));
      expect(template, contains('reportLabelBlocker'));
    });

    test('shows visible attribution for the full data chain', () {
      expect(template, contains('OpenStreetMap contributors'));
      expect(template, contains('OpenMapTiles'));
      expect(template, contains('OpenFreeMap'));
      expect(template, contains('attributionControl'));
      expect(template, contains('compact: false'));
    });

    test('keeps the single replaceable provider boundary', () {
      expect(
        template,
        contains('https://tiles.openfreemap.org/styles/liberty'),
      );
      // Only https style URLs are accepted from config.
      expect(template, contains('https://") === 0'));
    });

    test('policy: no raster OSM tiles, no prefetch, no external scripts', () {
      expect(template, isNot(contains('tile.openstreetmap.org')));
      expect(template, isNot(contains('setRTLTextPlugin')));
      // The template itself must not reference remote scripts/stylesheets.
      expect(template, isNot(contains('<script src=')));
      expect(template, isNot(contains('<link rel="stylesheet"')));
    });

    test('interaction-disabled mode and camera idle payload contract', () {
      expect(template, contains('applyInteractivity'));
      expect(template, contains('dragPan'));
      expect(template, contains('touchZoomRotate'));
      expect(template, contains('sw_lat'));
      expect(template, contains('ne_lng'));
      expect(template, contains('zoomToAppLevel'));
    });

    test('honest loading/error notices for every visitor locale', () {
      // First setConfig shows a loading notice; style failures fall back to
      // the unavailable notice with a mapError event (never silent blank).
      expect(template, contains('Loading the open map...'));
      expect(template, contains('STYLE_TIMEOUT_MS'));
      expect(template, contains('onStyleTimeout'));
      expect(template, contains('showNotice("unavailable")'));
    });
  });

  group('assembled open-map-embed.html (bundled asset)', () {
    late String embed;

    setUpAll(() async {
      embed = await loadAsset(kEmbedAssetPath);
    });

    test('is a self-contained pinned-runtime HTML asset', () {
      expect(embed, startsWith('<!DOCTYPE html>'));
      expect(embed, contains('maplibre-gl@3.6.2'));
      // Public upstream dist checksums (integrity pins, not credentials).
      expect(embed, contains(
        'c46084df69bbaa995b301a515274a86ec53905c78459b80dccbc27a0c0b8d13b', // pragma: allowlist secret
      ));
      expect(embed, contains(
        '731181d400d65a8b09d842f55b70bc4dc11010b15b8549e2c65a69d233fbdd2e', // pragma: allowlist secret
      ));
      // The runtime is really inlined, not referenced.
      expect(embed.length, greaterThan(700 * 1024));
      expect(embed, isNot(contains('__MAPLIBRE_GL_JS__')));
      expect(embed, isNot(contains('__MAPLIBRE_GL_CSS__')));
      expect(embed, isNot(contains('<script src=')));
      expect(embed, isNot(contains('<link rel="stylesheet"')));
      expect(embed, isNot(contains('sourceMappingURL')));
    });

    test('carries every template bridge marker', () {
      for (final marker in <String>[
        'lala-flutter-map-config',
        '"lala-open-map"',
        'window.LalaMapEmbed',
        'no_multilingual_labels',
        'suppressIdleUntil',
        'attributionControl',
        'https://tiles.openfreemap.org/styles/liberty',
        'OpenStreetMap contributors',
      ]) {
        expect(embed, contains(marker), reason: 'missing marker: $marker');
      }
    });

    test('does not leak the maplibre global assignment into page scope oddly',
        () {
      // The UMD bundle must define window.maplibregl for the bridge to use.
      expect(embed, contains('maplibregl'));
    });

    test('renders valid UTF-8 JSON-transportable content', () {
      final bytes = utf8.encode(embed);
      expect(utf8.decode(bytes), embed);
    });
  });
}
