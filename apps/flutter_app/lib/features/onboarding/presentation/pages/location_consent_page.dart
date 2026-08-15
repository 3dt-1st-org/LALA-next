// 모바일 비주얼 계약 S3: 위치 동의.
// - 상단 읽기 전용 카카오맵 미리보기(라이브 키 경계 재사용, 제스처/콜백 차단).
// - "현재 위치 사용"(요청 중에만 비활성), "지역 직접 선택"(항상 노출), "나중에 하기".
// 수동 지역 선택은 권한 실패 뒤에만 나타나지 않고 첫 렌더부터 항상 사용 가능하다(01-flow §F1.5).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/app_settings_opener.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/location/widgets/manual_location_sheet.dart';
import 'package:lala_next_app/features/location/widgets/permanently_denied_recovery.dart';
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
  static const Duration _unavailableRetryDelay = Duration(milliseconds: 500);

  _LocationConsentStatus _status = _LocationConsentStatus.idle;
  // OS 영구 거결(permanentlyDenied) 전용 복구 카드 노출 여부. 시스템 다이얼로그 재노출이
  // 불가하므로 일반 denied 와 구분해 설정 유도 + 수동 선택 경로를 안내한다.
  bool _permanentlyDenied = false;

  // 미리보기 중심/키는 기본 지역(SSOT 기본값)을 따른다. 좌표가 확정되기 전이다.
  late final LalaAppConfig _config = LalaAppConfig.fromEnvironment();

  String get _language => OnboardingState.language;

  bool get _requesting => _status == _LocationConsentStatus.requesting;

  Future<LalaLocationResult> _requestLocationWithResumeRecovery() async {
    final firstResult = await widget.locationProvider.requestCurrentLocation();
    if (firstResult.status != LalaLocationResultStatus.unavailable) {
      return firstResult;
    }

    // Android may report an unavailable position while the app is resuming from
    // the just-approved system permission dialog. Retry this transient result
    // once so the user does not have to press "Use location" a second time.
    await Future<void>.delayed(_unavailableRetryDelay);
    if (!mounted) {
      return firstResult;
    }
    return widget.locationProvider.requestCurrentLocation();
  }

  Future<void> _allowLocation() async {
    if (_requesting) {
      return;
    }
    setState(() {
      _status = _LocationConsentStatus.requesting;
      _permanentlyDenied = false;
    });
    try {
      final result = await _requestLocationWithResumeRecovery();
      if (!mounted) {
        return;
      }
      if (result.status == LalaLocationResultStatus.found &&
          result.location != null) {
        // Retain the resolved location into the app shell so the search/plan/map
        // tabs drive place + weather calls from it instead of the default region.
        // Why: await the durable clear of any prior manual id before completion, so
        // a kill right after this tap cannot leave a stale manual selection durable.
        await RegionContextStore.setAndFlush(
          RegionContext.current(
            lat: result.location!.lat,
            lng: result.location!.lng,
          ),
        );
        await _complete();
        return;
      }
      if (result.status == LalaLocationResultStatus.permanentlyDenied) {
        // OS 영구 거절: 시스템 다이얼로그 재노출 불가 → 전용 복구 카드로 설정 유도.
        setState(() {
          _status = _LocationConsentStatus.idle;
          _permanentlyDenied = true;
        });
        return;
      }
      // denied / unavailable: 수동 선택은 항상 노출되므로 별도 배너 없이 대기 상태로 복귀.
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
      // 수동 선택도 앱 쉘로 이관한다(기존에는 폐기됨).
      // Why: await the manual-id write before completion so a kill right after the
      // tap cannot lose the region the user just chose.
      await RegionContextStore.setAndFlush(RegionContext.manual(selected));
      await _complete();
    }
  }

  Future<void> _complete() async {
    // Why: callers already durably flushed the region choice via setAndFlush, so
    // only the completion slice remains. completeAndFlush awaits that write and
    // flips the router's completion gate only afterwards; storage failure still
    // completes so the user is never stranded. A kill after navigation can't lose
    // either slice — region durable → completion durable → gate flip → navigate.
    await OnboardingState.completeAndFlush();
    // completeAndFlush() 가 ValueNotifier 를 바꾸면 router refreshListenable 이
    // redirect 를 재평가하여 /map-route 로 전환한다. (이동이 늦는 대비로 명시 이동도 안전.)
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
                        lalaCopyMulti(
                          language,
                          ko: '내 주변을\n추천해 드릴게요',
                          en: 'We\'ll recommend\nwhat\'s nearby',
                          ja: '近くのスポットを\nご案内します',
                          zhHans: '为您推荐\n附近的去处',
                          zhHant: '為您推薦\n附近的去處',
                        ),
                        style: TextStyle(
                          fontSize: LalaVisualTokens.onboardingTitleSize,
                          height:
                              LalaVisualTokens.onboardingTitleLineHeight /
                              LalaVisualTokens.onboardingTitleSize,
                          fontWeight: FontWeight.w800,
                          color: LalaVisualColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      lalaCopyMulti(
                        language,
                        ko: '현재 위치를 사용하면 가까운 명소·맛집·행사 등\n맞춤 추천을 받을 수 있어요.\n\n위치 정보는 동의 없이 저장되지 않으며,\n언제든지 변경할 수 있어요.',
                        en: 'Use your current location for nearby attractions,\nfood, and events.\n\nLocation is never stored without consent,\nand you can change it anytime.',
                        ja: '現在地を使って、近くの名所・グルメ・イベントなど\nおすすめをご案内します。\n\n位置情報は同意なしに保存されず、\nいつでも変更できます。',
                        zhHans: '使用当前位置，探索附近的景点、美食和活动。\n\n未经同意不会存储位置信息，\n您可以随时更改。',
                        zhHant: '使用當前位置，探索附近的景點、美食和活動。\n\n未經同意不會儲存位置資訊，\n您可以隨時更改。',
                      ),
                      style: TextStyle(
                        fontSize: LalaVisualTokens.bodySize,
                        height:
                            LalaVisualTokens.bodyLineHeight /
                            LalaVisualTokens.bodySize,
                        fontWeight: FontWeight.w500,
                        color: LalaVisualColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_permanentlyDenied) ...<Widget>[
              // OS 영구 거절 복구: 설정 유도(지원되는 플랫폼만) + 수동 선택 + 재시도.
              PermanentlyDeniedRecovery(
                language: language,
                canOpenSettings: canOpenAppSettings,
                onOpenSettings: () => openAppSettings(),
                onRetry: _allowLocation,
                onChooseArea: _openManualSheet,
              ),
              const SizedBox(height: 8),
              _TextActionButton(
                label: lalaCopyMulti(
                  language,
                  ko: '나중에 하기',
                  en: 'Not now',
                  ja: 'あとで',
                  zhHans: '暂不',
                  zhHant: '暫不',
                ),
                onPressed: () => unawaited(_complete()),
              ),
            ] else if (_requesting)
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
            else ...<Widget>[
              _PrimaryButton(
                label: lalaCopyMulti(
                  language,
                  ko: '현재 위치 사용',
                  en: 'Use location',
                  ja: '現在地を使う',
                  zhHans: '使用当前位置',
                  zhHant: '使用當前位置',
                ),
                onPressed: _allowLocation,
              ),
              const SizedBox(height: LalaVisualTokens.contentGap),
              _SecondaryButton(
                label: lalaCopyMulti(
                  language,
                  ko: '지역 직접 선택',
                  en: 'Choose area',
                  ja: '地域を選ぶ',
                  zhHans: '选择地区',
                  zhHant: '選擇地區',
                ),
                // 권한 결과와 무관하게 항상 노출/사용 가능.
                onPressed: _requesting ? null : _openManualSheet,
              ),
              const SizedBox(height: 8),
              _TextActionButton(
                label: lalaCopyMulti(
                  language,
                  ko: '나중에 하기',
                  en: 'Not now',
                  ja: 'あとで',
                  zhHans: '暂不',
                  zhHant: '暫不',
                ),
                onPressed: _requesting ? null : () => unawaited(_complete()),
              ),
            ],
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
            height:
                LalaVisualTokens.controlLabelLineHeight /
                LalaVisualTokens.controlLabelSize,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
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
          side: BorderSide(
            color: LalaVisualColors.primaryBlue.withValues(alpha: 0.4),
          ),
          textStyle: TextStyle(
            fontSize: LalaVisualTokens.controlLabelSize,
            height:
                LalaVisualTokens.controlLabelLineHeight /
                LalaVisualTokens.controlLabelSize,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
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
