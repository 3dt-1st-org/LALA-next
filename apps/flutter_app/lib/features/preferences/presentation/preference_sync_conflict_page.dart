import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/lala_visual_tokens.dart';
import '../../../shared/l10n/lala_copy.dart';
import '../data/travel_preferences_store.dart';
import '../domain/travel_preferences.dart';

/// S-59: explicit, revision-safe choice between device and account defaults.
class PreferenceSyncConflictPage extends StatefulWidget {
  const PreferenceSyncConflictPage({
    required this.language,
    this.store,
    super.key,
  });

  final String language;
  final TravelPreferencesStore? store;

  @override
  State<PreferenceSyncConflictPage> createState() =>
      _PreferenceSyncConflictPageState();
}

class _PreferenceSyncConflictPageState
    extends State<PreferenceSyncConflictPage> {
  late final TravelPreferencesStore _store;
  bool _busy = false;
  String? _safeError;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? TravelPreferencesStore.instance;
    _store.addListener(_onStoreChanged);
    unawaited(_store.ensureLoaded());
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _safeError = null;
    });
    try {
      await action();
    } on Object {
      _safeError = _copy(
        widget.language,
        ko: '동기화하지 못했어요. 기기 설정은 그대로 유지됩니다.',
        en: 'Sync failed. Your device preferences are unchanged.',
        ja: '同期できませんでした。端末の設定はそのまま保持されます。',
        zhHans: '同步失败。设备偏好保持不变。',
        zhHant: '同步失敗。裝置偏好維持不變。',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final account = _store.accountPreferences;
    final status = _store.syncStatus;
    final differences = account == null
        ? const <_PreferenceDifference>[]
        : _preferenceDifferences(_store.value, account, language);
    return Scaffold(
      key: const ValueKey('preference-sync-conflict-page'),
      backgroundColor: LalaVisualColors.surface,
      appBar: AppBar(
        backgroundColor: LalaVisualColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const ValueKey('preference-sync-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Text(
          _copy(
            language,
            ko: '취향 동기화 충돌',
            en: 'Resolve preference conflict',
            ja: '設定の同期競合',
            zhHans: '解决偏好同步冲突',
            zhHant: '解決偏好同步衝突',
          ),
        ),
        centerTitle: true,
      ),
      body: !_store.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: <Widget>[
                        _StatusIntro(
                          language: language,
                          status: status,
                          accountAvailable: account != null,
                        ),
                        if (_safeError != null) ...<Widget>[
                          const SizedBox(height: 12),
                          _ErrorBanner(message: _safeError!),
                        ],
                        const SizedBox(height: 16),
                        _VersionSummary(
                          language: language,
                          deviceUpdatedAt: _store.deviceUpdatedAt,
                          accountUpdatedAt: _store.accountUpdatedAt,
                          accountAvailable: account != null,
                        ),
                        if (account != null) ...<Widget>[
                          const SizedBox(height: 20),
                          Text(
                            _copy(
                              language,
                              ko: '다른 항목',
                              en: 'What differs',
                              ja: '異なる項目',
                              zhHans: '差异项目',
                              zhHant: '差異項目',
                            ),
                            style: const TextStyle(
                              color: LalaVisualColors.ink,
                              fontSize: LalaVisualTokens.sectionTitleSize,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (differences.isEmpty)
                            _AlreadyEqual(language: language)
                          else
                            ...differences.map(
                              (difference) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _DifferenceCard(
                                  difference: difference,
                                  language: language,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  _Actions(
                    language: language,
                    status: status,
                    busy: _busy,
                    accountAvailable: account != null,
                    onUseAccount: () => _run(_store.useAccountPreferences),
                    onUseDevice: () =>
                        _run(_store.saveDevicePreferencesToAccount),
                    onRetry: () => _run(_store.retryAccountSync),
                    onLater: () => context.pop(),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatusIntro extends StatelessWidget {
  const _StatusIntro({
    required this.language,
    required this.status,
    required this.accountAvailable,
  });

  final String language;
  final TravelPreferencesSyncStatus status;
  final bool accountAvailable;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, body) = switch (status) {
      TravelPreferencesSyncStatus.conflict => (
        Icons.compare_arrows_rounded,
        const Color(0xFFB45309),
        _copy(
          language,
          ko: '자동으로 덮어쓰지 않았어요',
          en: 'Nothing was overwritten',
          ja: '自動で上書きしていません',
          zhHans: '未自动覆盖任何内容',
          zhHant: '未自動覆蓋任何內容',
        ),
        _copy(
          language,
          ko: '이 기기와 계정의 설정을 비교한 뒤 유지할 기준을 선택해 주세요.',
          en: 'Compare the device and account copies, then choose what to keep.',
          ja: '端末とアカウントの設定を比較して、残す内容を選んでください。',
          zhHans: '比较设备与账号设置后，选择要保留的版本。',
          zhHant: '比較裝置與帳號設定後，選擇要保留的版本。',
        ),
      ),
      TravelPreferencesSyncStatus.synced => (
        Icons.cloud_done_outlined,
        const Color(0xFF148467),
        _copy(
          language,
          ko: '현재 설정이 같아요',
          en: 'Preferences are synchronized',
          ja: '設定は同期されています',
          zhHans: '偏好已同步',
          zhHant: '偏好已同步',
        ),
        _copy(
          language,
          ko: '기기와 계정에 같은 여행 취향이 저장되어 있어요.',
          en: 'The same travel preferences are stored on this device and account.',
          ja: '端末とアカウントに同じ旅行設定が保存されています。',
          zhHans: '设备与账号保存了相同的旅行偏好。',
          zhHant: '裝置與帳號儲存了相同的旅行偏好。',
        ),
      ),
      TravelPreferencesSyncStatus.checking => (
        Icons.sync_rounded,
        LalaVisualColors.primaryBlue,
        _copy(
          language,
          ko: '동기화 상태를 확인 중이에요',
          en: 'Checking synchronization',
          ja: '同期状態を確認しています',
          zhHans: '正在检查同步状态',
          zhHant: '正在檢查同步狀態',
        ),
        _copy(
          language,
          ko: '완료될 때까지 기기 설정은 그대로 유지됩니다.',
          en: 'Device preferences remain available while this completes.',
          ja: '完了するまで端末の設定は保持されます。',
          zhHans: '检查完成前，设备偏好仍会保留。',
          zhHant: '檢查完成前，裝置偏好仍會保留。',
        ),
      ),
      TravelPreferencesSyncStatus.error => (
        Icons.cloud_off_outlined,
        const Color(0xFFBE123C),
        _copy(
          language,
          ko: '계정 설정을 확인하지 못했어요',
          en: 'Account preferences could not be checked',
          ja: 'アカウント設定を確認できませんでした',
          zhHans: '无法检查账号偏好',
          zhHant: '無法檢查帳號偏好',
        ),
        _copy(
          language,
          ko: '기기 설정은 안전하게 남아 있어요. 연결이 돌아오면 다시 시도해 주세요.',
          en: 'Your device copy is safe. Retry when the connection is available.',
          ja: '端末の設定は保持されています。接続後に再試行してください。',
          zhHans: '设备设置仍安全保留，请在连接恢复后重试。',
          zhHant: '裝置設定仍安全保留，請在連線恢復後重試。',
        ),
      ),
      TravelPreferencesSyncStatus.serverEmpty => (
        Icons.cloud_upload_outlined,
        LalaVisualColors.primaryBlue,
        _copy(
          language,
          ko: '계정에 저장된 취향이 없어요',
          en: 'No account preferences yet',
          ja: 'アカウント設定はまだありません',
          zhHans: '账号中尚无偏好',
          zhHant: '帳號中尚無偏好',
        ),
        _copy(
          language,
          ko: '원하면 이 기기의 설정을 계정 기본값으로 저장할 수 있어요.',
          en: 'You can save this device copy as your account defaults.',
          ja: 'この端末の設定をアカウントの既定値として保存できます。',
          zhHans: '可以将此设备设置保存为账号默认值。',
          zhHant: '可以將此裝置設定儲存為帳號預設值。',
        ),
      ),
      TravelPreferencesSyncStatus.localOnly => (
        Icons.phone_iphone_outlined,
        LalaVisualColors.muted,
        _copy(
          language,
          ko: '이 기기에만 저장되어 있어요',
          en: 'Saved on this device only',
          ja: 'この端末にのみ保存されています',
          zhHans: '仅保存在此设备上',
          zhHant: '僅儲存在此裝置上',
        ),
        accountAvailable
            ? _copy(
                language,
                ko: '계정 동기화를 다시 확인해 주세요.',
                en: 'Check account synchronization again.',
                ja: 'アカウント同期を再確認してください。',
                zhHans: '请重新检查账号同步。',
                zhHant: '請重新檢查帳號同步。',
              )
            : _copy(
                language,
                ko: '로그인하면 여러 기기에서 같은 취향을 사용할 수 있어요.',
                en: 'Sign in to use the same preferences across devices.',
                ja: 'ログインすると複数端末で同じ設定を利用できます。',
                zhHans: '登录后可在多台设备上使用相同偏好。',
                zhHant: '登入後可在多台裝置上使用相同偏好。',
              ),
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(body, style: const TextStyle(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionSummary extends StatelessWidget {
  const _VersionSummary({
    required this.language,
    required this.deviceUpdatedAt,
    required this.accountUpdatedAt,
    required this.accountAvailable,
  });

  final String language;
  final String? deviceUpdatedAt;
  final String? accountUpdatedAt;
  final bool accountAvailable;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final device = _VersionCard(
        icon: Icons.phone_iphone_outlined,
        title: _copy(
          language,
          ko: '이 기기',
          en: 'This device',
          ja: 'この端末',
          zhHans: '此设备',
          zhHant: '此裝置',
        ),
        updatedAt: _dateLabel(deviceUpdatedAt, language),
      );
      final account = _VersionCard(
        icon: Icons.cloud_outlined,
        title: _copy(
          language,
          ko: 'LALA 계정',
          en: 'LALA account',
          ja: 'LALAアカウント',
          zhHans: 'LALA 账号',
          zhHant: 'LALA 帳號',
        ),
        updatedAt: accountAvailable
            ? _dateLabel(accountUpdatedAt, language)
            : _copy(
                language,
                ko: '저장된 값 없음',
                en: 'No saved copy',
                ja: '保存データなし',
                zhHans: '无已保存版本',
                zhHant: '無已儲存版本',
              ),
      );
      if (constraints.maxWidth >= 600) {
        return Row(
          children: <Widget>[
            Expanded(child: device),
            const SizedBox(width: 12),
            Expanded(child: account),
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: device),
            const SizedBox(width: 10),
            Expanded(child: account),
          ],
        ),
      );
    },
  );
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.icon,
    required this.title,
    required this.updatedAt,
  });

  final IconData icon;
  final String title;
  final String updatedAt;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: LalaVisualColors.card,
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      border: Border.all(color: LalaVisualColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: LalaVisualColors.primaryBlue, size: 22),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(
          updatedAt,
          style: const TextStyle(
            color: LalaVisualColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _DifferenceCard extends StatelessWidget {
  const _DifferenceCard({required this.difference, required this.language});

  final _PreferenceDifference difference;
  final String language;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label:
        '${difference.title}. ${_copy(language, ko: '이 기기', en: 'This device', ja: 'この端末', zhHans: '此设备', zhHant: '此裝置')}: ${difference.device}. '
        '${_copy(language, ko: '계정', en: 'Account', ja: 'アカウント', zhHans: '账号', zhHant: '帳號')}: ${difference.account}',
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LalaVisualColors.card,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        border: Border.all(
          color: difference.safetyCritical
              ? const Color(0xFFE59A35)
              : LalaVisualColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                difference.safetyCritical
                    ? Icons.health_and_safety_outlined
                    : difference.icon,
                size: 20,
                color: difference.safetyCritical
                    ? const Color(0xFFB45309)
                    : LalaVisualColors.primaryBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  difference.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (difference.safetyCritical)
                Text(
                  _copy(
                    language,
                    ko: '안전 조건',
                    en: 'Safety',
                    ja: '安全条件',
                    zhHans: '安全条件',
                    zhHant: '安全條件',
                  ),
                  style: const TextStyle(
                    color: Color(0xFFB45309),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _ComparisonRow(
            label: _copy(
              language,
              ko: '이 기기',
              en: 'This device',
              ja: 'この端末',
              zhHans: '此设备',
              zhHant: '此裝置',
            ),
            value: difference.device,
          ),
          const SizedBox(height: 8),
          _ComparisonRow(
            label: _copy(
              language,
              ko: '계정',
              en: 'Account',
              ja: 'アカウント',
              zhHans: '账号',
              zhHant: '帳號',
            ),
            value: difference.account,
          ),
        ],
      ),
    ),
  );
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: 82,
        child: Text(
          label,
          style: const TextStyle(
            color: LalaVisualColors.muted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Expanded(child: Text(value, style: const TextStyle(height: 1.4))),
    ],
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.language,
    required this.status,
    required this.busy,
    required this.accountAvailable,
    required this.onUseAccount,
    required this.onUseDevice,
    required this.onRetry,
    required this.onLater,
  });

  final String language;
  final TravelPreferencesSyncStatus status;
  final bool busy;
  final bool accountAvailable;
  final VoidCallback onUseAccount;
  final VoidCallback onUseDevice;
  final VoidCallback onRetry;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final conflict =
        status == TravelPreferencesSyncStatus.conflict && accountAvailable;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: LalaVisualColors.card,
        border: Border(top: BorderSide(color: LalaVisualColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (conflict)
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('sync-use-account'),
                    onPressed: busy ? null : onUseAccount,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, LalaVisualTokens.actionHeight),
                    ),
                    child: Text(
                      _copy(
                        language,
                        ko: '계정 값 사용',
                        en: 'Use account',
                        ja: 'アカウントを使用',
                        zhHans: '使用账号设置',
                        zhHant: '使用帳號設定',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('sync-use-device'),
                    onPressed: busy ? null : onUseDevice,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, LalaVisualTokens.actionHeight),
                    ),
                    child: Text(
                      _copy(
                        language,
                        ko: '이 기기 값 사용',
                        en: 'Use this device',
                        ja: 'この端末を使用',
                        zhHans: '使用此设备设置',
                        zhHant: '使用此裝置設定',
                      ),
                    ),
                  ),
                ),
              ],
            )
          else if (status == TravelPreferencesSyncStatus.serverEmpty)
            FilledButton.icon(
              key: const ValueKey('sync-save-device-to-account'),
              onPressed: busy ? null : onUseDevice,
              icon: const Icon(Icons.cloud_upload_outlined),
              style: FilledButton.styleFrom(
                minimumSize: const Size(
                  double.infinity,
                  LalaVisualTokens.actionHeight,
                ),
              ),
              label: Text(
                _copy(
                  language,
                  ko: '기기 취향을 계정에 저장',
                  en: 'Save device preferences to account',
                  ja: '端末設定をアカウントに保存',
                  zhHans: '将设备偏好保存到账号',
                  zhHant: '將裝置偏好儲存到帳號',
                ),
              ),
            )
          else if (status == TravelPreferencesSyncStatus.error)
            FilledButton.icon(
              key: const ValueKey('sync-retry'),
              onPressed: busy ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded),
              style: FilledButton.styleFrom(
                minimumSize: const Size(
                  double.infinity,
                  LalaVisualTokens.actionHeight,
                ),
              ),
              label: Text(
                _copy(
                  language,
                  ko: '다시 확인',
                  en: 'Retry',
                  ja: '再試行',
                  zhHans: '重试',
                  zhHant: '重試',
                ),
              ),
            ),
          if (busy) ...<Widget>[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 6),
          TextButton(
            key: const ValueKey('sync-decide-later'),
            onPressed: busy ? null : onLater,
            child: Text(
              _copy(
                language,
                ko: '나중에 결정하고 기기 설정 유지',
                en: 'Decide later and keep device copy',
                ja: '後で決めて端末設定を維持',
                zhHans: '稍后决定并保留设备设置',
                zhHant: '稍後決定並保留裝置設定',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlreadyEqual extends StatelessWidget {
  const _AlreadyEqual({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF8F3),
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.check_circle_outline, color: Color(0xFF148467)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _copy(
              language,
              ko: '비교 가능한 모든 항목이 같아요.',
              en: 'All comparable preference groups match.',
              ja: '比較可能な設定はすべて一致しています。',
              zhHans: '所有可比较的偏好项目均一致。',
              zhHant: '所有可比較的偏好項目均一致。',
            ),
          ),
        ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.error_outline, color: Color(0xFFBE123C)),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _PreferenceDifference {
  const _PreferenceDifference({
    required this.title,
    required this.icon,
    required this.device,
    required this.account,
    this.safetyCritical = false,
  });

  final String title;
  final IconData icon;
  final String device;
  final String account;
  final bool safetyCritical;
}

List<_PreferenceDifference> _preferenceDifferences(
  TravelPreferences device,
  TravelPreferences account,
  String language,
) {
  final groups = <_PreferenceDifference>[
    _PreferenceDifference(
      title: _copy(
        language,
        ko: '여행 방식',
        en: 'Travel style',
        ja: '旅行スタイル',
        zhHans: '旅行方式',
        zhHant: '旅行方式',
      ),
      icon: Icons.explore_outlined,
      device: _travelSummary(device, language),
      account: _travelSummary(account, language),
    ),
    _PreferenceDifference(
      title: _copy(
        language,
        ko: '음식과 필수 식이 조건',
        en: 'Food and required dietary needs',
        ja: '食事と必須の食事条件',
        zhHans: '饮食与必要饮食条件',
        zhHant: '飲食與必要飲食條件',
      ),
      icon: Icons.restaurant_outlined,
      device: _foodSummary(device, language),
      account: _foodSummary(account, language),
      safetyCritical: true,
    ),
    _PreferenceDifference(
      title: _copy(
        language,
        ko: '이동과 접근성',
        en: 'Mobility and accessibility',
        ja: '移動とアクセシビリティ',
        zhHans: '出行与无障碍',
        zhHant: '移動與無障礙',
      ),
      icon: Icons.accessible_forward_outlined,
      device: _mobilitySummary(device, language),
      account: _mobilitySummary(account, language),
      safetyCritical: true,
    ),
    _PreferenceDifference(
      title: _copy(
        language,
        ko: '예산과 운영 조건',
        en: 'Budget and operating conditions',
        ja: '予算と運用条件',
        zhHans: '预算与运营条件',
        zhHant: '預算與營運條件',
      ),
      icon: Icons.account_balance_wallet_outlined,
      device: _operationSummary(device, language),
      account: _operationSummary(account, language),
    ),
    _PreferenceDifference(
      title: _copy(
        language,
        ko: '도슨트와 표시 방식',
        en: 'Docent and display',
        ja: '音声ガイドと表示',
        zhHans: '导览与显示',
        zhHant: '導覽與顯示',
      ),
      icon: Icons.headphones_outlined,
      device: _contentSummary(device, language),
      account: _contentSummary(account, language),
    ),
  ];
  return groups
      .where((group) => group.device != group.account)
      .toList(growable: false);
}

String _travelSummary(TravelPreferences value, String language) => <String>[
  _enumLabel(value.pace.name, language),
  _countLabel(value.interests.length, language, 'interest'),
  _countLabel(value.travelStyles.length, language, 'style'),
  _enumLabel(value.crowdTolerance.name, language),
].join(' · ');

String _foodSummary(TravelPreferences value, String language) => <String>[
  _countLabel(value.cuisines.length, language, 'cuisine'),
  if (value.dietaryModes.isEmpty)
    _noneLabel(language)
  else
    value.dietaryModes
        .map((item) => _enumLabel(item.name, language))
        .join(', '),
  if (value.allergens.isEmpty)
    _copy(
      language,
      ko: '등록 알레르기 없음',
      en: 'No registered allergens',
      ja: '登録アレルギーなし',
      zhHans: '未登记过敏原',
      zhHant: '未登記過敏原',
    )
  else
    value.allergens.map((item) => _enumLabel(item.name, language)).join(', '),
  if (value.avoidIngredients.trim().isNotEmpty)
    _copy(
      language,
      ko: '피해야 할 재료 메모 있음',
      en: 'Avoid-ingredient note saved',
      ja: '避ける食材メモあり',
      zhHans: '已保存忌口备注',
      zhHant: '已儲存忌口備註',
    ),
].join(' · ');

String _mobilitySummary(TravelPreferences value, String language) => <String>[
  _enumLabel(value.walkingBand.name, language),
  value.transportModes
      .map((item) => _enumLabel(item.name, language))
      .join(', '),
  _copy(
    language,
    ko: '환승 최대 ${value.maxTransfers}회',
    en: 'Up to ${value.maxTransfers} transfers',
    ja: '乗換最大${value.maxTransfers}回',
    zhHans: '最多换乘 ${value.maxTransfers} 次',
    zhHant: '最多轉乘 ${value.maxTransfers} 次',
  ),
  if (value.avoidStairs) _enumLabel('avoidStairs', language),
  if (value.wheelchairAccess) _enumLabel('wheelchairAccess', language),
  if (value.strollerAccess) _enumLabel('strollerAccess', language),
].join(' · ');

String _operationSummary(TravelPreferences value, String language) => <String>[
  _enumLabel(value.budgetBand.name, language),
  _copy(
    language,
    ko: '대기 ${value.maxWaitMinutes}분',
    en: '${value.maxWaitMinutes} min wait',
    ja: '待ち時間${value.maxWaitMinutes}分',
    zhHans: '等候 ${value.maxWaitMinutes} 分钟',
    zhHant: '等候 ${value.maxWaitMinutes} 分鐘',
  ),
  _enumLabel(value.dayRhythm.name, language),
  _enumLabel(value.weatherSensitivity.name, language),
].join(' · ');

String _contentSummary(TravelPreferences value, String language) => <String>[
  _enumLabel(value.docentDepth.name, language),
  value.docentAutoplay
      ? _copy(
          language,
          ko: '자동 재생',
          en: 'Autoplay',
          ja: '自動再生',
          zhHans: '自动播放',
          zhHant: '自動播放',
        )
      : _copy(
          language,
          ko: '수동 재생',
          en: 'Manual playback',
          ja: '手動再生',
          zhHans: '手动播放',
          zhHant: '手動播放',
        ),
  _enumLabel(value.placeNameMode.name, language),
  '${value.narrationSpeed}x',
].join(' · ');

String _enumLabel(String value, String language) {
  final labels = <String, List<String>>{
    'relaxed': ['여유롭게', 'Relaxed', 'ゆったり', '悠闲', '悠閒'],
    'balanced': ['균형', 'Balanced', 'バランス', '均衡', '均衡'],
    'packed': ['알차게', 'Packed', '充実', '紧凑', '緊湊'],
    'quiet': ['한적함', 'Quiet', '静か', '安静', '安靜'],
    'popular': ['인기 장소', 'Popular', '人気', '热门', '熱門'],
    'short': ['짧게 걷기', 'Short walks', '短い徒歩', '短距离步行', '短距離步行'],
    'medium': ['보통', 'Medium', '標準', '适中', '適中'],
    'long': ['오래 걷기', 'Long walks', '長い徒歩', '长距离步行', '長距離步行'],
    'vegetarian': ['채식', 'Vegetarian', 'ベジタリアン', '素食', '素食'],
    'vegan': ['비건', 'Vegan', 'ヴィーガン', '纯素', '純素'],
    'halal': ['할랄', 'Halal', 'ハラール', '清真', '清真'],
    'kosher': ['코셔', 'Kosher', 'コーシャ', '犹太洁食', '猶太潔食'],
    'nuts': ['견과류', 'Nuts', 'ナッツ', '坚果', '堅果'],
    'shellfish': ['갑각류', 'Shellfish', '甲殻類', '甲壳类', '甲殼類'],
    'dairy': ['유제품', 'Dairy', '乳製品', '乳制品', '乳製品'],
    'eggs': ['달걀', 'Eggs', '卵', '鸡蛋', '雞蛋'],
    'gluten': ['글루텐', 'Gluten', 'グルテン', '麸质', '麩質'],
    'soy': ['대두', 'Soy', '大豆', '大豆', '大豆'],
    'walk': ['도보', 'Walk', '徒歩', '步行', '步行'],
    'transit': ['대중교통', 'Transit', '公共交通', '公共交通', '大眾運輸'],
    'taxi': ['택시', 'Taxi', 'タクシー', '出租车', '計程車'],
    'car': ['자동차', 'Car', '自動車', '驾车', '駕車'],
    'bicycle': ['자전거', 'Bicycle', '自転車', '自行车', '自行車'],
    'avoidStairs': ['계단 최소화', 'Avoid stairs', '階段を避ける', '减少楼梯', '減少樓梯'],
    'wheelchairAccess': ['휠체어', 'Wheelchair', '車いす', '轮椅', '輪椅'],
    'strollerAccess': ['유아차', 'Stroller', 'ベビーカー', '婴儿车', '嬰兒車'],
    'value': ['실속', 'Value', '節約', '实惠', '實惠'],
    'special': ['특별한 경험', 'Special', '特別', '特别体验', '特別體驗'],
    'morning': ['아침', 'Morning', '朝', '早晨', '早晨'],
    'daytime': ['낮', 'Daytime', '昼', '白天', '白天'],
    'night': ['밤', 'Night', '夜', '夜间', '夜間'],
    'low': ['낮음', 'Low', '低', '低', '低'],
    'high': ['높음', 'High', '高', '高', '高'],
    'standard': ['표준', 'Standard', '標準', '标准', '標準'],
    'deep': ['상세', 'Detailed', '詳細', '详细', '詳細'],
    'localized': ['현지어', 'Localized', '現地語', '本地化', '在地化'],
    'localizedWithKorean': [
      '현지명 병기',
      'Localized + Korean',
      '現地名併記',
      '本地名并列',
      '在地名並列',
    ],
    'korean': ['한국어 이름', 'Korean names', '韓国語名', '韩文名称', '韓文名稱'],
  };
  final values = labels[value];
  if (values == null) return value;
  final index = switch (language) {
    'ko' => 0,
    'ja' => 2,
    'zh-Hans' => 3,
    'zh-Hant' => 4,
    _ => 1,
  };
  return values[index];
}

String _countLabel(int count, String language, String kind) {
  if (kind == 'interest') {
    return _copy(
      language,
      ko: '관심사 $count개',
      en: '$count interests',
      ja: '興味 $count件',
      zhHans: '$count 个兴趣',
      zhHant: '$count 個興趣',
    );
  }
  if (kind == 'style') {
    return _copy(
      language,
      ko: '스타일 $count개',
      en: '$count styles',
      ja: 'スタイル $count件',
      zhHans: '$count 种风格',
      zhHant: '$count 種風格',
    );
  }
  return _copy(
    language,
    ko: '음식 취향 $count개',
    en: '$count cuisines',
    ja: '料理の好み $count件',
    zhHans: '$count 种饮食偏好',
    zhHant: '$count 種飲食偏好',
  );
}

String _noneLabel(String language) => _copy(
  language,
  ko: '별도 식이 방식 없음',
  en: 'No dietary mode',
  ja: '食事方式の指定なし',
  zhHans: '无特定饮食方式',
  zhHant: '無特定飲食方式',
);

String _dateLabel(String? value, String language) {
  final parsed = value == null ? null : DateTime.tryParse(value)?.toLocal();
  if (parsed == null) {
    return _copy(
      language,
      ko: '갱신 시각 미확인',
      en: 'Update time unavailable',
      ja: '更新時刻は未確認',
      zhHans: '更新时间未确认',
      zhHant: '更新時間未確認',
    );
  }
  final date =
      '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}'
      '-${parsed.day.toString().padLeft(2, '0')}';
  final time =
      '${parsed.hour.toString().padLeft(2, '0')}:'
      '${parsed.minute.toString().padLeft(2, '0')}';
  return '$date $time';
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
