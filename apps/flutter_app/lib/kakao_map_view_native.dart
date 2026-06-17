import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'kakao_map_models.dart';

Widget buildKakaoMapView({
  required String javascriptKey,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<KakaoMapPlace> places,
  ValueChanged<String>? onPlaceTap,
}) {
  final normalizedKey = javascriptKey.trim();
  if (normalizedKey.isEmpty) {
    return const _KakaoMapNativeUnavailable(
      message: 'KAKAO_JAVASCRIPT_KEY를 설정하면 실제 카카오 지도가 표시됩니다.',
    );
  }

  if (!io.Platform.isIOS && !io.Platform.isAndroid) {
    return const _KakaoMapNativeUnavailable(message: 'Kakao Map API');
  }

  return _KakaoMapNativeWebView(
    javascriptKey: normalizedKey,
    centerLat: centerLat,
    centerLng: centerLng,
    level: level,
    places: places,
    onPlaceTap: onPlaceTap,
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
  });

  final String javascriptKey;
  final double centerLat;
  final double centerLng;
  final int level;
  final List<KakaoMapPlace> places;
  final ValueChanged<String>? onPlaceTap;

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
        onMessageReceived: (message) =>
            widget.onPlaceTap?.call(message.message),
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
        oldWidget.places != widget.places) {
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
                'selected': place.selected,
              },
            )
            .toList(),
      ),
    });
  }
}

class _KakaoMapNativeUnavailable extends StatelessWidget {
  const _KakaoMapNativeUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2FB),
      alignment: Alignment.center,
      child: Semantics(
        label: 'Kakao Map API fallback',
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 8),
                color: Color(0x18000000),
              ),
            ],
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF1A202C),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
