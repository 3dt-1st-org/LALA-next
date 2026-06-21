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
  ValueChanged<KakaoMapCamera>? onCameraIdle,
}) {
  final isEnglish = language == 'en';
  if (javascriptKey.trim().isEmpty) {
    return _KakaoMapUnavailable(
      message: isEnglish
          ? 'The live map is not available right now.'
          : '현재 지도를 표시할 수 없습니다.',
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
    onCameraIdle: onCameraIdle,
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
    this.onCameraIdle,
  });

  final String javascriptKey;
  final String language;
  final double centerLat;
  final double centerLng;
  final int level;
  final List<KakaoMapPlace> places;
  final ValueChanged<String>? onPlaceTap;
  final ValueChanged<KakaoMapCamera>? onCameraIdle;

  @override
  State<_KakaoMapBackgroundBridge> createState() =>
      _KakaoMapBackgroundBridgeState();
}

class _KakaoMapBackgroundBridgeState extends State<_KakaoMapBackgroundBridge> {
  int _generation = 0;
  StreamSubscription<html.Event>? _placeTapSubscription;
  StreamSubscription<html.Event>? _cameraIdleSubscription;

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
    _cameraIdleSubscription = html.window.on['lala-map-camera-idle'].listen((
      event,
    ) {
      final detail = event is html.CustomEvent ? event.detail : null;
      final camera = _cameraFromDetail(detail);
      if (camera == null) {
        return;
      }
      widget.onCameraIdle?.call(camera);
    });
    _renderMap();
  }

  @override
  void dispose() {
    _placeTapSubscription?.cancel();
    _cameraIdleSubscription?.cancel();
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

  KakaoMapCamera? _cameraFromDetail(Object? detail) {
    Object? payload = detail;
    if (detail is String) {
      try {
        payload = jsonDecode(detail);
      } on FormatException {
        return null;
      }
    }
    if (payload is! Map) {
      return null;
    }
    final lat = _asDouble(payload['lat']);
    final lng = _asDouble(payload['lng']);
    final level = _asInt(payload['level']);
    if (lat == null || lng == null || level == null) {
      return null;
    }
    return KakaoMapCamera(lat: lat, lng: lng, level: level);
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
                ? 'Preparing the map view'
                : '지도 화면을 준비하고 있습니다',
            places: widget.places,
            centerLat: widget.centerLat,
            centerLng: widget.centerLng,
            level: widget.level,
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
    var renderedPins = 0;
    var renderedClusters = 0;

    function colorFor(category) {
      if (category === "attraction") return "#C53030";
      if (category === "restaurant") return "#F5C842";
      if (category === "event") return "#2B6CB0";
      if (category === "culture_venue") return "#0F766E";
      return "#1A202C";
    }

    function markerTextColorFor(category) {
      return category === "restaurant" ? "#1A202C" : "#ffffff";
    }

    function clusterTextColorFor(category) {
      return category === "restaurant" ? "#6B4F0D" : colorFor(category);
    }

    function iconSvgFor(category) {
      if (category === "restaurant") {
        return '<svg viewBox="0 0 24 24" width="13" height="13" aria-hidden="true"><path d="M7 3v8M5 3v8M9 3v8M5 11h4v10M16 3v18M16 3c3 2 4 5 3 9h-3" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      }
      if (category === "event") {
        return '<svg viewBox="0 0 24 24" width="13" height="13" aria-hidden="true"><rect x="4" y="5" width="16" height="15" rx="2.5" fill="none" stroke="currentColor" stroke-width="2.2"/><path d="M8 3v4M16 3v4M4 10h16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>';
      }
      return '<svg viewBox="0 0 24 24" width="13" height="13" aria-hidden="true"><path d="M4 10h16L12 4 4 10ZM6 10v8M10 10v8M14 10v8M18 10v8M4 20h16" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    }

    function shortName(name) {
      name = String(name || (${jsonEncode(isEnglish ? 'Local place' : '장소')}));
      return name.length > 14 ? name.slice(0, 14) + "..." : name;
    }

    places.forEach(function (place) {
      var isCluster = place.clusterCount != null && place.clusterCount > 1;
      var size = isCluster ? 42 : (place.selected ? 34 : 28);
      var marker = document.createElement("div");
      marker.className = isCluster ? "lala-marker lala-marker-cluster" : "lala-marker lala-marker-pin";
      marker.setAttribute("data-lala-place-id", String(place.id || ""));
      marker.setAttribute("data-lala-category", String(place.category || ""));
      if (isCluster) {
        marker.setAttribute("data-lala-cluster-count", String(place.clusterCount));
        renderedClusters += 1;
      } else {
        renderedPins += 1;
      }
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
        namePill.style.borderRadius = "12px";
        namePill.style.background = "rgba(17, 24, 39, .72)";
        namePill.style.color = "#ffffff";
        namePill.style.fontSize = "10px";
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
      if (isCluster) {
        circle.style.border = "2.2px solid " + colorFor(place.category);
      }

      var inner = document.createElement("div");
      inner.style.width = Math.round(size * 0.64) + "px";
      inner.style.height = Math.round(size * 0.64) + "px";
      inner.style.borderRadius = "50%";
      inner.style.background = colorFor(place.category);
      inner.style.display = "grid";
      inner.style.placeItems = "center";

      var label = document.createElement("div");
      label.style.color = markerTextColorFor(place.category);
      if (isCluster) {
        label.style.color = clusterTextColorFor(place.category);
      }
      label.style.fontSize = isCluster ? "14px" : (place.selected ? "13px" : "11px");
      label.style.fontWeight = "900";
      label.style.display = "grid";
      label.style.placeItems = "center";
      if (isCluster) {
        label.textContent = String(place.clusterCount);
        circle.appendChild(label);
      } else {
        label.innerHTML = iconSvgFor(place.category);
        inner.appendChild(label);
        circle.appendChild(inner);
      }
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
    container.setAttribute("data-lala-marker-pins", String(renderedPins));
    container.setAttribute("data-lala-marker-clusters", String(renderedClusters));
    container.setAttribute("data-lala-map-level", String(map.getLevel()));
    window.__lalaLastMapMarkerStats = {
      pins: renderedPins,
      clusters: renderedClusters,
      total: places.length,
      level: map.getLevel()
    };

    function dispatchCameraIdle() {
      var nextCenter = map.getCenter();
      window.dispatchEvent(new CustomEvent("lala-map-camera-idle", {
        detail: JSON.stringify({
          lat: nextCenter.getLat(),
          lng: nextCenter.getLng(),
          level: map.getLevel()
        })
      }));
    }

    kakao.maps.event.addListener(map, "dragend", dispatchCameraIdle);
    kakao.maps.event.addListener(map, "zoom_changed", dispatchCameraIdle);

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
  required int level,
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

  var renderedPins = 0;
  var renderedClusters = 0;
  for (final place in places.take(40)) {
    final point = _fallbackPosition(
      lat: place.lat,
      lng: place.lng,
      centerLat: centerLat,
      centerLng: centerLng,
    );
    final marker = html.DivElement()
      ..classes.addAll([
        'lala-marker',
        place.isCluster ? 'lala-marker-cluster' : 'lala-marker-pin',
      ])
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
    marker.dataset['lalaPlaceId'] = place.id;
    marker.dataset['lalaCategory'] = place.category;
    if (place.isCluster) {
      marker.dataset['lalaClusterCount'] = '${place.clusterCount}';
      renderedClusters += 1;
    } else {
      renderedPins += 1;
    }

    if (place.selected && !place.isCluster) {
      final namePill = html.DivElement()
        ..text = place.name.length > 14
            ? '${place.name.substring(0, 14)}...'
            : place.name
        ..style.maxWidth = '132px'
        ..style.padding = '5px 10px'
        ..style.borderRadius = '12px'
        ..style.backgroundColor = 'rgba(17, 24, 39, .72)'
        ..style.color = '#ffffff'
        ..style.fontSize = '10px'
        ..style.fontWeight = '800'
        ..style.whiteSpace = 'nowrap'
        ..style.overflow = 'hidden'
        ..style.textOverflow = 'ellipsis'
        ..style.boxShadow = '0 6px 18px rgba(15, 23, 42, .18)';
      marker.append(namePill);
    }

    final size = place.isCluster ? 42 : (place.selected ? 34 : 28);
    final circle = html.DivElement()
      ..style.width = '${size}px'
      ..style.height = '${size}px'
      ..style.borderRadius = '50%'
      ..style.backgroundColor = '#ffffff'
      ..style.boxShadow = '0 4px 14px rgba(15, 23, 42, .22)'
      ..style.display = 'grid'
      ..style.setProperty('place-items', 'center');
    if (place.isCluster) {
      circle.style.border =
          '2.2px solid ${_fallbackMarkerColor(place.category)}';
    }

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
          : _fallbackMarkerSymbol(place.category)
      ..style.color = place.isCluster
          ? _fallbackMarkerTextColorHex(place.category)
          : _fallbackMarkerIconColorHex(place.category)
      ..style.fontSize = place.isCluster ? '14px' : '11px'
      ..style.fontWeight = '900';
    if (place.isCluster) {
      circle.append(label);
    } else {
      inner.append(label);
      circle.append(inner);
    }
    marker.append(circle);
    container.append(marker);
  }
  container.setAttribute('data-lala-marker-pins', '$renderedPins');
  container.setAttribute('data-lala-marker-clusters', '$renderedClusters');
  container.setAttribute('data-lala-map-level', '$level');
  final statsPayload = jsonEncode({
    'pins': renderedPins,
    'clusters': renderedClusters,
    'total': places.length,
    'level': level,
  });
  final statsScript = html.ScriptElement()
    ..type = 'text/javascript'
    ..text = 'window.__lalaLastMapMarkerStats = $statsPayload;';
  html.document.body?.append(statsScript);
  statsScript.remove();
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

String _fallbackMarkerColor(String category) {
  return switch (category) {
    'attraction' => '#C53030',
    'restaurant' => '#F5C842',
    'event' => '#2B6CB0',
    'culture_venue' => '#0F766E',
    _ => '#1A202C',
  };
}

String _fallbackMarkerTextColorHex(String category) {
  return switch (category) {
    'restaurant' => '#6B4F0D',
    'event' => '#2B6CB0',
    'culture_venue' => '#0F766E',
    'attraction' => '#C53030',
    _ => '#1A202C',
  };
}

String _fallbackMarkerIconColorHex(String category) {
  return category == 'restaurant' ? '#1a202c' : '#ffffff';
}

Color _fallbackMarkerTextColor(String category) {
  return Color(
    int.parse(_fallbackMarkerTextColorHex(category).replaceFirst('#', '0xFF')),
  );
}

IconData _fallbackMarkerIcon(String category) {
  return switch (category) {
    'restaurant' => Icons.restaurant,
    'event' => Icons.calendar_month,
    'culture_venue' => Icons.account_balance,
    'attraction' => Icons.account_balance,
    _ => Icons.place,
  };
}

String _fallbackMarkerSymbol(String category) {
  return switch (category) {
    'restaurant' => '♨',
    'event' => '□',
    'culture_venue' => '▥',
    'attraction' => '▥',
    _ => '•',
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
    final visiblePlaces = places.take(24).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          key: ValueKey(
            'kakao-map-fallback-center-${centerLat.toStringAsFixed(4)}-${centerLng.toStringAsFixed(4)}',
          ),
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
                  color: const Color(0xFF111827).withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
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
                    color: Colors.white,
                    fontSize: 10,
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
                border: place.isCluster
                    ? Border.all(color: color, width: 2.2)
                    : null,
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 14,
                    offset: Offset(0, 4),
                    color: Color(0x380F172A),
                  ),
                ],
              ),
              child: place.isCluster
                  ? Text(
                      '${place.clusterCount}',
                      style: TextStyle(
                        color: _fallbackMarkerTextColor(place.category),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : Container(
                      width: size * 0.64,
                      height: size * 0.64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        _fallbackMarkerIcon(place.category),
                        color: place.category == 'restaurant'
                            ? const Color(0xFF1A202C)
                            : Colors.white,
                        size: place.selected ? 15 : 13,
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
