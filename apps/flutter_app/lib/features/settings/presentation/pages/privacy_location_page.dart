import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/core/location/app_settings_opener.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/persistence/action_preferences.dart';
import 'package:lala_next_app/core/persistence/cross_tab_preferences.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/settings/data/privacy_settings_store.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// S-58: app-level location consent, OS hand-off, and explicit device-data
/// controls. Account deletion remains owned by S-51.
class PrivacyLocationPage extends StatefulWidget {
  const PrivacyLocationPage({
    super.key,
    this.authController,
    this.privacyStore,
    this.preferencesStore,
    this.tripLibraryStore,
  });

  final LalaAuthController? authController;
  final PrivacySettingsStore? privacyStore;
  final TravelPreferencesStore? preferencesStore;
  final TripLibraryStore? tripLibraryStore;

  @override
  State<PrivacyLocationPage> createState() => _PrivacyLocationPageState();
}

class _PrivacyLocationPageState extends State<PrivacyLocationPage> {
  late final PrivacySettingsStore _privacyStore;
  late final TravelPreferencesStore _preferencesStore;
  late final TripLibraryStore _tripLibraryStore;
  bool _clearing = false;

  String get _language => OnboardingState.language;

  @override
  void initState() {
    super.initState();
    _privacyStore = widget.privacyStore ?? PrivacySettingsStore.instance;
    _preferencesStore =
        widget.preferencesStore ?? TravelPreferencesStore.instance;
    _tripLibraryStore = widget.tripLibraryStore ?? TripLibraryStore.instance;
    unawaited(_privacyStore.ensureLoaded());
    unawaited(_preferencesStore.ensureLoaded());
    unawaited(_tripLibraryStore.ensureLoaded());
  }

  Future<void> _openSystemSettings() async {
    final opened = await openAppSettings();
    if (!mounted || opened) return;
    _message(
      lalaCopyMulti(
        _language,
        ko: '이 기기에서는 앱 설정을 바로 열 수 없어요.',
        en: 'Device settings cannot be opened directly here.',
        ja: 'この端末ではアプリ設定を直接開けません。',
        zhHans: '无法从此处直接打开设备设置。',
        zhHant: '無法從此處直接開啟裝置設定。',
      ),
    );
  }

  Future<void> _confirmAndClearGuestData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          lalaCopyMulti(
            _language,
            ko: '이 기기의 여행 설정을 지울까요?',
            en: 'Clear travel settings on this device?',
            ja: 'この端末の旅行設定を消去しますか？',
            zhHans: '清除此设备上的旅行设置？',
            zhHant: '清除此裝置上的旅行設定？',
          ),
        ),
        content: Text(
          lalaCopyMulti(
            _language,
            ko: '기본 취향, 여행별 설정, 저장 장소, 현재 일정, 방문 기록, 온보딩과 직접 선택한 지역이 삭제됩니다. 계정·커뮤니티 글·운영체제 위치 권한은 삭제되지 않습니다.',
            en: 'This removes device preferences, trip overrides, saved places, the current plan, visit feedback, onboarding choices, and the manual region. It does not delete your account, community posts, or OS permission.',
            ja: '端末の基本設定、旅行別設定、保存場所、現在のプラン、訪問記録、オンボーディング、手動地域を削除します。アカウント、コミュニティ投稿、OS権限は削除しません。',
            zhHans:
                '这会删除设备偏好、单次旅行设置、已保存地点、当前行程、访问记录、引导选择和手动地区。不会删除账号、社区帖子或系统权限。',
            zhHant:
                '這會刪除裝置偏好、單次旅行設定、已儲存地點、目前行程、造訪記錄、引導選擇和手動地區。不會刪除帳號、社群貼文或系統權限。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              lalaCopyMulti(
                _language,
                ko: '취소',
                en: 'Cancel',
                ja: 'キャンセル',
                zhHans: '取消',
                zhHant: '取消',
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              lalaCopyMulti(
                _language,
                ko: '기기 데이터 지우기',
                en: 'Clear device data',
                ja: '端末データを消去',
                zhHans: '清除设备数据',
                zhHant: '清除裝置資料',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final successMessage = lalaCopyMulti(
      _language,
      ko: '이 기기의 여행 데이터가 삭제됐어요.',
      en: 'Travel data on this device was cleared.',
      ja: 'この端末の旅行データを消去しました。',
      zhHans: '已清除此设备上的旅行数据。',
      zhHant: '已清除此裝置上的旅行資料。',
    );
    setState(() => _clearing = true);
    try {
      await _preferencesStore.clear();
      await _tripLibraryStore.clearDeviceData();
      await ActionPersistence.clearAndFlush();
      await CrossTabPersistence.clearAndFlush();
      await RegionContextStore.clearAndFlush();
      await _privacyStore.setLocationRecommendationsEnabled(false);
      await OnboardingState.resetAndFlush();
      if (!mounted) return;
      setState(() => _clearing = false);
      _message(successMessage);
    } on Object {
      if (!mounted) return;
      setState(() => _clearing = false);
      _message(
        lalaCopyMulti(
          _language,
          ko: '기기 데이터를 모두 지우지 못했어요. 다시 시도해 주세요.',
          en: 'Could not clear all device data. Please try again.',
          ja: '端末データをすべて消去できませんでした。もう一度お試しください。',
          zhHans: '无法清除全部设备数据，请重试。',
          zhHant: '無法清除全部裝置資料，請重試。',
        ),
      );
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (context, language, _) {
        final auth = widget.authController;
        if (auth == null) return _buildPage(language, null);
        return AnimatedBuilder(
          animation: auth,
          builder: (context, _) => _buildPage(language, auth.state),
        );
      },
    );
  }

  Widget _buildPage(String language, LalaAuthState? authState) {
    final accountConnected = authState?.authenticated ?? false;
    return AnimatedBuilder(
      animation: _privacyStore,
      builder: (context, _) => Scaffold(
        key: const ValueKey('privacy-location-page'),
        backgroundColor: LalaVisualColors.surface,
        appBar: AppBar(
          title: Text(
            lalaCopyMulti(
              language,
              ko: '개인정보와 위치',
              en: 'Privacy and location',
              ja: 'プライバシーと位置情報',
              zhHans: '隐私与位置',
              zhHant: '隱私與位置',
            ),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: LalaVisualColors.surface,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              _SettingsCard(
                child: SwitchListTile.adaptive(
                  key: const ValueKey('privacy-location-toggle'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    lalaCopyMulti(
                      language,
                      ko: '위치 기반 추천',
                      en: 'Location recommendations',
                      ja: '位置情報に基づくおすすめ',
                      zhHans: '基于位置的推荐',
                      zhHant: '基於位置的推薦',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    lalaCopyMulti(
                      language,
                      ko: '앱의 추천 설정입니다. 운영체제 위치 권한과는 별도로 관리돼요.',
                      en: 'This app choice is separate from the operating-system permission.',
                      ja: 'アプリ内の選択で、OSの位置権限とは別に管理されます。',
                      zhHans: '这是应用内选择，与系统位置权限分开管理。',
                      zhHant: '這是應用程式內選擇，與系統位置權限分開管理。',
                    ),
                  ),
                  value: _privacyStore.locationRecommendationsEnabled,
                  onChanged: _clearing
                      ? null
                      : _privacyStore.setLocationRecommendationsEnabled,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SectionTitle(
                      icon: Icons.settings_outlined,
                      text: lalaCopyMulti(
                        language,
                        ko: '기기 위치 권한',
                        en: 'Device location permission',
                        ja: '端末の位置情報権限',
                        zhHans: '设备位置权限',
                        zhHant: '裝置位置權限',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lalaCopyMulti(
                        language,
                        ko: '권한을 거부해도 지역을 직접 선택해 LALA를 계속 사용할 수 있어요.',
                        en: 'If permission is denied, choose an area manually and keep using LALA.',
                        ja: '権限を拒否しても、地域を手動選択してLALAを利用できます。',
                        zhHans: '即使拒绝权限，也可手动选择地区继续使用 LALA。',
                        zhHant: '即使拒絕權限，也可手動選擇地區繼續使用 LALA。',
                      ),
                      style: const TextStyle(
                        color: LalaVisualColors.muted,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (canOpenAppSettings)
                      OutlinedButton.icon(
                        key: const ValueKey('privacy-open-device-settings'),
                        onPressed: _openSystemSettings,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: Text(
                          lalaCopyMulti(
                            language,
                            ko: '기기 설정 열기',
                            en: 'Open device settings',
                            ja: '端末設定を開く',
                            zhHans: '打开设备设置',
                            zhHant: '開啟裝置設定',
                          ),
                        ),
                      ),
                    TextButton.icon(
                      key: const ValueKey('privacy-use-manual-area'),
                      onPressed: () => context.go(LalaRoutePaths.mapRoute),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        lalaCopyMulti(
                          language,
                          ko: '지도에서 지역 직접 선택',
                          en: 'Choose an area on the map',
                          ja: '地図で地域を手動選択',
                          zhHans: '在地图上手动选择地区',
                          zhHant: '在地圖上手動選擇地區',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SectionTitle(
                      icon: Icons.shield_outlined,
                      text: lalaCopyMulti(
                        language,
                        ko: '사용하는 정보',
                        en: 'Data LALA uses',
                        ja: 'LALAが使用する情報',
                        zhHans: 'LALA 使用的信息',
                        zhHant: 'LALA 使用的資訊',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DataLine(
                      text: lalaCopyMulti(
                        language,
                        ko: '선택 지역과 대략적인 위치 맥락',
                        en: 'Selected area and approximate location context',
                        ja: '選択地域とおおよその位置コンテキスト',
                        zhHans: '所选地区和大致位置环境',
                        zhHant: '所選地區和大致位置情境',
                      ),
                    ),
                    _DataLine(
                      text: lalaCopyMulti(
                        language,
                        ko: '여행 취향, 저장, 일정과 방문 확인',
                        en: 'Travel preferences, saves, plans, and visit feedback',
                        ja: '旅行の好み、保存、プラン、訪問確認',
                        zhHans: '旅行偏好、收藏、行程和访问确认',
                        zhHant: '旅行偏好、儲存、行程和造訪確認',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lalaCopyMulti(
                        language,
                        ko: '정밀 위치, 원문 리뷰, 비밀값은 공개 응답에 포함하지 않아요.',
                        en: 'Precise location, raw reviews, and secrets are not exposed in public responses.',
                        ja: '正確な位置、レビュー原文、秘密情報は公開レスポンスに含めません。',
                        zhHans: '公开响应不包含精确位置、原始评论或机密信息。',
                        zhHant: '公開回應不包含精確位置、原始評論或機密資訊。',
                      ),
                      style: const TextStyle(
                        color: LalaVisualColors.muted,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SectionTitle(
                      icon: accountConnected
                          ? Icons.cloud_done_outlined
                          : Icons.phone_iphone_outlined,
                      text: accountConnected
                          ? lalaCopyMulti(
                              language,
                              ko: '계정과 기기 데이터',
                              en: 'Account and device data',
                              ja: 'アカウントと端末データ',
                              zhHans: '账号和设备数据',
                              zhHant: '帳號和裝置資料',
                            )
                          : lalaCopyMulti(
                              language,
                              ko: '게스트 기기 데이터',
                              en: 'Guest device data',
                              ja: 'ゲスト端末データ',
                              zhHans: '访客设备数据',
                              zhHant: '訪客裝置資料',
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      accountConnected
                          ? lalaCopyMulti(
                              language,
                              ko: '계정 데이터는 계정 관리에서 범위를 확인한 뒤 삭제해야 해요. 여기서는 서버 데이터를 지우지 않습니다.',
                              en: 'Review and delete account data from Account. This screen never deletes server data.',
                              ja: 'アカウントデータはアカウント管理で範囲を確認して削除します。この画面ではサーバーデータを削除しません。',
                              zhHans: '请在账号管理中确认范围后删除账号数据。本页面不会删除服务器数据。',
                              zhHant: '請在帳號管理中確認範圍後刪除帳號資料。本頁面不會刪除伺服器資料。',
                            )
                          : lalaCopyMulti(
                              language,
                              ko: '이 기기에 저장된 여행 취향과 여행 기록을 지우고 온보딩부터 다시 시작할 수 있어요.',
                              en: 'Clear travel preferences and history stored on this device, then start onboarding again.',
                              ja: 'この端末の旅行設定と履歴を消去し、オンボーディングから再開できます。',
                              zhHans: '可清除此设备保存的旅行偏好与记录，并重新开始引导。',
                              zhHant: '可清除此裝置儲存的旅行偏好與記錄，並重新開始引導。',
                            ),
                      style: const TextStyle(
                        color: LalaVisualColors.muted,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (accountConnected)
                      OutlinedButton.icon(
                        key: const ValueKey('privacy-open-account'),
                        onPressed: widget.authController == null
                            ? null
                            : () => context.push(LalaRoutePaths.account),
                        icon: const Icon(Icons.manage_accounts_outlined),
                        label: Text(
                          lalaCopyMulti(
                            language,
                            ko: '계정 관리 열기',
                            en: 'Open account settings',
                            ja: 'アカウント管理を開く',
                            zhHans: '打开账号管理',
                            zhHant: '開啟帳號管理',
                          ),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        key: const ValueKey('privacy-clear-guest-data'),
                        onPressed: _clearing ? null : _confirmAndClearGuestData,
                        icon: _clearing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          lalaCopyMulti(
                            language,
                            ko: '게스트 기기 데이터 지우기',
                            en: 'Clear guest device data',
                            ja: 'ゲスト端末データを消去',
                            zhHans: '清除访客设备数据',
                            zhHant: '清除訪客裝置資料',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        side: const BorderSide(color: LalaVisualColors.line),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: LalaVisualColors.primaryBlue, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: LalaVisualColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _DataLine extends StatelessWidget {
  const _DataLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(
              Icons.check_circle_outline_rounded,
              color: LalaVisualColors.primaryBlue,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: LalaVisualColors.ink,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
