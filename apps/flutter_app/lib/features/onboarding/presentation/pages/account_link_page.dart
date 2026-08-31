import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// Optional account link after the three onboarding choices.
///
/// This page is deliberately not a fourth required onboarding step. Guests can
/// always enter the app, while a configured Logto build can establish one
/// root-owned session before the main shell is created.
class OnboardingAccountLinkPage extends StatefulWidget {
  const OnboardingAccountLinkPage({required this.authController, super.key});

  final LalaAuthController authController;

  @override
  State<OnboardingAccountLinkPage> createState() =>
      _OnboardingAccountLinkPageState();
}

class _OnboardingAccountLinkPageState extends State<OnboardingAccountLinkPage> {
  bool _signingIn = false;
  bool _finishing = false;

  String get _language => OnboardingState.language;

  Future<void> _finishOnboarding() async {
    if (_finishing) {
      return;
    }
    setState(() => _finishing = true);
    await OnboardingState.completeAndFlush();
    if (mounted) {
      context.go(LalaRoutePaths.mapRoute);
    }
  }

  Future<void> _signIn() async {
    if (_signingIn || _finishing) {
      return;
    }
    setState(() => _signingIn = true);
    await widget.authController.signIn();
    if (!mounted) {
      return;
    }
    setState(() => _signingIn = false);
    final state = widget.authController.state;
    if (state.authenticated &&
        state.accountSyncStatus == LalaAccountSyncStatus.ready) {
      await _finishOnboarding();
    }
  }

  Future<void> _retryAccountSync() async {
    if (_signingIn || _finishing) {
      return;
    }
    setState(() => _signingIn = true);
    await widget.authController.retryAccountSync();
    if (!mounted) {
      return;
    }
    setState(() => _signingIn = false);
    if (widget.authController.state.accountSyncStatus ==
        LalaAccountSyncStatus.ready) {
      await _finishOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 3,
      showProgress: false,
      child: AnimatedBuilder(
        animation: widget.authController,
        builder: (BuildContext context, Widget? _) {
          final state = widget.authController.state;
          final waiting = _signingIn || _finishing;
          final accountReady =
              state.authenticated &&
              state.accountSyncStatus == LalaAccountSyncStatus.ready;
          final accountSyncFailed =
              state.authenticated &&
              state.accountSyncStatus == LalaAccountSyncStatus.error;

          return Padding(
            padding: const EdgeInsets.fromLTRB(
              LalaVisualTokens.pageGutter,
              32,
              LalaVisualTokens.pageGutter,
              LalaVisualTokens.sectionGap + 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: LalaVisualColors.primarySoft,
                            borderRadius: BorderRadius.circular(
                              LalaVisualTokens.controlRadius,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_outline_rounded,
                            color: LalaVisualColors.primaryBlue,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _copy(
                            ko: '여행을 계정과\n연결할까요?',
                            en: 'Connect your trip\nto an account?',
                            ja: '旅をアカウントに\nつなげますか？',
                            zhHans: '要将旅程关联到\n您的账户吗？',
                            zhHant: '要將旅程連結到\n您的帳戶嗎？',
                          ),
                          style: const TextStyle(
                            fontSize: LalaVisualTokens.onboardingTitleSize,
                            height:
                                LalaVisualTokens.onboardingTitleLineHeight /
                                LalaVisualTokens.onboardingTitleSize,
                            fontWeight: FontWeight.w800,
                            color: LalaVisualColors.ink,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _copy(
                            ko: '로그인하면 커뮤니티와 계정이 필요한 기능을 이어서 사용할 수 있어요. 지도·검색·일정은 로그인 없이도 둘러볼 수 있어요.',
                            en: 'Sign in for community and account features. Maps, search, and plans remain available without an account.',
                            ja: 'ログインするとコミュニティやアカウント機能を利用できます。地図・検索・日程はログインなしでも使えます。',
                            zhHans: '登录后可使用社区和账户功能。无需登录也能继续使用地图、搜索和行程。',
                            zhHant: '登入後可使用社群和帳戶功能。無需登入也能繼續使用地圖、搜尋和行程。',
                          ),
                          style: const TextStyle(
                            fontSize: LalaVisualTokens.bodySize,
                            height:
                                LalaVisualTokens.bodyLineHeight /
                                LalaVisualTokens.bodySize,
                            fontWeight: FontWeight.w500,
                            color: LalaVisualColors.muted,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (state.authenticated)
                          _ConnectedAccountSummary(state: state),
                        if (accountSyncFailed) ...<Widget>[
                          const SizedBox(height: 12),
                          _StatusMessage(
                            icon: Icons.sync_problem_rounded,
                            message: _copy(
                              ko: '로그인은 완료됐지만 LALA 계정 연결을 마치지 못했어요. 다시 시도하거나 앱으로 계속할 수 있어요.',
                              en: 'Sign-in succeeded, but LALA account sync did not. Retry or continue to the app.',
                              ja: 'ログインは完了しましたが、LALAアカウントとの連携に失敗しました。再試行するか、そのまま進めます。',
                              zhHans: '登录已完成，但未能同步 LALA 账户。您可以重试或继续使用应用。',
                              zhHant: '登入已完成，但未能同步 LALA 帳戶。您可以重試或繼續使用應用程式。',
                            ),
                          ),
                        ] else if (state.status ==
                            LalaAuthStatus.error) ...<Widget>[
                          const SizedBox(height: 12),
                          _StatusMessage(
                            icon: Icons.info_outline_rounded,
                            message: _copy(
                              ko: '로그인을 완료하지 못했어요. 다시 시도하거나 게스트로 계속할 수 있어요.',
                              en: 'We could not complete sign-in. Try again or continue as a guest.',
                              ja: 'ログインを完了できませんでした。再試行するか、ゲストとして進めます。',
                              zhHans: '未能完成登录。您可以重试或以访客身份继续。',
                              zhHant: '未能完成登入。您可以重試或以訪客身分繼續。',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (waiting || state.status == LalaAuthStatus.busy) ...<Widget>[
                  const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('onboarding-account-primary'),
                    onPressed: waiting || state.status == LalaAuthStatus.busy
                        ? null
                        : accountReady
                        ? () => unawaited(_finishOnboarding())
                        : accountSyncFailed
                        ? () => unawaited(_retryAccountSync())
                        : () => unawaited(_signIn()),
                    icon: Icon(
                      accountReady
                          ? Icons.arrow_forward_rounded
                          : accountSyncFailed
                          ? Icons.refresh_rounded
                          : Icons.login_rounded,
                    ),
                    label: Text(
                      accountReady
                          ? _copy(
                              ko: 'LALA 시작하기',
                              en: 'Start LALA',
                              ja: 'LALAを始める',
                              zhHans: '开始使用 LALA',
                              zhHant: '開始使用 LALA',
                            )
                          : accountSyncFailed
                          ? _copy(
                              ko: '계정 연결 다시 시도',
                              en: 'Retry account sync',
                              ja: 'アカウント連携を再試行',
                              zhHans: '重试账户同步',
                              zhHant: '重試帳戶同步',
                            )
                          : _copy(
                              ko: '로그인',
                              en: 'Sign in',
                              ja: 'ログイン',
                              zhHans: '登录',
                              zhHant: '登入',
                            ),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        LalaVisualTokens.actionHeight,
                      ),
                      backgroundColor: LalaVisualColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          LalaVisualTokens.controlRadius,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('onboarding-account-skip'),
                  onPressed: waiting
                      ? null
                      : () => unawaited(_finishOnboarding()),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: LalaVisualColors.muted,
                  ),
                  child: Text(
                    state.authenticated
                        ? _copy(
                            ko: '앱으로 계속',
                            en: 'Continue to the app',
                            ja: 'アプリへ進む',
                            zhHans: '继续使用应用',
                            zhHant: '繼續使用應用程式',
                          )
                        : _copy(
                            ko: '게스트로 둘러보기',
                            en: 'Continue as guest',
                            ja: 'ゲストとして続ける',
                            zhHans: '以访客身份继续',
                            zhHant: '以訪客身分繼續',
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _copy({
    required String ko,
    required String en,
    required String ja,
    required String zhHans,
    required String zhHant,
  }) {
    return lalaCopyMulti(
      _language,
      ko: ko,
      en: en,
      ja: ja,
      zhHans: zhHans,
      zhHant: zhHant,
    );
  }
}

class _ConnectedAccountSummary extends StatelessWidget {
  const _ConnectedAccountSummary({required this.state});

  final LalaAuthState state;

  @override
  Widget build(BuildContext context) {
    final profile = state.profile;
    final title = profile?.name ?? profile?.email ?? 'LALA account';
    final subtitle = profile?.name == null ? null : profile?.email;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LalaVisualColors.card,
        border: Border.all(color: LalaVisualColors.line),
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.check_circle_outline_rounded,
            color: LalaVisualColors.culture,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: LalaVisualColors.ink,
                    fontSize: LalaVisualTokens.controlLabelSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LalaVisualColors.muted,
                      fontSize: LalaVisualTokens.chipSize,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 20, color: LalaVisualColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: LalaVisualColors.muted,
              fontSize: LalaVisualTokens.chipSize,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}
