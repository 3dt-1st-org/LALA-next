import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../browser_location.dart';

/// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
/// 위치 도메인 모델 + Geolocator/browser_location 하이브리드 provider.

class LalaLocation {
  const LalaLocation({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

enum LalaLocationResultStatus {
  found,
  // Soft denial: the user declined this request but can be asked again.
  denied,
  // OS-level permanent denial (Geolocator deniedForever). Re-prompting will not
  // show the system dialog; the user must grant from settings. Kept distinct so
  // the UI can route to settings instead of re-requesting.
  permanentlyDenied,
  // Location service unsupported/unavailable on this platform or timed out.
  unavailable,
}

class LalaLocationResult {
  const LalaLocationResult._({required this.status, this.location});

  const LalaLocationResult.found(LalaLocation location)
    : this._(status: LalaLocationResultStatus.found, location: location);

  const LalaLocationResult.denied()
    : this._(status: LalaLocationResultStatus.denied);

  const LalaLocationResult.permanentlyDenied()
    : this._(status: LalaLocationResultStatus.permanentlyDenied);

  const LalaLocationResult.unavailable()
    : this._(status: LalaLocationResultStatus.unavailable);

  final LalaLocationResultStatus status;
  final LalaLocation? location;
}

abstract class LalaLocationProvider {
  Future<LalaLocationResult> requestCurrentLocation();
}

class GeolocatorLalaLocationProvider implements LalaLocationProvider {
  const GeolocatorLalaLocationProvider();

  static const Duration _permissionTimeout = Duration(seconds: 8);
  static const Duration _positionTimeout = Duration(seconds: 12);

  @override
  Future<LalaLocationResult> requestCurrentLocation() async {
    try {
      final browserLocation = await requestBrowserLocation(_positionTimeout);
      if (browserLocation.status == BrowserLocationResultStatus.found &&
          browserLocation.lat != null &&
          browserLocation.lng != null) {
        return LalaLocationResult.found(
          LalaLocation(lat: browserLocation.lat!, lng: browserLocation.lng!),
        );
      }
      if (browserLocation.status == BrowserLocationResultStatus.denied) {
        return const LalaLocationResult.denied();
      }

      var permission = await Geolocator.checkPermission().timeout(
        _permissionTimeout,
      );
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(
          _permissionTimeout,
        );
      }
      // Why: the OS distinguishes a one-time decline from a permanent denial.
      // Mapping both to `denied` hid permanently-denied users behind a retry
      // that can never surface the system dialog, so deniedForever is reported
      // truthfully as its own status. The web boundary cannot confirm
      // permanence, so it stays at `denied` (handled above).
      if (permission == LocationPermission.deniedForever) {
        return const LalaLocationResult.permanentlyDenied();
      }
      if (permission == LocationPermission.denied) {
        return const LalaLocationResult.denied();
      }
      if (permission == LocationPermission.unableToDetermine) {
        return const LalaLocationResult.unavailable();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _positionTimeout,
        ),
      ).timeout(_positionTimeout);
      return LalaLocationResult.found(
        LalaLocation(lat: position.latitude, lng: position.longitude),
      );
    } on MissingPluginException {
      return const LalaLocationResult.unavailable();
    } on TimeoutException {
      return const LalaLocationResult.unavailable();
    } on Object {
      return const LalaLocationResult.unavailable();
    }
  }
}
