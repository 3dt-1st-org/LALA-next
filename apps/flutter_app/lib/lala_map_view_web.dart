// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';

import 'lala_map_fallback.dart';
import 'lala_map_models.dart';
import 'lala_map_provider.dart';

Widget buildLalaMapView({
  required String clientId,
  required String language,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<LalaMapPlace> places,
  bool interactionEnabled = true,
  ValueChanged<String>? onPlaceTap,
  ValueChanged<LalaMapCamera>? onCameraIdle,
}) {
  final provider = selectLalaMapProvider(language);
  final normalizedClientId = clientId.trim();
  if (provider == LalaMapProviderKind.naver && normalizedClientId.isEmpty) {
    return LalaMapFallbackView(
      message: liveMapUnavailableLabel(language),
      language: language,
      centerLat: centerLat,
      centerLng: centerLng,
      places: places,
      onPlaceTap: onPlaceTap,
    );
  }

  return _LalaMapWebFrame(
    provider: provider,
    clientId: normalizedClientId,
    language: language,
    centerLat: centerLat,
    centerLng: centerLng,
    level: level,
    places: places,
    interactionEnabled: interactionEnabled,
    onPlaceTap: onPlaceTap,
    onCameraIdle: onCameraIdle,
  );
}

class _LalaMapWebFrame extends StatefulWidget {
  const _LalaMapWebFrame({
    required this.provider,
    required this.clientId,
    required this.language,
    required this.centerLat,
    required this.centerLng,
    required this.level,
    required this.places,
    required this.interactionEnabled,
    this.onPlaceTap,
    this.onCameraIdle,
  });

  final LalaMapProviderKind provider;
  final String clientId;
  final String language;
  final double centerLat;
  final double centerLng;
  final int level;
  final List<LalaMapPlace> places;
  final bool interactionEnabled;
  final ValueChanged<String>? onPlaceTap;
  final ValueChanged<LalaMapCamera>? onCameraIdle;

  @override
  State<_LalaMapWebFrame> createState() => _LalaMapWebFrameState();
}

class _LalaMapWebFrameState extends State<_LalaMapWebFrame> {
  static int _nextViewId = 0;

  late final String _viewType;
  late final String _bridgeId;
  late final html.IFrameElement _frame;
  int _revision = 0;
  StreamSubscription<html.Event>? _loadSubscription;
  StreamSubscription<html.MessageEvent>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    final prefix = widget.provider == LalaMapProviderKind.openVector
        ? 'lala-open-map'
        : 'lala-naver-map';
    _viewType = '$prefix-${_nextViewId++}';
    _bridgeId = '$_viewType-bridge';
    _frame = html.IFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = '0'
      ..style.backgroundColor = '#eaf2fb'
      ..setAttribute('title', _mapTitle(widget.provider, widget.language));
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _frame,
    );
    _loadSubscription = _frame.onLoad.listen((_) => _postConfig());
    _messageSubscription = html.window.onMessage.listen(_handleMessage);
    _reloadFrame();
  }

  @override
  void didUpdateWidget(covariant _LalaMapWebFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _frame.style.pointerEvents = widget.interactionEnabled ? 'auto' : 'none';
    _frame.setAttribute('title', _mapTitle(widget.provider, widget.language));
    // Provider swaps must point the iframe at the other embed document; the
    // onLoad listener delivers config once it is live. Same-provider updates
    // keep the document (no camera reset) and post config only.
    final transition = resolveLalaMapDocumentTransition(
      oldProvider: oldWidget.provider,
      newProvider: widget.provider,
      clientIdChanged: oldWidget.clientId != widget.clientId,
      languageChanged: oldWidget.language != widget.language,
    );
    if (transition != LalaMapDocumentTransition.keepDocument) {
      _reloadFrame();
      return;
    }
    if (oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLng != widget.centerLng ||
        oldWidget.level != widget.level ||
        oldWidget.language != widget.language ||
        oldWidget.interactionEnabled != widget.interactionEnabled ||
        !sameLalaMapPlaces(oldWidget.places, widget.places)) {
      _postConfig();
    }
  }

  @override
  void dispose() {
    _loadSubscription?.cancel();
    _messageSubscription?.cancel();
    _frame.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEAF2FB),
      child: HtmlElementView(viewType: _viewType),
    );
  }

  void _reloadFrame() {
    _revision += 1;
    _frame
      ..style.pointerEvents = widget.interactionEnabled ? 'auto' : 'none'
      ..setAttribute('title', _mapTitle(widget.provider, widget.language))
      ..src = _embedUrl().toString();
  }

  Uri _embedUrl() {
    if (widget.provider == LalaMapProviderKind.openVector) {
      // Bundled asset served same-origin by the Flutter web build (asset
      // keys are prefixed with the `assets/` base); the version-pinned
      // MapLibre runtime is inlined, so no cache busting of a remote
      // document is needed and locale swaps go through config.
      return Uri.base.resolve(kLalaOpenMapEmbedWebPath);
    }
    return Uri.base
        .resolve('naver-map-embed.html')
        .replace(queryParameters: {'r': '$_revision'});
  }

  void _postConfig() {
    final payload = widget.provider == LalaMapProviderKind.openVector
        ? buildOpenVectorMapConfigPayload(
            bridgeId: _bridgeId,
            language: widget.language,
            centerLat: widget.centerLat,
            centerLng: widget.centerLng,
            level: widget.level,
            places: widget.places,
            interactionEnabled: widget.interactionEnabled,
            includeConfigSource: true,
          )
        : <String, Object?>{
            // Literal kept for the Python safety contract
            // (apps/api/tests/test_safety_contracts.py greps this file for
            // the source marker); the open-vector branch above uses the
            // shared constant through buildOpenVectorMapConfigPayload.
            'source': 'lala-flutter-map-config',
            'bridgeId': _bridgeId,
            'clientId': widget.clientId,
            'language': widget.language,
            'interactive': widget.interactionEnabled,
            'lat': widget.centerLat,
            'lng': widget.centerLng,
            'level': widget.level,
            'places': widget.places
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
    _frame.contentWindow?.postMessage(
      jsonEncode(payload),
      html.window.location.origin,
    );
  }

  void _handleMessage(html.MessageEvent event) {
    if (event.origin != html.window.location.origin) {
      return;
    }
    final raw = event.data;
    if (raw is! String || raw.trim().isEmpty) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    final expectedSource = widget.provider == LalaMapProviderKind.openVector
        ? kLalaOpenMapBridgeSource
        : 'lala-naver-map';
    if (decoded is! Map<String, dynamic> ||
        decoded['source'] != expectedSource ||
        decoded['bridgeId'] != _bridgeId) {
      return;
    }
    final camera = decodeLalaMapCameraIdlePayload(decoded);
    if (camera != null) {
      widget.onCameraIdle?.call(camera);
      return;
    }
    if (decoded['type'] == 'placeTap') {
      final placeId = decoded['placeId']?.toString().trim();
      if (placeId != null && placeId.isNotEmpty) {
        widget.onPlaceTap?.call(placeId);
      }
    }
  }
}

String _mapTitle(LalaMapProviderKind provider, String language) {
  return provider == LalaMapProviderKind.openVector
      ? openVectorMapLabel(language)
      : naverMapLabel(language);
}
