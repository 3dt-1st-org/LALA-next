import 'package:flutter/material.dart';

import '../../../auth/auth_controller.dart';
import '../../../shared/l10n/lala_copy.dart';
import 'account_settings_section.dart';
import 'privacy_details_sheet.dart';
import 'settings_section.dart';

/// 사용자 설정 시트(C3 추출 — main.dart 의 _UserSettingsSheet).
/// 계정 / 개인정보 / 위치 동의 / 언어 / 글꼴 / 앱 정보 섹션을 포함한다.
class UserSettingsSheet extends StatelessWidget {
  const UserSettingsSheet({
    super.key,
    required this.authController,
    required this.locationConsentEnabled,
    required this.uiLanguage,
    required this.fontScale,
    required this.onLocationConsentChanged,
    required this.onLanguageChanged,
    required this.onFontScaleChanged,
  });

  final LalaAuthController authController;
  final bool locationConsentEnabled;
  final String uiLanguage;
  final double fontScale;
  final ValueChanged<bool> onLocationConsentChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<double> onFontScaleChanged;

  @override
  Widget build(BuildContext context) {
    final title = lalaCopy(uiLanguage, ko: '설정', en: 'Settings');
    final closeLabel = lalaCopy(uiLanguage, ko: '닫기', en: 'Close');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1,
      minChildSize: 0.48,
      maxChildSize: 1,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [
              BoxShadow(
                blurRadius: 28,
                offset: Offset(0, -10),
                color: Color(0x26000000),
              ),
            ],
          ),
          child: ListView(
            key: const ValueKey('manual-location-scroll'),
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC8D0D9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: closeLabel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A202C),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 16),
              AccountSettingsSection(
                controller: authController,
                language: uiLanguage,
              ),
              SettingsSection(
                title: lalaCopy(
                  uiLanguage,
                  ko: '개인정보 동의 안내',
                  en: 'Privacy notice',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lalaCopy(
                        uiLanguage,
                        ko: '서비스 품질 향상을 위해 최소한의 이용 정보와 위치 기반 추천 정보가 사용됩니다.',
                        en: 'LALA uses minimal usage and location signals to improve recommendations.',
                      ),
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        height: 1.38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          showPrivacyDetailsSheet(context, uiLanguage),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: const Color(0xFF2B6CB0),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      child: Text(
                        lalaCopy(uiLanguage, ko: '자세히 보기', en: 'Learn more'),
                      ),
                    ),
                  ],
                ),
              ),
              SettingsSection(
                title: lalaCopy(
                  uiLanguage,
                  ko: '위치기반 정보 제공 동의',
                  en: 'Location recommendations',
                ),
                trailing: Switch(
                  value: locationConsentEnabled,
                  onChanged: onLocationConsentChanged,
                ),
              ),
              SettingsSection(
                title: lalaCopy(uiLanguage, ko: '언어', en: 'Language'),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'ko',
                      label: Text(languageOptionLabel('ko', uiLanguage)),
                    ),
                    ButtonSegment(
                      value: 'en',
                      label: Text(languageOptionLabel('en', uiLanguage)),
                    ),
                  ],
                  selected: {uiLanguage},
                  onSelectionChanged: (values) =>
                      onLanguageChanged(values.first),
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.white,
                    selectedBackgroundColor: const Color(0xFF2B6CB0),
                    selectedForegroundColor: Colors.white,
                  ),
                ),
              ),
              SettingsSection(
                title: lalaCopy(uiLanguage, ko: '글꼴 크기', en: 'Font size'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Slider(
                      value: fontScale,
                      min: 0.9,
                      max: 1.18,
                      divisions: 7,
                      label: 'x${fontScale.toStringAsFixed(2)}',
                      onChanged: onFontScaleChanged,
                    ),
                    Text(
                      'x${fontScale.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              SettingsSection(
                title: lalaCopy(uiLanguage, ko: '앱 정보', en: 'App info'),
                child: MetricRow(
                  label: lalaCopy(uiLanguage, ko: '버전', en: 'Version'),
                  value: '1.0',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 언어 옵션 라벨(C3 추출 — main.dart 의 _languageOptionLabel).
/// 설정 시트에서만 사용되는 feature 전용 헬퍼.
String languageOptionLabel(String optionLanguage, String uiLanguage) {
  if (isLalaEnglish(uiLanguage)) {
    return optionLanguage == 'en' ? 'English' : 'Korean';
  }
  return optionLanguage == 'en' ? '영어' : '한국어';
}

/// 앱 정보 표시용 라벨/값 행(C3 추출 — main.dart 의 _MetricRow).
/// 설정 시트의 '앱 정보' 섹션에서만 사용된다.
class MetricRow extends StatelessWidget {
  const MetricRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
