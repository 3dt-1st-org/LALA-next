import 'package:flutter/material.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

enum CommunityAuthOutcome {
  alreadyAuthenticated,
  signedInNow,
  cancelled,
  unavailable,
  failed,
  busy,
}

bool isCommunityAuthenticated(LalaAuthController? controller) =>
    controller?.state.authenticated ?? false;

/// Requests a real Logto session without executing the protected action.
///
/// A newly authenticated user explicitly taps the write action again. This
/// keeps drafts intact and prevents a post, reaction, room, or message from
/// being submitted as an implicit OAuth callback side effect.
Future<CommunityAuthOutcome> requestCommunityAuthentication(
  BuildContext context, {
  required LalaAuthController? controller,
  required String language,
  required String actionLabel,
}) async {
  if (controller?.state.authenticated ?? false) {
    return CommunityAuthOutcome.alreadyAuthenticated;
  }
  if (controller == null || !controller.config.enabled) {
    _showMessage(
      context,
      lalaCopyMulti(
        language,
        ko: '이 빌드에서는 계정 연결을 사용할 수 없어요. 커뮤니티 글은 계속 읽을 수 있어요.',
        en: 'Account linking is unavailable in this build. You can still read community posts.',
        ja: 'このビルドではアカウント連携を利用できません。コミュニティ投稿は引き続き読めます。',
        zhHans: '此版本无法连接账号，但仍可阅读社区帖子。',
        zhHant: '此版本無法連結帳號，但仍可閱讀社群貼文。',
      ),
    );
    return CommunityAuthOutcome.unavailable;
  }
  if (controller.state.status == LalaAuthStatus.busy) {
    _showMessage(
      context,
      lalaCopyMulti(
        language,
        ko: '계정 상태를 확인하고 있어요. 잠시 후 다시 시도해 주세요.',
        en: 'Checking your account. Please try again shortly.',
        ja: 'アカウントを確認しています。しばらくしてからもう一度お試しください。',
        zhHans: '正在检查账号，请稍后重试。',
        zhHant: '正在檢查帳號，請稍後重試。',
      ),
    );
    return CommunityAuthOutcome.busy;
  }

  final shouldSignIn = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        lalaCopyMulti(
          language,
          ko: '로그인이 필요해요',
          en: 'Sign in required',
          ja: 'ログインが必要です',
          zhHans: '需要登录',
          zhHant: '需要登入',
        ),
      ),
      content: Text(
        lalaCopyMulti(
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
            lalaCopyMulti(
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
          key: const ValueKey('community-sign-in-action'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.login_rounded),
          label: Text(
            lalaCopyMulti(
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
    return CommunityAuthOutcome.cancelled;
  }

  await controller.signIn();
  if (!context.mounted) return CommunityAuthOutcome.cancelled;
  if (controller.state.authenticated) {
    _showMessage(
      context,
      lalaCopyMulti(
        language,
        ko: '계정이 연결됐어요. 내용을 확인한 뒤 작업을 한 번 더 눌러 주세요.',
        en: 'Account connected. Review your content, then tap the action again.',
        ja: 'アカウントを連携しました。内容を確認して、もう一度操作してください。',
        zhHans: '账号已连接。请确认内容后再次操作。',
        zhHant: '帳號已連結。請確認內容後再次操作。',
      ),
    );
    return CommunityAuthOutcome.signedInNow;
  }

  _showMessage(
    context,
    lalaCopyMulti(
      language,
      ko: '로그인을 완료하지 못했어요. 작성 중인 내용은 유지됐습니다.',
      en: 'Sign-in was not completed. Your draft is still here.',
      ja: 'ログインを完了できませんでした。入力内容は保持されています。',
      zhHans: '登录未完成，已保留输入内容。',
      zhHant: '登入未完成，已保留輸入內容。',
    ),
  );
  return CommunityAuthOutcome.failed;
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

class CommunityAuthenticationView extends StatelessWidget {
  const CommunityAuthenticationView({
    super.key,
    required this.language,
    required this.controller,
    required this.onAuthenticated,
    required this.purpose,
  });

  final String language;
  final LalaAuthController? controller;
  final VoidCallback onAuthenticated;
  final String purpose;

  Future<void> _signIn(BuildContext context) async {
    final outcome = await requestCommunityAuthentication(
      context,
      controller: controller,
      language: language,
      actionLabel: purpose,
    );
    if (!context.mounted) return;
    if (outcome == CommunityAuthOutcome.alreadyAuthenticated ||
        outcome == CommunityAuthOutcome.signedInNow) {
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
              lalaCopyMulti(
                language,
                ko: '계정을 연결해 대화를 이어가세요',
                en: 'Connect your account to continue the conversation',
                ja: 'アカウントを連携して会話を続けましょう',
                zhHans: '连接账号以继续对话',
                zhHant: '連結帳號以繼續對話',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              lalaCopyMulti(
                language,
                ko: '공개 커뮤니티 글은 로그인 없이 읽을 수 있지만 채팅과 쓰기는 사용자 보호를 위해 로그인이 필요해요.',
                en: 'Public posts remain readable without sign-in. Chat and writing require an account for participant safety.',
                ja: '公開投稿はログインなしで読めますが、安全のためチャットと投稿にはログインが必要です。',
                zhHans: '公开帖子无需登录即可阅读；为保护参与者，聊天和发布需要登录。',
                zhHant: '公開貼文無需登入即可閱讀；為保護參與者，聊天和發布需要登入。',
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
              onPressed: controller == null || !controller!.config.enabled
                  ? null
                  : () => _signIn(context),
              icon: const Icon(Icons.login_rounded),
              label: Text(
                lalaCopyMulti(
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
