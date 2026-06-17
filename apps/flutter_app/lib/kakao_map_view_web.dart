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
  required String language,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<KakaoMapPlace> places,
  ValueChanged<String>? onPlaceTap,
}) {
  final isEnglish = language == 'en';
  if (javascriptKey.trim().isEmpty) {
    return _KakaoMapUnavailable(
      message: isEnglish
          ? 'Set the Kakao map key to show the live map.'
          : '카카오 지도 키를 설정하면 실제 지도가 표시됩니다.',
      language: language,
      places: places,
      centerLat: centerLat,
      centerLng: centerLng,
    );
  }

  return _KakaoMapBackgroundBridge(
    javascriptKey: javascriptKey.trim(),
    language: language,
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
    required this.language,
    required this.centerLat,
    required this.centerLng,
    required this.level,
    required this.places,
    this.onPlaceTap,
  });

  final String javascriptKey;
  final String language;
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
        oldWidget.language != widget.language ||
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
      ..text = widget.language == 'en' ? 'Loading Kakao Map' : '카카오 지도 로딩 중';
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
          _drawFallbackMap(
            container,
            language: widget.language,
            message: widget.language == 'en'
                ? 'Waiting for the Kakao map connection'
                : '카카오 지도 연결 대기 중',
            places: widget.places,
            centerLat: widget.centerLat,
            centerLng: widget.centerLng,
          );
        });
  }

  void _drawKakaoMap(html.DivElement container) {
    container.children.clear();
    container.text = '';
    container.style.display = 'block';
    final isEnglish = widget.language == 'en';
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
                'clusterMemberIds': place.clusterMemberIds,
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
      if (${jsonEncode(isEnglish)}) {
        if (category === "restaurant") return "F";
        if (category === "event") return "E";
        if (category === "culture_venue") return "C";
        if (category === "attraction") return "A";
        return "L";
      }
      if (category === "restaurant") return "맛";
      if (category === "event") return "행";
      if (category === "culture_venue") return "문";
      if (category === "attraction") return "명";
      return "L";
    }

    function shortName(name) {
      name = String(name || (${jsonEncode(isEnglish ? 'Local place' : '장소')}));
      return name.length > 14 ? name.slice(0, 14) + "..." : name;
    }

    places.forEach(function (place) {
      var isCluster = place.clusterCount != null && place.clusterCount > 1;
      var size = isCluster ? Math.min(58, 34 + place.clusterCount * 4) : (place.selected ? 42 : 34);
      var marker = document.createElement("div");
      marker.title = place.name;
      marker.style.display = "flex";
      marker.style.flexDirection = "column";
      marker.style.alignItems = "center";
      marker.style.gap = "5px";
      marker.style.pointerEvents = "auto";
      marker.style.cursor = "pointer";
      marker.style.fontFamily = "system-ui, -apple-system, sans-serif";

      if (place.selected && !isCluster) {
        var namePill = document.createElement("div");
        namePill.textContent = shortName(place.name);
        namePill.style.maxWidth = "132px";
        namePill.style.padding = "5px 10px";
        namePill.style.borderRadius = "999px";
        namePill.style.background = "#ffffff";
        namePill.style.color = "#111827";
        namePill.style.fontSize = "11px";
        namePill.style.fontWeight = "800";
        namePill.style.whiteSpace = "nowrap";
        namePill.style.overflow = "hidden";
        namePill.style.textOverflow = "ellipsis";
        namePill.style.boxShadow = "0 6px 18px rgba(15, 23, 42, 0.18)";
        marker.appendChild(namePill);
      }

      var circle = document.createElement("div");
      circle.style.width = size + "px";
      circle.style.height = size + "px";
      circle.style.borderRadius = "50%";
      circle.style.background = "#ffffff";
      circle.style.boxShadow = "0 4px 14px rgba(15, 23, 42, 0.22)";
      circle.style.display = "grid";
      circle.style.placeItems = "center";

      var inner = document.createElement("div");
      inner.style.width = Math.round(size * 0.64) + "px";
      inner.style.height = Math.round(size * 0.64) + "px";
      inner.style.borderRadius = "50%";
      inner.style.background = colorFor(place.category);
      inner.style.display = "grid";
      inner.style.placeItems = "center";

      var label = document.createElement("div");
      label.style.color = place.category === "event" ? "#1A202C" : "#ffffff";
      label.style.fontSize = isCluster ? "15px" : (place.selected ? "13px" : "11px");
      label.style.fontWeight = "900";
      label.textContent = isCluster ? String(place.clusterCount) : glyphFor(place.category);
      inner.appendChild(label);
      circle.appendChild(inner);
      marker.appendChild(circle);
      marker.addEventListener("click", function (event) {
        event.stopPropagation();
        if (place.id) {
          window.dispatchEvent(new CustomEvent("lala-map-place-tap", {
            detail: String(place.id)
          }));
        }
      });

      var overlay = new kakao.maps.CustomOverlay({
        position: new kakao.maps.LatLng(place.lat, place.lng),
        content: marker,
        yAnchor: place.selected && !isCluster ? 1.0 : 0.5,
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

void _drawFallbackMap(
  html.DivElement container, {
  required String language,
  required String message,
  required List<KakaoMapPlace> places,
  required double centerLat,
  required double centerLng,
}) {
  container.children.clear();
  container.text = '';
  container
    ..style.display = 'block'
    ..style.padding = '0'
    ..style.boxSizing = 'border-box'
    ..style.backgroundColor = '#dceee2'
    ..style.backgroundImage =
        'linear-gradient(90deg, rgba(43,108,176,.10) 1px, transparent 1px),'
        'linear-gradient(0deg, rgba(43,108,176,.10) 1px, transparent 1px),'
        'radial-gradient(circle at 16% 24%, rgba(21,128,61,.22) 0 12%, transparent 13%),'
        'radial-gradient(circle at 80% 72%, rgba(21,128,61,.20) 0 10%, transparent 11%),'
        'linear-gradient(135deg, #eaf7ee 0%, #f8fafc 54%, #e7f1ff 100%)'
    ..style.backgroundSize =
        '54px 54px, 54px 54px, 100% 100%, 100% 100%, 100% 100%'
    ..style.color = '#1a202c'
    ..style.fontWeight = '800'
    ..style.overflow = 'hidden';

  final roadLayer = html.DivElement()
    ..style.position = 'absolute'
    ..style.backgroundImage =
        'linear-gradient(118deg, transparent 0 38%, rgba(255,255,255,.82) 39% 42%, transparent 43% 100%),'
        'linear-gradient(74deg, transparent 0 48%, rgba(255,255,255,.72) 49% 51%, transparent 52% 100%),'
        'linear-gradient(0deg, transparent 0 58%, rgba(245,200,66,.45) 59% 60%, transparent 61% 100%)';
  roadLayer.style.setProperty('inset', '0');
  container.append(roadLayer);

  final riverLayer = html.DivElement()
    ..style.position = 'absolute'
    ..style.left = '-8%'
    ..style.top = '55%'
    ..style.width = '116%'
    ..style.height = '70px'
    ..style.transform = 'rotate(-13deg)'
    ..style.borderRadius = '999px'
    ..style.backgroundColor = 'rgba(43,108,176,.16)';
  container.append(riverLayer);

  final notice = html.DivElement()
    ..text = message
    ..style.position = 'absolute'
    ..style.left = '50%'
    ..style.top = '48%'
    ..style.transform = 'translate(-50%, -50%)'
    ..style.padding = '9px 13px'
    ..style.borderRadius = '999px'
    ..style.backgroundColor = 'rgba(255,255,255,.86)'
    ..style.boxShadow = '0 8px 18px rgba(15, 23, 42, .14)'
    ..style.color = '#334155'
    ..style.fontSize = '13px'
    ..style.fontFamily = 'system-ui, -apple-system, sans-serif';
  container.append(notice);

  final visiblePlaces = places.isEmpty
      ? _fallbackHtmlPlaces(centerLat, centerLng, language)
      : places;
  for (final place in visiblePlaces.take(40)) {
    final point = _fallbackPosition(
      lat: place.lat,
      lng: place.lng,
      centerLat: centerLat,
      centerLng: centerLng,
    );
    final marker = html.DivElement()
      ..title = place.name
      ..style.position = 'absolute'
      ..style.left = '${point.x}%'
      ..style.top = '${point.y}%'
      ..style.transform = place.selected && !place.isCluster
          ? 'translate(-50%, -100%)'
          : 'translate(-50%, -50%)'
      ..style.display = 'flex'
      ..style.flexDirection = 'column'
      ..style.alignItems = 'center'
      ..style.gap = '5px'
      ..style.fontFamily = 'system-ui, -apple-system, sans-serif';

    if (place.selected && !place.isCluster) {
      final namePill = html.DivElement()
        ..text = place.name.length > 14
            ? '${place.name.substring(0, 14)}...'
            : place.name
        ..style.maxWidth = '132px'
        ..style.padding = '5px 10px'
        ..style.borderRadius = '999px'
        ..style.backgroundColor = '#ffffff'
        ..style.color = '#111827'
        ..style.fontSize = '11px'
        ..style.fontWeight = '800'
        ..style.whiteSpace = 'nowrap'
        ..style.overflow = 'hidden'
        ..style.textOverflow = 'ellipsis'
        ..style.boxShadow = '0 6px 18px rgba(15, 23, 42, .18)';
      marker.append(namePill);
    }

    final size = place.isCluster ? 48 : (place.selected ? 42 : 34);
    final circle = html.DivElement()
      ..style.width = '${size}px'
      ..style.height = '${size}px'
      ..style.borderRadius = '50%'
      ..style.backgroundColor = '#ffffff'
      ..style.boxShadow = '0 4px 14px rgba(15, 23, 42, .22)'
      ..style.display = 'grid'
      ..style.setProperty('place-items', 'center');

    final innerSize = (size * 0.64).round();
    final inner = html.DivElement()
      ..style.width = '${innerSize}px'
      ..style.height = '${innerSize}px'
      ..style.borderRadius = '50%'
      ..style.backgroundColor = _fallbackMarkerColor(place.category)
      ..style.display = 'grid'
      ..style.setProperty('place-items', 'center');

    final label = html.DivElement()
      ..text = place.isCluster
          ? '${place.clusterCount}'
          : _fallbackMarkerGlyph(place.category, language)
      ..style.color = place.category == 'event' ? '#1a202c' : '#ffffff'
      ..style.fontSize = place.isCluster ? '15px' : '11px'
      ..style.fontWeight = '900';
    inner.append(label);
    circle.append(inner);
    marker.append(circle);
    container.append(marker);
  }
}

({double x, double y}) _fallbackPosition({
  required double lat,
  required double lng,
  required double centerLat,
  required double centerLng,
}) {
  final x = 50 + ((lng - centerLng) * 7200);
  final y = 50 - ((lat - centerLat) * 9000);
  return (x: x.clamp(8, 92).toDouble(), y: y.clamp(12, 82).toDouble());
}

List<KakaoMapPlace> _fallbackHtmlPlaces(
  double centerLat,
  double centerLng,
  String language,
) {
  final isEnglish = language == 'en';
  return [
    KakaoMapPlace(
      id: 'fallback-center',
      name: isEnglish ? 'Current recommendation' : '현재 추천 지점',
      category: 'attraction',
      lat: centerLat,
      lng: centerLng,
      selected: true,
    ),
    KakaoMapPlace(
      id: 'fallback-food',
      name: isEnglish ? 'Local food' : '로컬 맛집',
      category: 'restaurant',
      lat: centerLat - 0.0015,
      lng: centerLng + 0.0012,
    ),
    KakaoMapPlace(
      id: 'fallback-culture',
      name: isEnglish ? 'Culture event' : '문화 행사',
      category: 'event',
      lat: centerLat + 0.0012,
      lng: centerLng - 0.001,
    ),
  ];
}

String _fallbackMarkerColor(String category) {
  return switch (category) {
    'restaurant' => '#C53030',
    'event' => '#F5C842',
    'culture_venue' => '#2B6CB0',
    'attraction' => '#D73333',
    _ => '#1A202C',
  };
}

String _fallbackMarkerGlyph(String category, String language) {
  if (language == 'en') {
    return switch (category) {
      'restaurant' => 'F',
      'event' => 'E',
      'culture_venue' => 'C',
      'attraction' => 'A',
      _ => 'L',
    };
  }
  return switch (category) {
    'restaurant' => '맛',
    'event' => '행',
    'culture_venue' => '문',
    'attraction' => '명',
    _ => 'L',
  };
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
  const _KakaoMapUnavailable({
    required this.message,
    required this.language,
    required this.places,
    required this.centerLat,
    required this.centerLng,
  });

  final String message;
  final String language;
  final List<KakaoMapPlace> places;
  final double centerLat;
  final double centerLng;

  @override
  Widget build(BuildContext context) {
    final visiblePlaces = places.isEmpty
        ? _fallbackHtmlPlaces(centerLat, centerLng, language)
        : places.take(24).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: const Color(0xFFEAF2FB),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _FallbackFlutterMapPainter()),
              ),
              for (final place in visiblePlaces)
                _FallbackFlutterMarker(
                  place: place,
                  language: language,
                  position: _fallbackPosition(
                    lat: place.lat,
                    lng: place.lng,
                    centerLat: centerLat,
                    centerLng: centerLng,
                  ),
                ),
              Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(999),
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
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FallbackFlutterMarker extends StatelessWidget {
  const _FallbackFlutterMarker({
    required this.place,
    required this.language,
    required this.position,
  });

  final KakaoMapPlace place;
  final String language;
  final ({double x, double y}) position;

  @override
  Widget build(BuildContext context) {
    final size = place.isCluster ? 48.0 : (place.selected ? 42.0 : 34.0);
    final color = Color(
      int.parse(_fallbackMarkerColor(place.category).replaceFirst('#', '0xFF')),
    );
    final screenSize = MediaQuery.sizeOf(context);
    return Positioned(
      left: screenSize.width * position.x / 100,
      top: screenSize.height * position.y / 100,
      child: Transform.translate(
        offset: Offset(-size / 2, place.selected ? -size - 34 : -size / 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (place.selected && !place.isCluster) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 132),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 6),
                      color: Color(0x2E0F172A),
                    ),
                  ],
                ),
                child: Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 5),
            ],
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 14,
                    offset: Offset(0, 4),
                    color: Color(0x380F172A),
                  ),
                ],
              ),
              child: Container(
                width: size * 0.64,
                height: size * 0.64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  place.isCluster
                      ? '${place.clusterCount}'
                      : _fallbackMarkerGlyph(place.category, language),
                  style: TextStyle(
                    color: place.category == 'event'
                        ? const Color(0xFF1A202C)
                        : Colors.white,
                    fontSize: place.isCluster ? 15 : 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackFlutterMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEAF7EE), Color(0xFFF8FAFC), Color(0xFFE7F1FF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final parkPaint = Paint()..color = const Color(0x3322C55E);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.16, size.height * 0.24),
        width: size.width * 0.34,
        height: size.height * 0.26,
      ),
      parkPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.80, size.height * 0.72),
        width: size.width * 0.28,
        height: size.height * 0.22,
      ),
      parkPaint,
    );

    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..strokeWidth = 22
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final roadPath = Path()
      ..moveTo(size.width * -0.1, size.height * 0.76)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.52,
        size.width * 0.54,
        size.height * 0.58,
        size.width * 1.1,
        size.height * 0.36,
      );
    canvas.drawPath(roadPath, roadPaint);

    final sideRoadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.58)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.34, size.height * -0.1),
      Offset(size.width * 0.72, size.height * 1.1),
      sideRoadPaint,
    );

    final riverPaint = Paint()..color = const Color(0x292B6CB0);
    final riverPath = Path()
      ..moveTo(size.width * -0.1, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.72,
        size.width * 1.1,
        size.height * 0.56,
      )
      ..lineTo(size.width * 1.1, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.42,
        size.height * 0.82,
        size.width * -0.1,
        size.height * 0.70,
      )
      ..close();
    canvas.drawPath(riverPath, riverPaint);
  }

  @override
  bool shouldRepaint(covariant _FallbackFlutterMapPainter oldDelegate) => false;
}
