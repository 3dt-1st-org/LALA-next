import 'package:flutter/material.dart';

import '../../../auth/auth_controller.dart';
import '../../../shared/l10n/lala_copy.dart';

enum LocalSignalAuthOutcome {
  alreadyAuthenticated,
  signedInNow,
  cancelled,
  unavailable,
  failed,
  busy,
}

/// Requests a real Logto session without executing the protected write.
///
/// A newly authenticated user explicitly taps the write action again. This
/// keeps draft text intact and prevents a signal from being created as an
/// implicit OAuth-callback side effect (same contract as the community guard).
Future<LocalSignalAuthOutcome> requestLocalSignalAuthentication(
  BuildContext context, {
  required LalaAuthController? controller,
  required String language,
  required String actionLabel,
}) async {
  if (controller?.state.authenticated ?? false) {
    return LocalSignalAuthOutcome.alreadyAuthenticated;
  }
  if (controller == null || !controller.config.enabled) {
    _showMessage(
      context,
      _copy(
        language,
        ko: '이 빌드에서는 계정 연결을 사용할 수 없어요. 로컬 신호 읽기는 계속할 수 있어요.',
        en: 'Account linking is unavailable in this build. Local Signals reading still works.',
        ja: 'このビルドではアカウント連携を利用できません。ローカル信号の閲覧は引き続き可能です。',
        zhHans: '此版本无法连接账号，但仍可阅读本地信号。',
        zhHant: '此版本無法連結帳號，但仍可閱讀在地訊號。',
      ),
    );
    return LocalSignalAuthOutcome.unavailable;
  }
  if (controller.state.status == LalaAuthStatus.busy) {
    _showMessage(
      context,
      _copy(
        language,
        ko: '계정 상태를 확인하고 있어요. 잠시 후 다시 시도해 주세요.',
        en: 'Checking your account. Please try again shortly.',
        ja: 'アカウントを確認しています。しばらくしてからもう一度お試しください。',
        zhHans: '正在检查账号，请稍后重试。',
        zhHant: '正在檢查帳號，請稍後重試。',
      ),
    );
    return LocalSignalAuthOutcome.busy;
  }

  final shouldSignIn = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        _copy(
          language,
          ko: '로그인이 필요해요',
          en: 'Sign in required',
          ja: 'ログインが必要です',
          zhHans: '需要登录',
          zhHant: '需要登入',
        ),
      ),
      content: Text(
        _copy(
          language,
          ko: '$actionLabel 기능은 로그인 후 사용할 수 있어요. 작성 중인 내용은 이 화면에 그대로 남습니다.',
          en: 'Sign in to use $actionLabel. Anything you have typed stays on this screen.',
          ja: '$actionLabelを利用するにはログインしてください。入力中の内容はこの画面に残ります。',
          zhHans: '登录后可使用“$actionLabel”。已输入的内容会保留在此页面。',
          zhHant: '登入後可使用「$actionLabel」。已輸入的內容會保留在此頁面。',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            _copy(
              language,
              ko: '나중에',
              en: 'Not now',
              ja: '後で',
              zhHans: '稍后',
              zhHant: '稍後',
            ),
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('local-signal-auth-sign-in'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.login_rounded),
          label: Text(
            _copy(
              language,
              ko: '로그인',
              en: 'Sign in',
              ja: 'ログイン',
              zhHans: '登录',
              zhHant: '登入',
            ),
          ),
        ),
      ],
    ),
  );
  if (shouldSignIn != true || !context.mounted) {
    return LocalSignalAuthOutcome.cancelled;
  }

  await controller.signIn();
  if (!context.mounted) return LocalSignalAuthOutcome.cancelled;
  if (controller.state.authenticated) {
    _showMessage(
      context,
      _copy(
        language,
        ko: '계정이 연결됐어요. 내용을 확인한 뒤 작업을 한 번 더 눌러 주세요.',
        en: 'Account connected. Review your content, then tap the action again.',
        ja: 'アカウントを連携しました。内容を確認して、もう一度操作してください。',
        zhHans: '账号已连接。请确认内容后再次操作。',
        zhHant: '帳號已連結。請確認內容後再次操作。',
      ),
    );
    return LocalSignalAuthOutcome.signedInNow;
  }

  _showMessage(
    context,
    _copy(
      language,
      ko: '로그인을 완료하지 못했어요. 작성 중인 내용은 유지됐습니다.',
      en: 'Sign-in was not completed. Your draft is still here.',
      ja: 'ログインを完了できませんでした。入力内容は保持されています。',
      zhHans: '登录未完成，已保留输入内容。',
      zhHant: '登入未完成，已保留輸入內容。',
    ),
  );
  return LocalSignalAuthOutcome.failed;
}

/// Honest sign-in-required view for the contribute flow. The button performs a
/// real Logto sign-in; when account linking is disabled or absent in this
/// build it is disabled rather than pretending a session exists.
class LocalSignalAuthenticationView extends StatelessWidget {
  const LocalSignalAuthenticationView({
    super.key,
    required this.language,
    required this.controller,
    required this.onAuthenticated,
  });

  final String language;
  final LalaAuthController? controller;
  final VoidCallback onAuthenticated;

  Future<void> _signIn(BuildContext context) async {
    final outcome = await requestLocalSignalAuthentication(
      context,
      controller: controller,
      language: language,
      actionLabel: _copy(
        language,
        ko: '경험 공유',
        en: 'sharing a Local Signal',
        ja: '体験の共有',
        zhHans: '分享体验',
        zhHant: '分享體驗',
      ),
    );
    if (!context.mounted) return;
    if (outcome == LocalSignalAuthOutcome.alreadyAuthenticated ||
        outcome == LocalSignalAuthOutcome.signedInNow) {
      onAuthenticated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.lock_person_outlined,
              size: 44,
              color: Color(0xFF2B6CB0),
            ),
            const SizedBox(height: 14),
            Text(
              _copy(
                language,
                ko: '로그인하고 로컬 신호를 남겨 주세요',
                en: 'Sign in to share a Local Signal',
                ja: 'ログインしてローカル信号を投稿',
                zhHans: '登录后分享本地信号',
                zhHant: '登入後分享在地訊號',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _copy(
                language,
                ko: '로컬 신호 읽기는 로그인 없이 가능하지만, 경험 작성은 검수와 소유권 보호를 위해 로그인이 필요해요. 초안은 비공개로 저장되고 검수 승인 뒤에만 공개됩니다.',
                en: 'Reading Local Signals needs no account. Writing one requires sign-in for review and ownership. Drafts stay private and publish only after review.',
                ja: 'ローカル信号の閲覧にはアカウント不要ですが、審査と所有権の保護のため投稿にはログインが必要です。下書きは非公開で保存され、審査承認後にのみ公開されます。',
                zhHans: '阅读本地信号无需账号；为保障审核与所有权，撰写体验需要登录。草稿保持私密，仅在审核通过后公开。',
                zhHant: '閱讀在地訊號無需帳號；為保障審核與所有權，撰寫體驗需要登入。草稿維持私密，僅在審核通過後公開。',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('local-signal-auth-connect'),
              onPressed: controller == null || !controller!.config.enabled
                  ? null
                  : () => _signIn(context),
              icon: const Icon(Icons.login_rounded),
              label: Text(
                _copy(
                  language,
                  ko: '계정 연결',
                  en: 'Connect account',
                  ja: 'アカウントを連携',
                  zhHans: '连接账号',
                  zhHant: '連結帳號',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

String _copy(
  String language, {
  required String ko,
  required String en,
  required String ja,
  required String zhHans,
  required String zhHant,
}) => lalaCopyMulti(
  language,
  ko: ko,
  en: en,
  ja: ja,
  zhHans: zhHans,
  zhHant: zhHant,
);
