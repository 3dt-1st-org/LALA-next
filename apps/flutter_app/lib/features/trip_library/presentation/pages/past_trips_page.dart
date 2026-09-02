import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// S-24: account-scoped past-plan summaries without coordinate history.
class PastTripsPage extends StatefulWidget {
  const PastTripsPage({super.key, this.tripStore});

  final TripLibraryStore? tripStore;

  @override
  State<PastTripsPage> createState() => _PastTripsPageState();
}

class _PastTripsPageState extends State<PastTripsPage> {
  late final TripLibraryStore _store;

  @override
  void initState() {
    super.initState();
    _store = widget.tripStore ?? TripLibraryStore.instance;
    unawaited(_start());
  }

  Future<void> _start() async {
    await _store.ensureLoaded();
    if (_store.accountConnected) await _store.refreshPastTrips();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (context, language, _) => AnimatedBuilder(
        animation: _store,
        builder: (context, _) => Scaffold(
          key: const ValueKey('past-trips-page'),
          backgroundColor: LalaVisualColors.surface,
          appBar: AppBar(
            backgroundColor: LalaVisualColors.surface,
            surfaceTintColor: Colors.transparent,
            title: Text(
              _copy(language, '지난 일정', 'Past trips', '過去の旅行', '历史行程', '過往行程'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: _body(context, language),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String language) {
    if (!_store.accountConnected) {
      return _MessageState(
        icon: Icons.cloud_outlined,
        title: _copy(
          language,
          '계정 연결이 필요해요.',
          'Connect an account to see past trips.',
          '過去の旅行を見るにはアカウント連携が必要です。',
          '连接账号后可查看历史行程。',
          '連結帳號後可查看過往行程。',
        ),
        detail: _copy(
          language,
          '현재 일정은 이 기기에 유지됩니다. 로그인 후 저장된 일정만 이 목록에 표시돼요.',
          'Your active plan stays on this device. This list shows plans saved after sign-in.',
          '現在の予定はこの端末に残ります。ログイン後に保存された予定のみ表示されます。',
          '当前行程仍保留在此设备，仅显示登录后保存的行程。',
          '目前行程仍保留在此裝置，只會顯示登入後儲存的行程。',
        ),
      );
    }
    final trips = _store.pastTrips;
    if (_store.syncStatus == TripLibrarySyncStatus.syncing && trips.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_store.syncStatus == TripLibrarySyncStatus.error && trips.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        title: _copy(
          language,
          '지난 일정을 불러오지 못했어요.',
          'Could not load past trips.',
          '過去の旅行を読み込めませんでした。',
          '无法加载历史行程。',
          '無法載入過往行程。',
        ),
        detail: _copy(
          language,
          '기기의 현재 일정은 그대로 유지됩니다.',
          'The current plan on this device is unchanged.',
          'この端末の現在の予定は変更されません。',
          '此设备上的当前行程不会改变。',
          '此裝置上的目前行程不會變更。',
        ),
        action: () => _store.refreshPastTrips(),
        actionLabel: _copy(language, '재시도', 'Retry', '再試行', '重试', '重試'),
      );
    }
    if (trips.isEmpty) {
      return _MessageState(
        icon: Icons.history_rounded,
        title: _copy(
          language,
          '저장된 지난 일정이 없어요.',
          'No past trips yet.',
          '保存された過去の旅行はありません。',
          '暂无已保存的历史行程。',
          '尚無已儲存的過往行程。',
        ),
        detail: _copy(
          language,
          '로그인 상태에서 만든 오늘 일정이 날짜별로 여기에 쌓입니다.',
          'Plans made while signed in appear here by date.',
          'ログイン中に作成した予定が日付別に表示されます。',
          '登录后创建的行程会按日期显示在这里。',
          '登入後建立的行程會依日期顯示於此。',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _store.refreshPastTrips,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: <Widget>[
          Text(
            _copy(
              language,
              '최신 날짜순 · 위치 좌표와 이동 기록은 저장하지 않아요.',
              'Newest first · precise coordinates and route history are not listed.',
              '新しい順・正確な座標や移動履歴は表示しません。',
              '按最新日期排序 · 不显示精确坐标或移动记录。',
              '依最新日期排序 · 不顯示精確座標或移動記錄。',
            ),
            style: const TextStyle(color: LalaVisualColors.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          for (final trip in trips) ...<Widget>[
            _PastTripCard(
              trip: trip,
              language: language,
              onOpen: () => _openTrip(context, language, trip.planDate),
              onReuse: () => _reuseTrip(context, language, trip.planDate),
              onDelete: () => _deleteTrip(context, language, trip.planDate),
            ),
            const SizedBox(height: 10),
          ],
          if (trips.length >= 20)
            OutlinedButton.icon(
              onPressed: _store.syncStatus == TripLibrarySyncStatus.syncing
                  ? null
                  : () => _store.refreshPastTrips(
                      before: trips.last.planDate,
                      append: true,
                    ),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                _copy(
                  language,
                  '더 불러오기',
                  'Load more',
                  'さらに読み込む',
                  '加载更多',
                  '載入更多',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openTrip(
    BuildContext context,
    String language,
    String planDate,
  ) async {
    final plan = await _store.loadPastPlan(planDate);
    if (!context.mounted) return;
    if (plan == null) {
      _notice(
        context,
        _copy(
          language,
          '이 일정의 상세 데이터를 사용할 수 없어요.',
          'This plan is no longer available.',
          'この予定の詳細データは利用できません。',
          '此行程的详细数据不可用。',
          '此行程的詳細資料無法使用。',
        ),
      );
      return;
    }
    context.go(LalaRoutePaths.plan);
  }

  Future<void> _reuseTrip(
    BuildContext context,
    String language,
    String sourceDate,
  ) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null || !context.mounted) return;
    final targetDate = tripLibraryDateKey(selected);
    final saved = await _store.reusePastPlan(sourceDate, targetDate);
    if (!context.mounted) return;
    _notice(
      context,
      saved
          ? _copy(
              language,
              '$targetDate 일정으로 복사했어요.',
              'Copied to $targetDate.',
              '$targetDateの予定としてコピーしました。',
              '已复制到 $targetDate 行程。',
              '已複製到 $targetDate 行程。',
            )
          : _copy(
              language,
              '일정을 복사하지 못했어요.',
              'Could not copy this plan.',
              '予定をコピーできませんでした。',
              '无法复制此行程。',
              '無法複製此行程。',
            ),
    );
  }

  Future<void> _deleteTrip(
    BuildContext context,
    String language,
    String planDate,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _copy(
            language,
            '$planDate 일정을 삭제할까요?',
            'Delete the $planDate plan?',
            '$planDateの予定を削除しますか？',
            '删除 $planDate 行程？',
            '刪除 $planDate 行程？',
          ),
        ),
        content: Text(
          _copy(
            language,
            '방문 확인과 이번 여행 설정도 함께 삭제되며 되돌릴 수 없어요.',
            'Visit outcomes and this-trip settings are also deleted and cannot be restored.',
            '訪問確認と今回の旅行設定も削除され、元に戻せません。',
            '访问结果和本次旅行设置也会删除且无法恢复。',
            '造訪結果與本次旅行設定也會刪除且無法還原。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB42318),
            ),
            child: Text(_copy(language, '삭제', 'Delete', '削除', '删除', '刪除')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store.deletePastPlan(planDate);
  }

  void _notice(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _PastTripCard extends StatelessWidget {
  const _PastTripCard({
    required this.trip,
    required this.language,
    required this.onOpen,
    required this.onReuse,
    required this.onDelete,
  });

  final PastTripSummary trip;
  final String language;
  final VoidCallback onOpen;
  final VoidCallback onReuse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: LalaVisualColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.event_available_outlined,
              color: LalaVisualColors.primaryBlue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                trip.planDate,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: _copy(
                language,
                '일정 삭제',
                'Delete plan',
                '予定を削除',
                '删除行程',
                '刪除行程',
              ),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        if (trip.region != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            trip.region!,
            style: const TextStyle(
              color: LalaVisualColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _CountChip(
              icon: Icons.view_timeline_outlined,
              text: _copy(
                language,
                '${trip.slotCount}개 슬롯',
                '${trip.slotCount} slots',
                '${trip.slotCount}枠',
                '${trip.slotCount} 个时段',
                '${trip.slotCount} 個時段',
              ),
            ),
            _CountChip(
              icon: Icons.check_circle_outline,
              text: _copy(
                language,
                '${trip.visitedCount}곳 방문',
                '${trip.visitedCount} visited',
                '${trip.visitedCount}件訪問',
                '访问 ${trip.visitedCount} 处',
                '造訪 ${trip.visitedCount} 處',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: onOpen,
                child: Text(_copy(language, '열기', 'Open', '開く', '打开', '開啟')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: onReuse,
                child: Text(
                  _copy(
                    language,
                    '다른 날짜에 재사용',
                    'Reuse',
                    '別の日に再利用',
                    '复用到其他日期',
                    '重用至其他日期',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: LalaVisualColors.primarySoft,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: LalaVisualColors.primaryBlue),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 52, color: LalaVisualColors.primaryBlue),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: LalaVisualColors.muted, height: 1.4),
          ),
          if (action != null && actionLabel != null) ...<Widget>[
            const SizedBox(height: 16),
            FilledButton(onPressed: action, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _copy(
  String language,
  String ko,
  String en,
  String ja,
  String zhHans,
  String zhHant,
) => lalaCopyMulti(
  language,
  ko: ko,
  en: en,
  ja: ja,
  zhHans: zhHans,
  zhHant: zhHant,
);
