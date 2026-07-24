// 모바일 비주얼 계약 S3: 위치 동의.
// - 상단 읽기 전용 카카오맵 미리보기(라이브 키 경계 재사용, 제스처/콜백 차단).
// - "현재 위치 사용"(요청 중에만 비활성), "지역 직접 선택"(항상 노출), "나중에 하기".
// 수동 지역 선택은 권한 실패 뒤에만 나타나지 않고 첫 렌더부터 항상 사용 가능하다(01-flow §F1.5).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/location/widgets/manual_location_sheet.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/widgets/location_map_preview.dart';
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

  // 미리보기 중심/키는 기본 지역(SSOT 기본값)을 따른다. 좌표가 확정되기 전이다.
  late final LalaAppConfig _config = LalaAppConfig.fromEnvironment();

  String get _language => OnboardingState.language;

  bool get _requesting => _status == _LocationConsentStatus.requesting;

  Future<void> _allowLocation() async {
    if (_requesting) {
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
      // 거부/사용불가: 수동 선택은 항상 노출되므로 별도 배너 없이 대기 상태로 복귀.
      setState(() => _status = _LocationConsentStatus.idle);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _status = _LocationConsentStatus.idle);
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
    return OnboardingScaffold(
      step: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LalaVisualTokens.pageGutter,
          0,
          LalaVisualTokens.pageGutter,
          LalaVisualTokens.sectionGap + 12,
        ),
        // 미리보기 + 안내문은 스크롤, 세 개의 액션은 하단에 항상 노출 → 어떤 높이에서도
        // 오버플로우 없이 액션이 닿는다(00-ground-truth §5).
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 읽기 전용 라이브 미리보기. 좌표가 없으므로 핀은 없다.
                    LocationMapPreview(
                      kakaoJavascriptKey: _config.kakaoJavascriptKey,
                      centerLat: _config.lat,
                      centerLng: _config.lng,
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 272),
                      child: Text(
                        lalaCopy(
                          language,
                          ko: '내 주변을\n추천해 드릴게요',
                          en: 'We\'ll recommend\nwhat\'s nearby',
                        ),
                        style: TextStyle(
                          fontSize: LalaVisualTokens.onboardingTitleSize,
                          height: LalaVisualTokens.onboardingTitleLineHeight /
                              LalaVisualTokens.onboardingTitleSize,
                          fontWeight: FontWeight.w800,
                          color: LalaVisualColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      lalaCopy(
                        language,
                        ko: '현재 위치를 사용하면 가까운 명소·맛집·행사 등\n맞춤 추천을 받을 수 있어요.\n\n위치 정보는 동의 없이 저장되지 않으며,\n언제든지 변경할 수 있어요.',
                        en: 'Use your current location for nearby attractions,\nfood, and events.\n\nLocation is never stored without consent,\nand you can change it anytime.',
                      ),
                      style: TextStyle(
                        fontSize: LalaVisualTokens.bodySize,
                        height: LalaVisualTokens.bodyLineHeight /
                            LalaVisualTokens.bodySize,
                        fontWeight: FontWeight.w500,
                        color: LalaVisualColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_requesting)
              const Padding(
                padding: EdgeInsets.only(top: 12),
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
                label: lalaCopy(language, ko: '현재 위치 사용', en: 'Use location'),
                onPressed: _allowLocation,
              ),
            const SizedBox(height: LalaVisualTokens.contentGap),
            _SecondaryButton(
              label: lalaCopy(language, ko: '지역 직접 선택', en: 'Choose area'),
              // 권한 결과와 무관하게 항상 노출/사용 가능.
              onPressed: _requesting ? null : _openManualSheet,
            ),
            const SizedBox(height: 8),
            _TextActionButton(
              label: lalaCopy(language, ko: '나중에 하기', en: 'Not now'),
              onPressed: _requesting ? null : _complete,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(LalaVisualTokens.actionHeight),
          backgroundColor: LalaVisualColors.primaryBlue,
          foregroundColor: LalaVisualColors.card,
          textStyle: TextStyle(
            fontSize: LalaVisualTokens.controlLabelSize,
            height: LalaVisualTokens.controlLabelLineHeight /
                LalaVisualTokens.controlLabelSize,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              LalaVisualTokens.controlRadius,
            ),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: LalaVisualColors.primaryBlue,
          side: BorderSide(color: LalaVisualColors.primaryBlue.withValues(alpha: 0.4)),
          textStyle: TextStyle(
            fontSize: LalaVisualTokens.controlLabelSize,
            height: LalaVisualTokens.controlLabelLineHeight /
                LalaVisualTokens.controlLabelSize,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              LalaVisualTokens.controlRadius,
            ),
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
          foregroundColor: LalaVisualColors.muted,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}
