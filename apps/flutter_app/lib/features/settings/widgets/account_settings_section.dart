import 'package:flutter/material.dart';

import '../../../auth/auth_controller.dart';
import '../../../shared/l10n/lala_copy.dart';
import 'settings_section.dart';

/// 계정 상태 섹션(C3 추출 — main.dart 의 _AccountSettingsSection).
/// 인증 컨트롤러 상태에 따라 게스트/로그인/에러 UI 를 그린다.
class AccountSettingsSection extends StatelessWidget {
  const AccountSettingsSection({
    super.key,
    required this.controller,
    required this.language,
  });

  final LalaAuthController controller;
  final String language;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        if (state.status == LalaAuthStatus.disabled) {
          return SettingsSection(
            key: const ValueKey('account-panel'),
            title: lalaCopyMulti(
              language,
              ko: '계정',
              en: 'Account',
              ja: 'アカウント',
              zhHans: '账户',
              zhHant: '帳戶',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  lalaCopyMulti(
                      language,
                      ko: '계정 로그인을 사용할 수 없어요',
                      en: 'Sign-in unavailable',
                      ja: 'ログインは利用できません',
                      zhHans: '登录不可用',
                      zhHant: '登入不可用',
                    ),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }
        return SettingsSection(
          title: lalaCopyMulti(
              language,
              ko: '계정',
              en: 'Account',
              ja: 'アカウント',
              zhHans: '账户',
              zhHant: '帳戶',
            ),
          child: Container(
            key: const ValueKey('account-panel'),
            constraints: const BoxConstraints(minHeight: 72),
            alignment: Alignment.centerLeft,
            child: _buildState(context, state),
          ),
        );
      },
    );
  }

  Widget _buildState(BuildContext context, LalaAuthState state) {
    if (state.status == LalaAuthStatus.busy) {
      return Row(
        children: [
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              key: ValueKey('account-progress'),
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            lalaCopyMulti(
              language,
              ko: '계정 처리 중',
              en: 'Updating account',
              ja: 'アカウントを処理中',
              zhHans: '正在处理账户',
              zhHant: '正在處理帳戶',
            ),
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    if (!state.authenticated) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AccountStatusRow(
                  icon: Icons.person_outline,
                  label: lalaCopyMulti(
                      language,
                      ko: '게스트로 이용 중',
                      en: 'Using LALA as a guest',
                      ja: 'ゲストとして利用中',
                      zhHans: '正在以访客身份使用',
                      zhHant: '正在以訪客身分使用',
                    ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('account-sign-in'),
                onPressed: controller.signIn,
                icon: const Icon(Icons.login, size: 20),
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
          if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            AccountErrorText(language: language),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_circle_outlined, color: Color(0xFF2B6CB0)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.profile?.name ??
                        lalaCopyMulti(
              language,
              ko: '로그인됨',
              en: 'Signed in',
              ja: 'ログイン済み',
              zhHans: '已登录',
              zhHant: '已登入',
            ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (state.profile?.email != null)
                    Text(
                      state.profile!.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('account-sign-out'),
              tooltip: lalaCopyMulti(
              language,
              ko: '로그아웃',
              en: 'Sign out',
              ja: 'ログアウト',
              zhHans: '退出登录',
              zhHant: '登出',
            ),
              onPressed: controller.signOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        if (state.accountSyncStatus == LalaAccountSyncStatus.error) ...[
          const SizedBox(height: 8),
          AccountErrorText(
            language: language,
            category: state.accountSyncErrorCategory,
          ),
          TextButton.icon(
            key: const ValueKey('account-sync-retry'),
            onPressed: controller.retryAccountSync,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              lalaCopyMulti(
                language,
                ko: '계정 연결 다시 시도',
                en: 'Retry account sync',
                ja: 'アカウント連携を再試行',
                zhHans: '重试账户同步',
                zhHant: '重試帳戶同步',
              ),
            ),
          ),
        ] else if (state.errorMessage != null) ...[
          const SizedBox(height: 8),
          AccountErrorText(language: language),
        ],
        if (state.me != null)
          TextButton(
          key: const ValueKey('account-delete'),
          onPressed: () => _confirmDelete(context),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: const Color(0xFFB42318),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
          child: Text(
              lalaCopyMulti(
                language,
                ko: '계정 삭제',
                en: 'Delete account',
                ja: 'アカウントを削除',
                zhHans: '删除账户',
                zhHant: '刪除帳戶',
              ),
            ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('account-delete-dialog'),
        title: Text(
            lalaCopyMulti(
              language,
              ko: '계정을 삭제할까요?',
              en: 'Delete account?',
              ja: 'アカウントを削除しますか？',
              zhHans: '要删除账户吗？',
              zhHant: '要刪除帳戶嗎？',
            ),
          ),
        content: Text(
          lalaCopyMulti(
              language,
              ko: '계정과 연결된 데이터가 삭제되며 되돌릴 수 없습니다.',
              en: 'Your account data will be deleted and cannot be restored.',
              ja: 'アカウントに関連するデータが削除され、元に戻せません。',
              zhHans: '与账户关联的数据将被删除且无法恢复。',
              zhHant: '與帳戶相關的資料將被刪除且無法復原。',
            ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('account-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              lalaCopyMulti(
                language,
                ko: '취소',
                en: 'Cancel',
                ja: 'キャンセル',
                zhHans: '取消',
                zhHant: '取消',
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('account-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB42318),
            ),
            child: Text(
              lalaCopyMulti(
                language,
                ko: '삭제',
                en: 'Delete',
                ja: '削除',
                zhHans: '删除',
                zhHant: '刪除',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteAccount();
    }
  }
}

/// 계정 상태 한 줄 표시(C3 추출 — main.dart 의 _AccountStatusRow).
class AccountStatusRow extends StatelessWidget {
  const AccountStatusRow({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF64748B)),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 계정 에러 안내 텍스트(C3 추출 — main.dart 의 _AccountErrorText).
/// 동기화 실패는 안전한 카테고리별 문구로만 구분한다(세션 만료/일시 장애/설정 오류).
class AccountErrorText extends StatelessWidget {
  const AccountErrorText({super.key, required this.language, this.category});

  final String language;
  final LalaAccountSyncErrorCategory? category;

  @override
  Widget build(BuildContext context) {
    final copy = switch (category) {
      LalaAccountSyncErrorCategory.staleSession => lalaCopyMulti(
        language,
        ko: '세션이 만료되었어요. 다시 로그인해 주세요.',
        en: 'Your session has expired. Please sign in again.',
        ja: 'セッションの有効期限が切れました。再度ログインしてください。',
        zhHans: '会话已过期，请重新登录。',
        zhHant: '工作階段已過期，請重新登入。',
      ),
      LalaAccountSyncErrorCategory.configuration => lalaCopyMulti(
        language,
        ko: '계정 연결 설정을 사용할 수 없어요. 지도·검색·일정은 계속 이용할 수 있어요.',
        en:
            'Account linking is unavailable in this build. Maps, search, and plans keep working.',
        ja: 'アカウント連携の設定が利用できません。地図・検索・日程は引き続き利用できます。',
        zhHans: '账户关联配置不可用。地图、搜索和行程仍可继续使用。',
        zhHant: '帳戶連結設定無法使用。地圖、搜尋和行程仍可繼續使用。',
      ),
      _ => lalaCopyMulti(
        language,
        ko: '계정 요청을 완료하지 못했어요. 다시 시도해 주세요.',
        en: 'We could not complete the account request. Please try again.',
        ja: 'アカウントリクエストを完了できませんでした。もう一度お試しください。',
        zhHans: '无法完成账户请求，请重试。',
        zhHant: '無法完成帳戶請求，請重試。',
      ),
    };
    return Text(
      copy,
      style: const TextStyle(
        color: Color(0xFFB42318),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
    );
  }
}
