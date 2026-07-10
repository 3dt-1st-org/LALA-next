# Task 4 Report: Flutter Logto Session and Account UI

## Status

DONE

## Implementation

- Added `logto_dart_sdk: ^3.0.0` and the generated Flutter plugin/CocoaPods integration needed by Logto's secure storage and hosted web authentication dependencies.
- Added immutable `LalaAuthConfig.fromEnvironment()` selection for Web/native app IDs, HTTPS endpoint/audience validation, native and Web callback defaults, and optional redirect overrides. No Flutter client secret is accepted or stored.
- Added an injectable `LalaAuthGateway`, `LalaAccountApi`, immutable `LalaAuthState`, and `LalaAuthController` covering disabled, signed-out, busy, signed-in, and safe error states.
- Added the production factory composing `LogtoClient`, Task 3 `LalaApiClient`, dynamic resource token refresh, `/me`, and account deletion. Signed-out requests return a null token instead of surfacing Logto's `not_authenticated` exception.
- Added controller ownership to `LalaHomePage`, dynamic `LalaAccessTokenProvider` propagation through `LalaAppConfig`/`LalaApiBackend`, backend refresh after successful sign-in/sign-out/deletion, and disposal-safe asynchronous initialization.
- Added a compact Account section at the top of the existing settings sheet with Korean/English copy, hosted sign-in, logout, stable busy state, internal account ID display from `/me`, safe inline errors, and confirmation-only destructive deletion. Guest map startup remains unchanged.
- Added the official `flutter_web_auth_2` callback page, Android callback activity, secure-storage backup exclusion, and removal of the empty `taskAffinity`.

## RED/GREEN Evidence

1. Controller RED: `flutter test test/auth/auth_controller_test.dart`
   - Failed during loading because `lib/auth/auth_controller.dart`, `lib/auth/logto_auth_gateway.dart`, and their contracts did not exist.
2. Controller GREEN: `flutter test test/auth/auth_controller_test.dart`
   - Initial required controller suite passed with 9 tests after implementation.
3. Widget RED: `flutter test test/widget_test.dart --plain-name 'signed-out account action signs in through the injected gateway'`
   - Failed because `LalaAppConfig.accessTokenProvider` and `LalaApp.authControllerFactory` did not exist.
4. Widget GREEN: `flutter test test/widget_test.dart --name '(account|disabled auth|signed-out|signed-in)'`
   - All 6 new account/guest-map widget scenarios passed.
5. Review RED: focused controller tests failed for a signed-out token reaching the gateway and for deletion restoring stale signed-in UI after hosted logout failure.
6. Review GREEN: the controller suite passed after signed-out token gating and deletion/logout separation.
7. Lifecycle RED: pending initialization completed after `dispose()` and raised `A LalaAuthController was used after being disposed.`
8. Lifecycle GREEN: the disposal regression and full controller suite passed after notification guarding.

## Final Verification

- `flutter analyze`
  - `No issues found!`
- `flutter test`
  - `85` tests passed.
- `flutter build web --release`
  - Release Web build succeeded.
- `cmp web/auth-callback.html build/web/auth-callback.html`
  - Passed; the callback page is present unchanged in the release artifact.
- `git diff --check`
  - Passed.

Flutter commands used a command-local `xcrun` output wrapper because Flutter 3.44's native-assets `otool` parser rejects parentheses in this required worktree path (`feat(auth)`). No Flutter SDK or repository source was modified by the workaround.

## Files

- `.superpowers/sdd/task-4-report.md`
- `apps/flutter_app/android/app/src/main/AndroidManifest.xml`
- `apps/flutter_app/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
- `apps/flutter_app/android/app/src/main/res/xml/backup_rules.xml`
- `apps/flutter_app/ios/Flutter/Debug.xcconfig`
- `apps/flutter_app/ios/Flutter/Release.xcconfig`
- `apps/flutter_app/ios/Podfile`
- `apps/flutter_app/lib/auth/auth_controller.dart`
- `apps/flutter_app/lib/auth/logto_auth_gateway.dart`
- `apps/flutter_app/lib/main.dart`
- `apps/flutter_app/macos/Flutter/Flutter-Debug.xcconfig`
- `apps/flutter_app/macos/Flutter/Flutter-Release.xcconfig`
- `apps/flutter_app/macos/Flutter/GeneratedPluginRegistrant.swift`
- `apps/flutter_app/macos/Podfile`
- `apps/flutter_app/pubspec.lock`
- `apps/flutter_app/pubspec.yaml`
- `apps/flutter_app/test/auth/auth_controller_test.dart`
- `apps/flutter_app/test/widget_test.dart`
- `apps/flutter_app/web/auth-callback.html`

## Self-Review

- Verified disabled configuration touches neither SDK session nor account API, and no provider/browser/network flow is opened by tests.
- Verified tokens and provider subjects are absent from controller state and visible errors; the UI displays only localized generic failure copy.
- Verified every rebuilt backend receives the controller's dynamic provider while static bearer/API-key fields remain available and const environment construction remains valid.
- Verified signed-out providers return null, restored sessions can refresh through Logto, and successful auth transitions refresh API panels without replacing or covering the map.
- Verified deletion sends exactly `delete-my-account`, cancellation sends nothing, deletion failure retains `/me`, and successful deletion remains guest even when hosted logout fails.
- Verified account controls use familiar Material icons and existing settings-section styling with no custom social buttons, marketing page, gradient, nested card, or provider artwork.
- Verified Android callback and backup configuration match the installed plugin contracts and the Web callback is copied into the release output.
- Verified no backend, `clients/flutter`, operations documentation, scripts, or unrelated `docs/superpowers` files are included.

## Concerns

- `logto_dart_sdk 3.0.0` requires `flutter_secure_storage 9.x`/`win32 5.x`, while `geolocator 14.0.3` pulls `package_info_plus 10.x`/`win32 6.x`. `geolocator` is therefore pinned to `14.0.2`, which preserves the app-facing API and resolves the dependency graph.
- Flutter reports that the installed secure-storage/web-auth plugins do not yet support Swift Package Manager; `pub get` generated CocoaPods Podfiles and xcconfig includes as the current supported fallback.
- The release Web build reports a WASM dry-run incompatibility from `flutter_secure_storage_web` (`dart:html`/`dart:js_util`). The requested JavaScript release build succeeds; WASM output is not enabled by this task.
