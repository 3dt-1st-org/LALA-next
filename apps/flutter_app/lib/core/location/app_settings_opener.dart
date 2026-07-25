// Wave-1 location/weather: platform-safe "open settings" hand-off.
//
// A permanently-denied location can only be recovered from the OS app settings
// page — the system permission dialog can no longer be re-surfaced. This
// abstraction exposes that hand-off behind the existing conditional-import
// pattern so the UI can offer a REAL "Open settings" action where the platform
// supports it and degrade honestly everywhere else (web cannot reliably open
// browser/site permission settings, so it must not advertise the action).
export 'app_settings_opener_stub.dart'
    if (dart.library.io) 'app_settings_opener_io.dart';
