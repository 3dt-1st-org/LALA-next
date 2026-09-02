import 'package:flutter/material.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/settings/widgets/account_settings_section.dart';
import 'package:lala_next_app/features/settings/widgets/privacy_details_sheet.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// S-51: explicit account lifecycle and LALA account-sync status.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.authController});

  final LalaAuthController authController;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (context, language, _) {
        return Scaffold(
          key: const ValueKey('account-page'),
          backgroundColor: LalaVisualColors.surface,
          appBar: AppBar(
            backgroundColor: LalaVisualColors.surface,
            surfaceTintColor: Colors.transparent,
            title: Text(
              lalaCopyMulti(
                language,
                ko: '계정 관리',
                en: 'Account',
                ja: 'アカウント管理',
                zhHans: '账号管理',
                zhHant: '帳號管理',
              ),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                LalaVisualTokens.pageGutter,
                12,
                LalaVisualTokens.pageGutter,
                28,
              ),
              children: <Widget>[
                AccountSettingsSection(
                  controller: authController,
                  language: language,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: LalaVisualColors.card,
                    borderRadius: BorderRadius.circular(
                      LalaVisualTokens.controlRadius,
                    ),
                    border: Border.all(color: LalaVisualColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        lalaCopyMulti(
                          language,
                          ko: '계정에 저장되는 정보',
                          en: 'Data stored with your account',
                          ja: 'アカウントに保存される情報',
                          zhHans: '账号中保存的信息',
                          zhHant: '帳號中儲存的資訊',
                        ),
                        style: const TextStyle(
                          color: LalaVisualColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        lalaCopyMulti(
                          language,
                          ko: '로그인 식별자와 사용자가 직접 저장한 여행 취향을 연결합니다. 위치 권한과 정확한 좌표는 계정 프로필에 저장하지 않습니다.',
                          en: 'LALA links your sign-in identity with preferences you choose to save. Location permission and precise coordinates are not stored in the account profile.',
                          ja: 'ログイン識別子と、保存を選んだ旅行の好みを連携します。位置情報の権限や正確な座標はアカウントプロフィールに保存しません。',
                          zhHans: 'LALA 会关联登录标识与您主动保存的旅行偏好。位置权限和精确坐标不会存入账号资料。',
                          zhHant: 'LALA 會連結登入識別與您主動儲存的旅行偏好。位置權限和精確座標不會存入帳號資料。',
                        ),
                        style: const TextStyle(
                          color: LalaVisualColors.muted,
                          height: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        key: const ValueKey('account-privacy-details'),
                        onPressed: () =>
                            showPrivacyDetailsSheet(context, language),
                        icon: const Icon(Icons.privacy_tip_outlined),
                        label: Text(
                          lalaCopyMulti(
                            language,
                            ko: '개인정보 안내 보기',
                            en: 'View privacy details',
                            ja: 'プライバシー案内を見る',
                            zhHans: '查看隐私说明',
                            zhHant: '查看隱私說明',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
