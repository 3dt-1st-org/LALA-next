// Wave-1 location/weather: recovery surface for a permanently-denied location.
//
// permanentlyDenied is an OS-level denial the system dialog cannot re-surface,
// so re-requesting is pointless. This card explains the permission is off in
// system settings, keeps the manual-region escape hatch prominent, and offers a
// REAL "Open settings" action ONLY where the platform supports it. On
// web/unsupported platforms the button is omitted and the copy honestly tells
// the user to change it in their browser/site settings — no fake action is ever
// shown. The flow stays usable because the manual path is always present.
import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// Calm, localized recovery card shown ONLY for a permanently-denied location.
///
/// [canOpenSettings] is sourced from the platform abstraction
/// (`canOpenAppSettings`); when false (web/unsupported) the "Open settings"
/// button is hidden and an honest browser-specific explanation is shown instead.
/// [onChooseArea] (manual region) is always offered so recovery never dead-ends.
class PermanentlyDeniedRecovery extends StatelessWidget {
  const PermanentlyDeniedRecovery({
    required this.language,
    required this.canOpenSettings,
    required this.onChooseArea,
    this.onOpenSettings,
    this.onRetry,
    super.key,
  });

  final String language;

  /// Whether the platform can hand off to the OS app settings page.
  final bool canOpenSettings;

  /// Manual-region escape hatch — always available and prominent.
  final VoidCallback onChooseArea;

  /// Real "Open settings" hand-off. Only invoked when [canOpenSettings] is true.
  final VoidCallback? onOpenSettings;

  /// Re-check location (e.g. after the user grants it in settings and returns).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // When the platform can't open settings, the manual path is the primary
    // recovery, so it takes the filled style; otherwise the settings hand-off
    // leads and the manual path is the prominent secondary.
    final chooseAreaIsPrimary = !canOpenSettings;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 440),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1ECF8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurRadius: 28,
            offset: Offset(0, 14),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.location_off_outlined,
                  color: Color(0xFF2B6CB0),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  lalaCopy(
                    language,
                    ko: '설정에서 위치가 꺼져 있어요',
                    en: 'Location is turned off in Settings',
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            canOpenSettings
                ? lalaCopy(
                    language,
                    ko: 'LALA의 위치 권한이 시스템 설정에서 꺼져 있어요. 설정을 열어 위치를 허용한 뒤 돌아와 다시 확인해 주세요. 또는 지역을 직접 선택할 수 있어요.',
                    en: "Location permission for LALA is disabled in system settings. Open Settings, allow location, then come back and retry — or choose an area below.",
                  )
                : lalaCopy(
                    language,
                    ko: '브라우저에서 위치를 차단했어요. 브라우저 사이트 설정에서 위치를 허용하거나, 아래에서 지역을 직접 선택할 수 있어요.',
                    en: "Your browser blocked location. Allow it in your browser's site settings, or choose an area below.",
                  ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF4B5563),
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (canOpenSettings && onOpenSettings != null) ...<Widget>[
            FilledButton.icon(
              key: const ValueKey('permanently-denied-open-settings'),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: Text(lalaCopy(language, ko: '설정 열기', en: 'Open settings')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (onRetry != null) ...<Widget>[
            OutlinedButton.icon(
              key: const ValueKey('permanently-denied-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.my_location_outlined),
              label: Text(lalaCopy(language, ko: '다시 확인', en: 'Retry')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: const Color(0xFF2B6CB0),
                side: const BorderSide(color: Color(0xFFB9D4F3)),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Manual-region escape hatch: always present and prominent. Filled when
          // it is the primary (web/unsupported) path, otherwise a strong outline.
          if (chooseAreaIsPrimary)
            FilledButton.icon(
              key: const ValueKey('permanently-denied-choose-area'),
              onPressed: onChooseArea,
              icon: const Icon(Icons.map_outlined),
              label: Text(
                lalaCopy(language, ko: '지역 직접 선택', en: 'Choose area'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF2B6CB0),
                foregroundColor: Colors.white,
              ),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('permanently-denied-choose-area'),
              onPressed: onChooseArea,
              icon: const Icon(Icons.map_outlined),
              label: Text(
                lalaCopy(language, ko: '지역 직접 선택', en: 'Choose area'),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: const Color(0xFF2B6CB0),
                side: BorderSide(
                  color: const Color(0xFF2B6CB0).withValues(alpha: 0.55),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
