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
            title: lalaCopy(language, ko: '계정', en: 'Account'),
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
                  lalaCopy(
                    language,
                    ko: '계정 로그인을 사용할 수 없어요',
                    en: 'Sign-in unavailable',
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
          title: lalaCopy(language, ko: '계정', en: 'Account'),
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
            lalaCopy(language, ko: '계정 처리 중', en: 'Updating account'),
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    final me = state.me;
    if (me == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AccountStatusRow(
                  icon: Icons.person_outline,
                  label: lalaCopy(
                    language,
                    ko: '게스트로 이용 중',
                    en: 'Using LALA as a guest',
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('account-sign-in'),
                onPressed: controller.signIn,
                icon: const Icon(Icons.login, size: 20),
                label: Text(lalaCopy(language, ko: '로그인', en: 'Sign in')),
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
              child: Text(
                lalaCopy(language, ko: '로그인됨', en: 'Signed in'),
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('account-sign-out'),
              tooltip: lalaCopy(language, ko: '로그아웃', en: 'Sign out'),
              onPressed: controller.signOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 8),
          AccountErrorText(language: language),
        ],
        TextButton(
          key: const ValueKey('account-delete'),
          onPressed: () => _confirmDelete(context),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: const Color(0xFFB42318),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
          child: Text(lalaCopy(language, ko: '계정 삭제', en: 'Delete account')),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('account-delete-dialog'),
        title: Text(lalaCopy(language, ko: '계정을 삭제할까요?', en: 'Delete account?')),
        content: Text(
          lalaCopy(
            language,
            ko: '계정과 연결된 데이터가 삭제되며 되돌릴 수 없습니다.',
            en: 'Your account data will be deleted and cannot be restored.',
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('account-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(lalaCopy(language, ko: '취소', en: 'Cancel')),
          ),
          TextButton(
            key: const ValueKey('account-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB42318),
            ),
            child: Text(lalaCopy(language, ko: '삭제', en: 'Delete')),
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
class AccountErrorText extends StatelessWidget {
  const AccountErrorText({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Text(
      lalaCopy(
        language,
        ko: '계정 요청을 완료하지 못했어요. 다시 시도해 주세요.',
        en: 'We could not complete the account request. Please try again.',
      ),
      style: const TextStyle(
        color: Color(0xFFB42318),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
    );
  }
}
