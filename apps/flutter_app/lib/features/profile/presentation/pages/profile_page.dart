import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/settings/widgets/privacy_details_sheet.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// S-50: account, personalization, and app-setting entry points.
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.authController,
    this.preferencesStore,
    this.tripLibraryStore,
  });

  final LalaAuthController? authController;
  final TravelPreferencesStore? preferencesStore;
  final TripLibraryStore? tripLibraryStore;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TravelPreferencesStore _preferencesStore;
  late final TripLibraryStore _tripLibraryStore;

  @override
  void initState() {
    super.initState();
    _preferencesStore =
        widget.preferencesStore ?? TravelPreferencesStore.instance;
    _tripLibraryStore = widget.tripLibraryStore ?? TripLibraryStore.instance;
    unawaited(_preferencesStore.ensureLoaded());
    unawaited(_tripLibraryStore.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (context, language, _) {
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _preferencesStore,
            _tripLibraryStore,
            SavedPlaceStore.listenable,
          ]),
          builder: (context, _) {
            final auth = widget.authController;
            if (auth == null) {
              return _buildPage(context, language, null);
            }
            return AnimatedBuilder(
              animation: auth,
              builder: (context, _) =>
                  _buildPage(context, language, auth.state),
            );
          },
        );
      },
    );
  }

  Widget _buildPage(
    BuildContext context,
    String language,
    LalaAuthState? authState,
  ) {
    final preferences = _preferencesStore.value;
    final syncStatus = _preferencesStore.syncStatus;
    return Scaffold(
      key: const ValueKey('profile-page'),
      backgroundColor: LalaVisualColors.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            LalaVisualTokens.pageGutter,
            22,
            LalaVisualTokens.pageGutter,
            28,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    lalaCopyMulti(
                      language,
                      ko: '내 정보',
                      en: 'My Info',
                      ja: 'マイ情報',
                      zhHans: '我的',
                      zhHant: '我的',
                    ),
                    style: const TextStyle(
                      color: LalaVisualColors.ink,
                      fontSize: LalaVisualTokens.screenSize,
                      height:
                          LalaVisualTokens.screenLineHeight /
                          LalaVisualTokens.screenSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                _SyncIndicator(status: syncStatus, language: language),
              ],
            ),
            const SizedBox(height: 18),
            _AccountOverviewCard(
              state: authState,
              language: language,
              enabled: widget.authController != null,
              onTap: widget.authController == null
                  ? null
                  : () => context.push(LalaRoutePaths.account),
            ),
            if (syncStatus == TravelPreferencesSyncStatus.conflict ||
                syncStatus == TravelPreferencesSyncStatus.error) ...<Widget>[
              const SizedBox(height: 12),
              _SyncNotice(
                status: syncStatus,
                language: language,
                onTap: () => context.push(LalaRoutePaths.travelPreferences),
              ),
            ],
            const SizedBox(height: LalaVisualTokens.sectionGap),
            Text(
              lalaCopyMulti(
                language,
                ko: '여행 경험',
                en: 'Travel experience',
                ja: '旅行体験',
                zhHans: '旅行体验',
                zhHant: '旅行體驗',
              ),
              style: const TextStyle(
                color: LalaVisualColors.ink,
                fontSize: LalaVisualTokens.sectionTitleSize,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            _PreferenceSummaryCard(
              preferences: preferences,
              language: language,
              onTap: () => context.push(LalaRoutePaths.travelPreferences),
            ),
            const SizedBox(height: 10),
            Material(
              color: LalaVisualColors.card,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  LalaVisualTokens.controlRadius,
                ),
                side: const BorderSide(color: LalaVisualColors.line),
              ),
              child: Column(
                children: <Widget>[
                  _ProfileMenuRow(
                    key: const ValueKey('profile-saved-places-entry'),
                    icon: Icons.bookmark_outline_rounded,
                    title: lalaCopyMulti(
                      language,
                      ko: '저장한 장소',
                      en: 'Saved places',
                      ja: '保存した場所',
                      zhHans: '已保存地点',
                      zhHant: '已儲存地點',
                    ),
                    value: '${SavedPlaceStore.current.length}',
                    onTap: () => context.push(LalaRoutePaths.savedPlaces),
                  ),
                  const Divider(height: 1, indent: 56),
                  _ProfileMenuRow(
                    key: const ValueKey('profile-past-trips-entry'),
                    icon: Icons.calendar_month_outlined,
                    title: lalaCopyMulti(
                      language,
                      ko: '지난 일정',
                      en: 'Past trips',
                      ja: '過去の旅行',
                      zhHans: '历史行程',
                      zhHant: '過往行程',
                    ),
                    value: _tripLibraryStore.accountConnected
                        ? '${_tripLibraryStore.pastTrips.length}'
                        : null,
                    onTap: () => context.push(LalaRoutePaths.pastTrips),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LalaVisualTokens.sectionGap),
            Text(
              lalaCopyMulti(
                language,
                ko: '서비스 설정',
                en: 'Service settings',
                ja: 'サービス設定',
                zhHans: '服务设置',
                zhHant: '服務設定',
              ),
              style: const TextStyle(
                color: LalaVisualColors.ink,
                fontSize: LalaVisualTokens.sectionTitleSize,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: LalaVisualColors.card,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  LalaVisualTokens.controlRadius,
                ),
                side: const BorderSide(color: LalaVisualColors.line),
              ),
              child: Column(
                children: <Widget>[
                  _ProfileMenuRow(
                    key: const ValueKey('profile-language-entry'),
                    icon: Icons.translate_rounded,
                    title: lalaCopyMulti(
                      language,
                      ko: '언어',
                      en: 'Language',
                      ja: '言語',
                      zhHans: '语言',
                      zhHant: '語言',
                    ),
                    value: _languageName(language),
                    onTap: () => _selectLanguage(context, language),
                  ),
                  const Divider(height: 1, indent: 56),
                  _ProfileMenuRow(
                    key: const ValueKey('profile-privacy-entry'),
                    icon: Icons.privacy_tip_outlined,
                    title: lalaCopyMulti(
                      language,
                      ko: '개인정보 및 위치',
                      en: 'Privacy and location',
                      ja: 'プライバシーと位置情報',
                      zhHans: '隐私与位置',
                      zhHant: '隱私與位置',
                    ),
                    onTap: () => showPrivacyDetailsSheet(context, language),
                  ),
                  const Divider(height: 1, indent: 56),
                  _ProfileMenuRow(
                    key: const ValueKey('profile-community-chat-entry'),
                    icon: Icons.forum_outlined,
                    title: lalaCopyMulti(
                      language,
                      ko: '현지 가이드 채팅',
                      en: 'Local guide chats',
                      ja: '現地ガイドのチャット',
                      zhHans: '当地向导聊天',
                      zhHant: '在地嚮導聊天',
                    ),
                    onTap: () => context.push(LalaRoutePaths.communityChat),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectLanguage(
    BuildContext context,
    String currentLanguage,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => RadioGroup<String>(
        groupValue: currentLanguage,
        onChanged: (value) => Navigator.of(context).pop(value),
        child: ListView(
          key: const ValueKey('profile-language-sheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: <Widget>[
            for (final language in kLalaLanguages)
              RadioListTile<String>(
                value: language,
                title: Text(_languageName(language)),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      OnboardingState.selectLanguage(selected);
    }
  }
}

class _AccountOverviewCard extends StatelessWidget {
  const _AccountOverviewCard({
    required this.state,
    required this.language,
    required this.enabled,
    required this.onTap,
  });

  final LalaAuthState? state;
  final String language;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final authenticated = state?.authenticated ?? false;
    final name = authenticated
        ? state?.profile?.name ??
              lalaCopyMulti(
                language,
                ko: '연결된 여행자',
                en: 'Connected traveler',
                ja: '連携済みの旅行者',
                zhHans: '已连接的旅行者',
                zhHant: '已連結的旅客',
              )
        : lalaCopyMulti(
            language,
            ko: '게스트 여행자',
            en: 'Guest traveler',
            ja: 'ゲスト旅行者',
            zhHans: '访客旅行者',
            zhHant: '訪客旅客',
          );
    final detail = !enabled
        ? lalaCopyMulti(
            language,
            ko: '이 빌드에서는 계정 연결을 사용할 수 없어요.',
            en: 'Account linking is unavailable in this build.',
            ja: 'このビルドではアカウント連携を利用できません。',
            zhHans: '此版本无法使用账号连接。',
            zhHant: '此版本無法使用帳號連結。',
          )
        : authenticated
        ? _accountSyncLabel(state!.accountSyncStatus, language)
        : lalaCopyMulti(
            language,
            ko: '로그인하면 취향과 일정을 기기 간에 이어갈 수 있어요.',
            en: 'Sign in to continue preferences and trips across devices.',
            ja: 'ログインすると好みや旅程を端末間で引き継げます。',
            zhHans: '登录后可跨设备继续使用偏好和行程。',
            zhHant: '登入後可跨裝置延續偏好與行程。',
          );
    return Material(
      color: LalaVisualColors.card,
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      child: InkWell(
        key: const ValueKey('profile-account-entry'),
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: LalaVisualColors.line),
            borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 28,
                backgroundColor: LalaVisualColors.primarySoft,
                child: Icon(
                  authenticated
                      ? Icons.account_circle_rounded
                      : Icons.person_outline_rounded,
                  color: LalaVisualColors.primaryBlue,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LalaVisualColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LalaVisualColors.muted,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: LalaVisualColors.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreferenceSummaryCard extends StatelessWidget {
  const _PreferenceSummaryCard({
    required this.preferences,
    required this.language,
    required this.onTap,
  });

  final TravelPreferences preferences;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final interests = preferences.interests.take(3).toList(growable: false);
    return Material(
      color: const Color(0xFF062552),
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      child: InkWell(
        key: const ValueKey('profile-travel-preferences-entry'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                lalaCopyMulti(
                  language,
                  ko: '기본 여행 취향',
                  en: 'Default travel preferences',
                  ja: '基本の旅行の好み',
                  zhHans: '默认旅行偏好',
                  zhHant: '預設旅行偏好',
                ),
                style: const TextStyle(
                  color: Color(0xFFBFD7FF),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _paceName(preferences.pace, language),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              if (interests.isEmpty)
                Text(
                  lalaCopyMulti(
                    language,
                    ko: '관심사를 설정하면 추천 이유가 더 선명해져요.',
                    en: 'Choose interests to make recommendation reasons clearer.',
                    ja: '関心を設定するとおすすめ理由がより明確になります。',
                    zhHans: '设置兴趣后，推荐理由会更清晰。',
                    zhHant: '設定興趣後，推薦理由會更清楚。',
                  ),
                  style: const TextStyle(
                    color: Color(0xFFDCE9FF),
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final interest in interests)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(color: Color(0xFF527DB8)),
                        backgroundColor: const Color(0xFF173E72),
                        label: Text(
                          _interestName(interest, language),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Text(
                    lalaCopyMulti(
                      language,
                      ko: '설정 변경',
                      en: 'Edit preferences',
                      ja: '設定を変更',
                      zhHans: '修改设置',
                      zhHant: '變更設定',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      minTileHeight: 58,
      leading: Icon(icon, color: LalaVisualColors.primaryBlue),
      title: Text(
        title,
        style: const TextStyle(
          color: LalaVisualColors.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: LalaVisualColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: LalaVisualColors.muted,
          ),
        ],
      ),
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.status, required this.language});

  final TravelPreferencesSyncStatus status;
  final String language;

  @override
  Widget build(BuildContext context) {
    final synced = status == TravelPreferencesSyncStatus.synced;
    final busy = status == TravelPreferencesSyncStatus.checking;
    return Tooltip(
      message: _preferenceSyncLabel(status, language),
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  synced ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  color: synced
                      ? const Color(0xFF148467)
                      : LalaVisualColors.muted,
                ),
        ),
      ),
    );
  }
}

class _SyncNotice extends StatelessWidget {
  const _SyncNotice({
    required this.status,
    required this.language,
    required this.onTap,
  });

  final TravelPreferencesSyncStatus status;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final conflict = status == TravelPreferencesSyncStatus.conflict;
    return Material(
      color: conflict ? const Color(0xFFFFF7ED) : const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      child: ListTile(
        key: const ValueKey('profile-preference-sync-notice'),
        onTap: onTap,
        leading: Icon(
          conflict ? Icons.sync_problem_rounded : Icons.cloud_off_rounded,
          color: conflict ? const Color(0xFFB45309) : const Color(0xFFBE123C),
        ),
        title: Text(
          _preferenceSyncLabel(status, language),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

String _accountSyncLabel(LalaAccountSyncStatus status, String language) {
  return switch (status) {
    LalaAccountSyncStatus.ready => lalaCopyMulti(
      language,
      ko: 'LALA 계정과 연결됐어요.',
      en: 'Connected to your LALA account.',
      ja: 'LALAアカウントと連携済みです。',
      zhHans: '已连接到 LALA 账号。',
      zhHant: '已連結至 LALA 帳號。',
    ),
    LalaAccountSyncStatus.syncing => lalaCopyMulti(
      language,
      ko: '계정 정보를 동기화하고 있어요.',
      en: 'Syncing account information.',
      ja: 'アカウント情報を同期しています。',
      zhHans: '正在同步账号信息。',
      zhHant: '正在同步帳號資訊。',
    ),
    LalaAccountSyncStatus.error => lalaCopyMulti(
      language,
      ko: '계정 동기화를 다시 확인해 주세요.',
      en: 'Account sync needs attention.',
      ja: 'アカウント同期を確認してください。',
      zhHans: '请检查账号同步。',
      zhHant: '請檢查帳號同步。',
    ),
    LalaAccountSyncStatus.idle => lalaCopyMulti(
      language,
      ko: '계정 연결 상태를 확인하고 있어요.',
      en: 'Checking the account connection.',
      ja: 'アカウント接続を確認しています。',
      zhHans: '正在检查账号连接。',
      zhHant: '正在檢查帳號連結。',
    ),
  };
}

String _preferenceSyncLabel(
  TravelPreferencesSyncStatus status,
  String language,
) {
  return switch (status) {
    TravelPreferencesSyncStatus.synced => lalaCopyMulti(
      language,
      ko: '여행 취향 동기화 완료',
      en: 'Travel preferences synced',
      ja: '旅行の好みを同期済み',
      zhHans: '旅行偏好已同步',
      zhHant: '旅行偏好已同步',
    ),
    TravelPreferencesSyncStatus.checking => lalaCopyMulti(
      language,
      ko: '여행 취향 동기화 중',
      en: 'Syncing travel preferences',
      ja: '旅行の好みを同期中',
      zhHans: '正在同步旅行偏好',
      zhHant: '正在同步旅行偏好',
    ),
    TravelPreferencesSyncStatus.conflict => lalaCopyMulti(
      language,
      ko: '기기와 계정의 여행 취향이 달라요.',
      en: 'Device and account preferences differ.',
      ja: '端末とアカウントの旅行設定が異なります。',
      zhHans: '设备与账号的旅行偏好不同。',
      zhHant: '裝置與帳號的旅行偏好不同。',
    ),
    TravelPreferencesSyncStatus.error => lalaCopyMulti(
      language,
      ko: '여행 취향을 동기화하지 못했어요.',
      en: 'Travel preferences could not be synced.',
      ja: '旅行の好みを同期できませんでした。',
      zhHans: '无法同步旅行偏好。',
      zhHant: '無法同步旅行偏好。',
    ),
    TravelPreferencesSyncStatus.serverEmpty => lalaCopyMulti(
      language,
      ko: '기기 취향을 계정에 저장할 수 있어요.',
      en: 'Device preferences can be saved to your account.',
      ja: '端末の設定をアカウントに保存できます。',
      zhHans: '可将设备偏好保存到账号。',
      zhHant: '可將裝置偏好儲存到帳號。',
    ),
    TravelPreferencesSyncStatus.localOnly => lalaCopyMulti(
      language,
      ko: '이 기기에 저장됨',
      en: 'Saved on this device',
      ja: 'この端末に保存済み',
      zhHans: '已保存在此设备',
      zhHant: '已儲存在此裝置',
    ),
  };
}

String _paceName(TravelPace pace, String language) => switch (pace) {
  TravelPace.relaxed => lalaCopyMulti(
    language,
    ko: '여유롭게 둘러보기',
    en: 'A relaxed journey',
    ja: 'ゆったり巡る旅',
    zhHans: '悠闲旅行',
    zhHant: '悠閒旅行',
  ),
  TravelPace.balanced => lalaCopyMulti(
    language,
    ko: '균형 있게 여행하기',
    en: 'A balanced journey',
    ja: 'バランスのよい旅',
    zhHans: '均衡旅行',
    zhHant: '均衡旅行',
  ),
  TravelPace.packed => lalaCopyMulti(
    language,
    ko: '알차게 둘러보기',
    en: 'A full itinerary',
    ja: '充実した旅',
    zhHans: '充实行程',
    zhHant: '充實行程',
  ),
};

String _interestName(TravelInterest interest, String language) {
  final labels = <TravelInterest, List<String>>{
    TravelInterest.localFood: <String>[
      '로컬 음식',
      'Local food',
      'ローカル料理',
      '本地美食',
      '在地美食',
    ],
    TravelInterest.cafe: <String>['카페', 'Cafes', 'カフェ', '咖啡馆', '咖啡館'],
    TravelInterest.history: <String>[
      '전통·역사',
      'History',
      '伝統・歴史',
      '传统历史',
      '傳統歷史',
    ],
    TravelInterest.arts: <String>['미술·공연', 'Arts', '芸術・公演', '艺术演出', '藝術表演'],
    TravelInterest.nature: <String>['자연', 'Nature', '自然', '自然', '自然'],
    TravelInterest.walk: <String>['산책', 'Walks', '散歩', '散步', '散步'],
    TravelInterest.night: <String>['야경', 'Night views', '夜景', '夜景', '夜景'],
    TravelInterest.shopping: <String>['쇼핑', 'Shopping', '買い物', '购物', '購物'],
    TravelInterest.market: <String>['시장', 'Markets', '市場', '市场', '市場'],
    TravelInterest.festival: <String>['축제', 'Festivals', '祭り', '节庆', '節慶'],
    TravelInterest.handsOn: <String>['체험', 'Hands-on', '体験', '体验', '體驗'],
    TravelInterest.photography: <String>['사진', 'Photography', '写真', '摄影', '攝影'],
  };
  final index = switch (normalizeLalaLanguage(language)) {
    'en' => 1,
    'ja' => 2,
    'zh-Hans' => 3,
    'zh-Hant' => 4,
    _ => 0,
  };
  return labels[interest]![index];
}

String _languageName(String language) =>
    switch (normalizeLalaLanguage(language)) {
      'en' => 'English',
      'ja' => '日本語',
      'zh-Hans' => '简体中文',
      'zh-Hant' => '繁體中文',
      _ => '한국어',
    };
