// Native (iOS/Android/desktop) hand-off for the "open settings" recovery action.
//
// permanentlyDenied can only be resolved by the user re-granting the per-app
// Location permission, which lives on this app's own settings page. The default
// `AppSettingsType.settings` opens exactly that page on both iOS and Android.
import 'package:app_settings/app_settings.dart';

/// Native platforms can reach the OS app settings page, so a real recovery
/// action is available for a permanently-denied location.
bool get canOpenAppSettings => true;

/// Opens this app's settings page (where the per-app Location permission toggle
/// lives). Returns `false` if the hand-off fails so the UI keeps the manual
/// escape hatch usable rather than leaving the user stranded.
Future<bool> openAppSettings() async {
  try {
    await AppSettings.openAppSettings();
    return true;
  } on Object {
    return false;
  }
}
