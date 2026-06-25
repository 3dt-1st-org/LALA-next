import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'kakao_map_fallback.dart';
import 'kakao_map_models.dart';

Widget buildKakaoMapView({
  required String javascriptKey,
  required String language,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<KakaoMapPlace> places,
  ValueChanged<String>? onPlaceTap,
  ValueChanged<KakaoMapCamera>? onCameraIdle,
}) {
  final normalizedKey = javascriptKey.trim();
  if (normalizedKey.isEmpty) {
    return _KakaoMapNativeUnavailable(
      message: language == 'en'
          ? 'The live map is not available right now.'
          : '현재 지도를 표시할 수 없습니다.',
      language: language,
      centerLat: centerLat,
      centerLng: centerLng,
      places: places,
      onPlaceTap: onPlaceTap,
    );
  }

  if (!io.Platform.isIOS && !io.Platform.isAndroid) {
    return _KakaoMapNativeUnavailable(
      message: language == 'en'
          ? 'The live map is not available right now.'
          : '현재 지도를 표시할 수 없습니다.',
      language: language,
      centerLat: centerLat,
      centerLng: centerLng,
      places: places,
      onPlaceTap: onPlaceTap,
    );
  }

  return _KakaoMapNativeWebView(
    javascriptKey: normalizedKey,
    centerLat: centerLat,
    centerLng: centerLng,
    level: level,
    places: places,
    onPlaceTap: onPlaceTap,
    onCameraIdle: onCameraIdle,
  );
}

class _KakaoMapNativeWebView extends StatefulWidget {
  const _KakaoMapNativeWebView({
    required this.javascriptKey,
    required this.centerLat,
    required this.centerLng,
    required this.level,
    required this.places,
    this.onPlaceTap,
    this.onCameraIdle,
  });

  final String javascriptKey;
  final double centerLat;
  final double centerLng;
  final int level;
  final List<KakaoMapPlace> places;
  final ValueChanged<String>? onPlaceTap;
  final ValueChanged<KakaoMapCamera>? onCameraIdle;

  @override
  State<_KakaoMapNativeWebView> createState() => _KakaoMapNativeWebViewState();
}

class _KakaoMapNativeWebViewState extends State<_KakaoMapNativeWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFEAF2FB))
      ..addJavaScriptChannel(
        'LalaMap',
        onMessageReceived: (message) => _handleMapMessage(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.prevent;
            }
            return uri.host == 'lala-next.cloud' ||
                    uri.host == 'www.lala-next.cloud' ||
                    uri.host == 'dapi.kakao.com'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(_mapUri());
  }

  @override
  void didUpdateWidget(covariant _KakaoMapNativeWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.javascriptKey != widget.javascriptKey ||
        oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLng != widget.centerLng ||
        oldWidget.level != widget.level ||
        !sameKakaoMapPlaces(oldWidget.places, widget.places)) {
      _controller.loadRequest(_mapUri());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEAF2FB),
      child: WebViewWidget(controller: _controller),
    );
  }

  Uri _mapUri() {
    return Uri.https('lala-next.cloud', '/kakao-map-embed.html', {
      'appkey': widget.javascriptKey,
      'lat': widget.centerLat.toStringAsFixed(7),
      'lng': widget.centerLng.toStringAsFixed(7),
      'level': '${widget.level}',
      'places': jsonEncode(
        widget.places
            .map(
              (place) => {
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
      ),
    });
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
    if (decoded is Map<String, dynamic>) {
      if (decoded['type'] == 'cameraIdle') {
        final lat = _asDouble(decoded['lat']);
        final lng = _asDouble(decoded['lng']);
        final level = _asInt(decoded['level']);
        if (lat != null && lng != null && level != null) {
          widget.onCameraIdle?.call(
            KakaoMapCamera(lat: lat, lng: lng, level: level),
          );
        }
        return;
      }
      final placeId = decoded['placeId']?.toString().trim();
      if (placeId != null && placeId.isNotEmpty) {
        widget.onPlaceTap?.call(placeId);
      }
      return;
    }
    widget.onPlaceTap?.call(trimmed);
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class _KakaoMapNativeUnavailable extends StatelessWidget {
  const _KakaoMapNativeUnavailable({
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
  final List<KakaoMapPlace> places;
  final ValueChanged<String>? onPlaceTap;

  @override
  Widget build(BuildContext context) {
    return KakaoMapFallbackView(
      message: message,
      language: language,
      centerLat: centerLat,
      centerLng: centerLng,
      places: places,
      onPlaceTap: onPlaceTap,
    );
  }
}
