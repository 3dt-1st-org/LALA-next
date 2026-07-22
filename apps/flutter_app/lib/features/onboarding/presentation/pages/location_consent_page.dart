// ONMU P2: 온보딩 4/4 — 위치 권한 요청.
// - "위치 권한 허용": locationProvider.requestCurrentLocation() 호출.
// - "나중에": 기본 위치(LalaAppConfig)로 스킵.
// - 거부/사용불가 시 "지역 직접 선택" 으로 ManualLocationSheet(기존 위젯) 옵션 노출.
// 완료 시 OnboardingState.markCompleted() → router redirect 가 /map-route 로 전환.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/location/widgets/manual_location_sheet.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:lala_next_app/manual_location_options.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class OnboardingLocationConsentPage extends StatefulWidget {
  const OnboardingLocationConsentPage({
    required this.locationProvider,
    super.key,
  });

  final LalaLocationProvider locationProvider;

  @override
  State<OnboardingLocationConsentPage> createState() =>
      _OnboardingLocationConsentPageState();
}

enum _LocationConsentStatus { idle, requesting }

class _OnboardingLocationConsentPageState
    extends State<OnboardingLocationConsentPage> {
  _LocationConsentStatus _status = _LocationConsentStatus.idle;
  bool _offeredManual = false;

  String get _language => OnboardingState.language;

  Future<void> _allowLocation() async {
    if (_status == _LocationConsentStatus.requesting) {
      return;
    }
    setState(() => _status = _LocationConsentStatus.requesting);
    try {
      final result = await widget.locationProvider.requestCurrentLocation();
      if (!mounted) {
        return;
      }
      if (result.status == LalaLocationResultStatus.found) {
        _complete();
        return;
      }
      // 거부/사용불가 → 수동 지역 선택 옵션 노출.
      setState(() {
        _status = _LocationConsentStatus.idle;
        _offeredManual = true;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _LocationConsentStatus.idle;
        _offeredManual = true;
      });
    }
  }

  Future<void> _openManualSheet() async {
    final selected = await showModalBottomSheet<ManualLocationOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualLocationSheet(language: _language),
    );
    if (selected != null && mounted) {
      _complete();
    }
  }

  void _complete() {
    OnboardingState.markCompleted();
    // markCompleted() 가 ValueNotifier 를 바꾸면 router refreshListenable 이 redirect
    // 를 재평가하여 /map-route 로 전환한다. (이동이 늦는 대비로 명시 이동도 안전.)
    if (mounted) {
      context.go(LalaRoutePaths.mapRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = _language;
    final requesting = _status == _LocationConsentStatus.requesting;
    return OnboardingScaffold(
      step: 4,
      onBack: requesting ? null : () => context.go(LalaRoutePaths.onboardingLanguage),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 12),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.my_location_rounded,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              lalaCopy(
                language,
                ko: '주변 추천을 위해 위치가 필요해요',
                en: 'We need your location for nearby tips',
              ),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.16,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              lalaCopy(
                language,
                ko: '현재 위치 주변의 명소·맛집·날씨를 추천해 드릴게요. 허용하지 않아도 기본 지역으로 시작할 수 있어요.',
                en:
                    'Get nearby attractions, food, and weather. You can still start with a default area.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const Spacer(),
            if (_offeredManual) ...<Widget>[
              _InfoBanner(
                language: language,
                text: lalaCopy(
                  language,
                  ko: '위치 권한이 없어요. 지역을 직접 선택하거나 기본 지역으로 시작할 수 있어요.',
                  en:
                      'Location is unavailable. Pick an area or start with the default.',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (requesting)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else
              _PrimaryButton(
                label: lalaCopy(language, ko: '위치 권한 허용', en: 'Allow location'),
                icon: Icons.location_on_rounded,
                onPressed: _allowLocation,
              ),
            const SizedBox(height: 12),
            if (_offeredManual)
              _SecondaryButton(
                label: lalaCopy(language, ko: '지역 직접 선택', en: 'Choose area'),
                onPressed: _openManualSheet,
              ),
            const SizedBox(height: 8),
            _TextActionButton(
              label: lalaCopy(
                language,
                ko: '나중에 하기',
                en: 'Not now',
              ),
              onPressed: requesting ? null : _complete,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: const Color(0xFF2B6CB0),
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: const Color(0xFF2B6CB0),
          side: const BorderSide(color: Color(0xFFB9D4F3)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _TextActionButton extends StatelessWidget {
  const _TextActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: const Color(0xFF64748B),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.language, required this.text});

  final String language;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF6E2B8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB7791F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF7B5E10),
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
