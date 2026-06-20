enum BrowserLocationResultStatus { found, denied, unavailable }

class BrowserLocationResult {
  const BrowserLocationResult._({required this.status, this.lat, this.lng});

  const BrowserLocationResult.found({required double lat, required double lng})
    : this._(status: BrowserLocationResultStatus.found, lat: lat, lng: lng);

  const BrowserLocationResult.denied()
    : this._(status: BrowserLocationResultStatus.denied);

  const BrowserLocationResult.unavailable()
    : this._(status: BrowserLocationResultStatus.unavailable);

  final BrowserLocationResultStatus status;
  final double? lat;
  final double? lng;
}
