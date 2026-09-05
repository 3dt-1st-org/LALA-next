import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
    return _LalaMapNativeUnavailable(
      message: liveMapUnavailableLabel(language),
      language: language,
      centerLat: centerLat,
      centerLng: centerLng,
      places: places,
      onPlaceTap: onPlaceTap,
    );
  }

  if (!io.Platform.isIOS && !io.Platform.isAndroid) {
    return _LalaMapNativeUnavailable(
      message: liveMapUnavailableLabel(language),
      language: language,
      centerLat: centerLat,
      centerLng: centerLng,
      places: places,
      onPlaceTap: onPlaceTap,
    );
  }

  return _LalaMapNativeWebView(
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

class _LalaMapNativeWebView extends StatefulWidget {
  const _LalaMapNativeWebView({
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
  State<_LalaMapNativeWebView> createState() => _LalaMapNativeWebViewState();
}

class _LalaMapNativeWebViewState extends State<_LalaMapNativeWebView> {
  static int _nextBridgeId = 0;

  late final WebViewController _controller;
  late final String _bridgeId;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _bridgeId = 'lala-native-map-${_nextBridgeId++}';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFEAF2FB))
      ..addJavaScriptChannel(
        'LalaMap',
        onMessageReceived: (message) => _handleMapMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async => _pushConfig(),
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (widget.provider == LalaMapProviderKind.openVector) {
              return isOpenVectorNavigationAllowed(uri)
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            }
            if (uri == null) {
              return NavigationDecision.prevent;
            }
            return uri.host == 'lala-next.cloud' ||
                    uri.host == 'www.lala-next.cloud' ||
                    uri.host == 'oapi.map.naver.com'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
    if (widget.provider == LalaMapProviderKind.openVector) {
      unawaited(_controller.loadFlutterAsset(kLalaOpenMapEmbedAssetPath));
    } else {
      unawaited(_controller.loadRequest(_nextNaverMapUri()));
    }
  }

  @override
  void didUpdateWidget(covariant _LalaMapNativeWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Provider swaps must load the other embed document; config delivery
    // happens in onPageFinished once that document is live. Same-provider
    // updates keep the document (no camera reset) and push config only.
    final transition = resolveLalaMapDocumentTransition(
      oldProvider: oldWidget.provider,
      newProvider: widget.provider,
      clientIdChanged: oldWidget.clientId != widget.clientId,
      languageChanged: oldWidget.language != widget.language,
    );
    switch (transition) {
      case LalaMapDocumentTransition.swapToOpenVectorEmbed:
        unawaited(_controller.loadFlutterAsset(kLalaOpenMapEmbedAssetPath));
        return;
      case LalaMapDocumentTransition.swapToNaverEmbed:
        unawaited(_controller.loadRequest(_nextNaverMapUri()));
        return;
      case LalaMapDocumentTransition.keepDocument:
        break;
    }
    if (oldWidget.clientId != widget.clientId ||
        oldWidget.language != widget.language ||
        oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLng != widget.centerLng ||
        oldWidget.level != widget.level ||
        oldWidget.interactionEnabled != widget.interactionEnabled ||
        !sameLalaMapPlaces(oldWidget.places, widget.places)) {
      unawaited(_pushConfig());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEAF2FB),
      child: WebViewWidget(controller: _controller),
    );
  }

  Uri _nextNaverMapUri() {
    _revision += 1;
    return Uri.https('lala-next.cloud', '/naver-map-embed.html', {
      'r': '$_revision',
    });
  }

  Future<void> _pushConfig() {
    final config = jsonEncode(
      widget.provider == LalaMapProviderKind.openVector
          ? buildOpenVectorMapConfigPayload(
              bridgeId: _bridgeId,
              language: widget.language,
              centerLat: widget.centerLat,
              centerLng: widget.centerLng,
              level: widget.level,
              places: widget.places,
              interactionEnabled: widget.interactionEnabled,
            )
          : <String, Object?>{
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
            },
    );
    return _controller.runJavaScript(
      'window.LalaMapEmbed && window.LalaMapEmbed.setConfig($config);',
    );
  }

  void _handleMapMessage(String rawMessage) {
    final trimmed = rawMessage.trim();
    if (trimmed.isEmpty) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      decoded = null;
    }
    final decodedMessage = decoded is Map<String, dynamic> ? decoded : null;
    if (!isLalaMapEmbedMessageAccepted(
      provider: widget.provider,
      bridgeId: _bridgeId,
      message: decodedMessage,
    )) {
      return;
    }
    final message = decodedMessage!;
    final camera = decodeLalaMapCameraIdlePayload(message);
    if (camera != null) {
      widget.onCameraIdle?.call(camera);
      return;
    }
    final placeId = message['placeId']?.toString().trim();
    if (message['type'] == 'placeTap' &&
        placeId != null &&
        placeId.isNotEmpty) {
      widget.onPlaceTap?.call(placeId);
    }
  }
}

class _LalaMapNativeUnavailable extends StatelessWidget {  const _LalaMapNativeUnavailable({
    required this.message,
    required this.language,
    required this.centerLat,
    required this.centerLng,
    required this.places,
    required this.onPlaceTap,
  });

  final String message;
  final String language;
  final double centerLat;
  final double centerLng;
  final List<LalaMapPlace> places;
  final ValueChanged<String>? onPlaceTap;

  @override
  Widget build(BuildContext context) {
    return LalaMapFallbackView(
      message: message,
      language: language,
      centerLat: centerLat,
      centerLng: centerLng,
      places: places,
      onPlaceTap: onPlaceTap,
     );
   }
}
