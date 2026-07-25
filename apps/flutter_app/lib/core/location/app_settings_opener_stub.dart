// Web / unsupported fallback for the "open settings" hand-off.
//
// Browser permission settings cannot be opened reliably from script (each
// browser buries them differently, and several expose no entry point at all),
// so the UI must NOT advertise a fake "Open settings" action. Instead it tells
// the user honestly to change the permission in their browser/site settings and
// keeps the manual-region escape hatch prominent.

/// Whether this platform can hand the user off to the OS app settings page.
///
/// Always `false` here (web/unsupported). The recovery UI must hide its
/// "Open settings" action when this is false.
bool get canOpenAppSettings => false;

/// Attempts to open the OS app settings page. Unsupported platforms can never
/// fulfill this, so it reports `false` instead of throwing or faking success.
Future<bool> openAppSettings() async => false;
