# Task 4 Report: Flutter Logto Session and Account UI

## Status

DONE - independent review Important findings resolved.

## Review Fixes

- Retained the legacy `android:fullBackupContent="@xml/backup_rules"` contract and added the Android 12+ `android:dataExtractionRules="@xml/data_extraction_rules"` contract.
- Added API 31+ cloud-backup and device-transfer exclusions for the `FlutterSecureStorage` shared preferences.
- Added parsed XML contract tests for the manifest, legacy backup rules, and Android 12+ extraction rules. `xml` is now an explicit test dependency.
- Made `LalaAuthConfig.fromEnvironment()` testable through optional platform, base-URI, and environment-value inputs while preserving production defaults.
- Trimmed endpoint, selected app ID, audience, redirect, and post-logout values once before storing the immutable config. `LogtoConfig`, token requests, and API client composition consume only those stored values.
- Added platform-aware redirect validation: Web accepts HTTPS and loopback HTTP callbacks; native accepts the registered `cloud.lalanext.lala` scheme. Optional post-logout callbacks follow the same platform policy.
- Added focused Web/native app-ID selection, whitespace, default callback, malformed redirect, post-logout, and SDK adapter tests.
- Replaced the normal settings UUID display with a neutral signed-in status while retaining `/me`, deletion, and session behavior.

## RED/GREEN Evidence

1. Android backup RED: `flutter test test/android_backup_contract_test.dart`
   - Failed because `android:dataExtractionRules` was null and `data_extraction_rules.xml` did not exist; the legacy exclusion test already passed.
2. Android backup GREEN: the same command passed all 3 manifest/resource contract tests after adding the API 31+ policy.
3. Config RED: `flutter test test/auth/auth_config_test.dart`
   - Failed to compile because `fromEnvironment` did not accept injectable platform/environment inputs.
4. Config GREEN: the same command passed all 7 normalization, URI validation, and platform app-ID selection tests.
5. Account UI RED: the focused sign-in widget test found `계정 ID: account-123` after the expectation changed to no UUID disclosure.
6. Account UI GREEN: the focused widget test passed after rendering only the neutral signed-in status.
7. Adapter coverage: 4 direct `LogtoAuthGateway` tests pass for redirect/resource forwarding, signed-out token handling, hosted logout cancellation after local clearing, and retained-session error propagation.

## Final Verification

- `flutter analyze`
  - `No issues found!`
- `flutter test`
  - `99` tests passed.
- `flutter build web --release`
  - Release Web build succeeded.
- `cmp web/auth-callback.html build/web/auth-callback.html`
  - Passed; the callback page is present unchanged in the release artifact.
- `git diff --check`
  - Passed.

Flutter commands used the existing command-local `/private/tmp/lala-flutter-tools/xcrun` output wrapper because Flutter 3.44's native-assets `otool` parser rejects parentheses in this required worktree path (`feat(auth)`). No Flutter SDK or repository source was modified by the workaround.

## Files

- `.superpowers/sdd/task-4-report.md`
- `apps/flutter_app/android/app/src/main/AndroidManifest.xml`
- `apps/flutter_app/android/app/src/main/res/xml/data_extraction_rules.xml`
- `apps/flutter_app/lib/auth/logto_auth_gateway.dart`
- `apps/flutter_app/lib/main.dart`
- `apps/flutter_app/pubspec.lock`
- `apps/flutter_app/pubspec.yaml`
- `apps/flutter_app/test/android_backup_contract_test.dart`
- `apps/flutter_app/test/auth/auth_config_test.dart`
- `apps/flutter_app/test/auth/logto_auth_gateway_test.dart`
- `apps/flutter_app/test/widget_test.dart`

## Self-Review

- Verified API 31+ excludes secure storage from both cloud backup and device transfer while older Android versions retain the legacy exclusion.
- Verified all environment strings are normalized before config construction and downstream SDK/API composition reads only immutable config fields.
- Verified Web does not accept native callback schemes, native does not accept Web callback schemes, malformed callbacks disable auth, and the unselected platform app ID is never used as fallback.
- Verified the settings UI no longer renders `user_id`, while controller state and the account deletion flow still use the `/me` response normally.
- Verified direct adapter tests do not open browsers or networks and require no production abstraction changes.
- Verified concurrent Task 5 `apps/api` and unrelated `docs/superpowers` changes are excluded from this report and commit scope.

## Concerns

- The release Web build still reports the existing WASM dry-run incompatibility from `flutter_secure_storage_web` (`dart:html`/`dart:js_util`). The requested JavaScript release build succeeds; WASM output is not enabled by Task 4.
- Flutter still warns that the installed secure-storage/web-auth plugins do not support Swift Package Manager; the existing CocoaPods fallback remains unchanged.
