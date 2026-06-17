// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import 'kakao_map_models.dart';

const _backgroundMapId = 'lala-kakao-background-map';
String? _loadedSdkKey;
Future<void>? _sdkLoader;

Widget buildKakaoMapView({
  required String javascriptKey,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<KakaoMapPlace> places,
  ValueChanged<String>? onPlaceTap,
}) {
  if (javascriptKey.trim().isEmpty) {
    return const _KakaoMapUnavailable(
      message: 'KAKAO_JAVASCRIPT_KEY를 설정하면 실제 카카오 지도가 표시됩니다.',
    );
  }

  return _KakaoMapBackgroundBridge(
    javascriptKey: javascriptKey.trim(),
    centerLat: centerLat,
    centerLng: centerLng,
    level: level,
    places: places,
    onPlaceTap: onPlaceTap,
  );
}

class _KakaoMapBackgroundBridge extends StatefulWidget {
  const _KakaoMapBackgroundBridge({
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
  State<_KakaoMapBackgroundBridge> createState() =>
      _KakaoMapBackgroundBridgeState();
}

class _KakaoMapBackgroundBridgeState extends State<_KakaoMapBackgroundBridge> {
  int _generation = 0;
  StreamSubscription<html.Event>? _placeTapSubscription;

  @override
  void initState() {
    super.initState();
    _placeTapSubscription = html.window.on['lala-map-place-tap'].listen((
      event,
    ) {
      final detail = event is html.CustomEvent ? event.detail : null;
      if (detail is String && detail.trim().isNotEmpty) {
        widget.onPlaceTap?.call(detail.trim());
      }
    });
    _renderMap();
  }

  @override
  void dispose() {
    _placeTapSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _KakaoMapBackgroundBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.javascriptKey != widget.javascriptKey ||
        oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLng != widget.centerLng ||
        oldWidget.level != widget.level ||
        oldWidget.places != widget.places) {
      _renderMap();
    }
  }

  @override
  Widget build(BuildContext context) {
    _makeFlutterLayerTransparent();
    return const SizedBox.expand();
  }

  void _renderMap() {
    final generation = ++_generation;
    final container = _ensureBackgroundContainer();
    container.children.clear();
    container
      ..style.display = 'grid'
      ..style.color = '#1a202c'
      ..style.fontWeight = '800'
      ..style.setProperty('place-items', 'center')
      ..text = 'Kakao Map API 로딩 중';
    _makeFlutterLayerTransparent();

    _ensureKakaoMapsSdk(widget.javascriptKey)
        .then((_) {
          if (!mounted || generation != _generation) {
            return;
          }
          _drawKakaoMap(container);
        })
        .catchError((Object _) {
          if (!mounted || generation != _generation) {
            return;
          }
          container.children.clear();
          container
            ..style.display = 'grid'
            ..style.padding = '24px'
            ..style.boxSizing = 'border-box'
            ..style.backgroundColor = '#eaf2fb'
            ..style.color = '#1a202c'
            ..style.fontWeight = '800'
            ..style.setProperty('place-items', 'center')
            ..text = '카카오 지도 로드에 실패했습니다. 도메인 등록과 JavaScript Key를 확인하세요.';
        });
  }

  void _drawKakaoMap(html.DivElement container) {
    container.children.clear();
    container.text = '';
    container.style.display = 'block';
    final placesPayload = Uri.encodeComponent(
      jsonEncode(
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
    );

    final script = html.ScriptElement()
      ..type = 'text/javascript'
      ..text =
          '''
(function () {
  var container = document.getElementById(${jsonEncode(container.id)});
  if (!container || !window.kakao || !window.kakao.maps) {
    return;
  }
  var places = JSON.parse(decodeURIComponent(${jsonEncode(placesPayload)}));
  window.kakao.maps.load(function () {
    container.innerHTML = "";
    var center = new kakao.maps.LatLng(${widget.centerLat}, ${widget.centerLng});
    var map = new kakao.maps.Map(container, { center: center, level: ${widget.level} });
    var circle = new kakao.maps.Circle({
      center: center,
      radius: 95,
      strokeWeight: 2,
      strokeColor: "#2B6CB0",
      strokeOpacity: 0.75,
      fillColor: "#2B6CB0",
      fillOpacity: 0.12
    });
    circle.setMap(map);

    function colorFor(category) {
      if (category === "restaurant") return "#C53030";
      if (category === "event") return "#F5C842";
      if (category === "culture_venue") return "#2B6CB0";
      if (category === "attraction") return "#D73333";
      return "#1A202C";
    }

    function glyphFor(category) {
      if (category === "restaurant") return "맛";
      if (category === "event") return "행";
      if (category === "culture_venue") return "문";
      if (category === "attraction") return "명";
      return "L";
    }

    places.forEach(function (place) {
      var isCluster = place.clusterCount != null && place.clusterCount > 1;
      var size = isCluster ? Math.min(66, 38 + place.clusterCount * 4) : (place.selected ? 58 : 42);
      var marker = document.createElement("div");
      marker.title = place.name;
      marker.style.width = size + "px";
      marker.style.height = size + "px";
      marker.style.borderRadius = isCluster ? "50%" : "50% 50% 50% 8px";
      marker.style.background = colorFor(place.category);
      marker.style.border = place.selected ? "5px solid #ffffff" : "3px solid #ffffff";
      marker.style.boxShadow = "0 10px 24px rgba(15, 23, 42, 0.26)";
      marker.style.transform = isCluster ? "none" : "rotate(-45deg)";
      marker.style.display = "grid";
      marker.style.placeItems = "center";
      marker.style.pointerEvents = "auto";
      marker.style.cursor = "pointer";

      var label = document.createElement("div");
      label.style.transform = isCluster ? "none" : "rotate(45deg)";
      label.style.color = place.category === "event" ? "#1A202C" : "#ffffff";
      label.style.fontSize = isCluster ? "16px" : (place.selected ? "15px" : "13px");
      label.style.fontWeight = "900";
      label.style.fontFamily = "system-ui, -apple-system, sans-serif";
      label.textContent = isCluster ? String(place.clusterCount) : glyphFor(place.category);
      marker.appendChild(label);
      marker.addEventListener("click", function (event) {
        event.stopPropagation();
        if (!isCluster && place.id) {
          window.dispatchEvent(new CustomEvent("lala-map-place-tap", {
            detail: String(place.id)
          }));
        }
      });

      var overlay = new kakao.maps.CustomOverlay({
        position: new kakao.maps.LatLng(place.lat, place.lng),
        content: marker,
        yAnchor: 1.08,
        zIndex: place.selected ? 12 : (isCluster ? 9 : 6)
      });
      overlay.setMap(map);
    });

    window.setTimeout(function () {
      map.relayout();
      map.setCenter(center);
    }, 0);
  });
})();
''';
    html.document.body?.append(script);
    script.remove();
  }
}

html.DivElement _ensureBackgroundContainer() {
  var container = html.document.getElementById(_backgroundMapId);
  if (container is! html.DivElement) {
    container = html.DivElement()..id = _backgroundMapId;
    html.document.body?.insertBefore(container, html.document.body?.firstChild);
  }
  container
    ..style.position = 'fixed'
    ..style.left = '0'
    ..style.top = '0'
    ..style.width = '100vw'
    ..style.height = '100vh'
    ..style.zIndex = '0'
    ..style.pointerEvents = 'none'
    ..style.overflow = 'hidden'
    ..style.backgroundColor = '#eaf2fb';
  return container;
}

void _makeFlutterLayerTransparent() {
  html.document.documentElement?.style.backgroundColor = 'transparent';
  html.document.body?.style.backgroundColor = 'transparent';
  for (final element in html.document.querySelectorAll(
    'flutter-view, flt-glass-pane, flt-scene-host',
  )) {
    element.style.backgroundColor = 'transparent';
  }
}

Future<void> _ensureKakaoMapsSdk(String javascriptKey) {
  if (_loadedSdkKey == javascriptKey && _sdkLoader != null) {
    return _sdkLoader!;
  }

  _loadedSdkKey = javascriptKey;
  final completer = Completer<void>();
  _sdkLoader = completer.future;

  html.document
      .querySelectorAll('script[data-lala-kakao-map-sdk="true"]')
      .forEach((element) => element.remove());

  final script = html.ScriptElement()
    ..type = 'text/javascript'
    ..async = true
    ..dataset['lalaKakaoMapSdk'] = 'true'
    ..src =
        'https://dapi.kakao.com/v2/maps/sdk.js?appkey=${Uri.encodeComponent(javascriptKey)}&libraries=services,clusterer&autoload=false';

  script.onLoad.first.then((_) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });

  script.onError.first.then((_) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Kakao Maps SDK failed to load.'));
    }
  });

  html.document.head?.append(script);
  return completer.future;
}

class _KakaoMapUnavailable extends StatelessWidget {
  const _KakaoMapUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2FB),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
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
    );
  }
}
