// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';

import 'lala_map_fallback.dart';
import 'lala_map_models.dart';

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
  final normalizedClientId = clientId.trim();
  if (normalizedClientId.isEmpty) {
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
    _viewType = 'lala-naver-map-${_nextViewId++}';
    _bridgeId = '$_viewType-bridge';
    _frame = html.IFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = '0'
      ..style.backgroundColor = '#eaf2fb'
      ..setAttribute('title', _mapTitle(widget.language));
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
    _frame.setAttribute('title', _mapTitle(widget.language));
    if (oldWidget.clientId != widget.clientId ||
        oldWidget.language != widget.language) {
      _reloadFrame();
    } else if (oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLng != widget.centerLng ||
        oldWidget.level != widget.level ||
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
      ..setAttribute('title', _mapTitle(widget.language))
      ..src = Uri.base
          .resolve('naver-map-embed.html')
          .replace(queryParameters: {'r': '$_revision'})
          .toString();
  }

  void _postConfig() {
    _frame.contentWindow?.postMessage(
      jsonEncode({
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
      }),
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
    if (decoded is! Map<String, dynamic> ||
        decoded['source'] != 'lala-naver-map' ||
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

String _mapTitle(String language) => naverMapLabel(language);
