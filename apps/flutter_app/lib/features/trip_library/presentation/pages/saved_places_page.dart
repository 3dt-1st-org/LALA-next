import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/place/place_helpers.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';
import 'package:lala_next_app/shared/labels/source_label.dart';

enum _SavedProjectionStatus { loading, ready, error }

/// S-23: device-first saved IDs projected through current public place data.
class SavedPlacesPage extends StatefulWidget {
  const SavedPlacesPage({
    super.key,
    required this.backendFactory,
    required this.initialConfig,
    required this.actionController,
    this.tripStore,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LocalSignalActionController actionController;
  final TripLibraryStore? tripStore;

  @override
  State<SavedPlacesPage> createState() => _SavedPlacesPageState();
}

class _SavedPlacesPageState extends State<SavedPlacesPage> {
  late final TripLibraryStore _tripStore;
  _SavedProjectionStatus _status = _SavedProjectionStatus.loading;
  Map<String, LalaPlace> _places = const <String, LalaPlace>{};
  String _category = 'all';
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _tripStore = widget.tripStore ?? TripLibraryStore.instance;
    SavedPlaceStore.listenable.addListener(_savedChanged);
    OnboardingState.languageListenable.addListener(_savedChanged);
    RegionContextStore.listenable.addListener(_savedChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _loadEpoch += 1;
    SavedPlaceStore.listenable.removeListener(_savedChanged);
    OnboardingState.languageListenable.removeListener(_savedChanged);
    RegionContextStore.listenable.removeListener(_savedChanged);
    super.dispose();
  }

  void _savedChanged() {
    if (mounted) unawaited(_load());
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    final ids = SavedPlaceStore.current;
    if (mounted) setState(() => _status = _SavedProjectionStatus.loading);
    if (ids.isEmpty) {
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          _places = const <String, LalaPlace>{};
          _status = _SavedProjectionStatus.ready;
        });
      }
      return;
    }
    final region = RegionContextStore.current;
    final config = widget.initialConfig.copyWith(
      lat: region?.lat ?? widget.initialConfig.lat,
      lng: region?.lng ?? widget.initialConfig.lng,
      category: 'all',
      lang: OnboardingState.language,
      placeLimit: 100,
    );
    final backend = widget.backendFactory(config);
    try {
      final response = await backend.getPlaces();
      final data = response.data;
      if (!response.ok || data == null) {
        throw StateError('projection unavailable');
      }
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _places = <String, LalaPlace>{
          for (final place in data.places)
            if (ids.contains(place.placeId)) place.placeId: place,
        };
        _status = _SavedProjectionStatus.ready;
      });
    } on Object {
      if (mounted && epoch == _loadEpoch) {
        setState(() => _status = _SavedProjectionStatus.error);
      }
    } finally {
      backend.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (context, language, _) => Scaffold(
        key: const ValueKey('saved-places-page'),
        backgroundColor: LalaVisualColors.surface,
        appBar: AppBar(
          backgroundColor: LalaVisualColors.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            _copy(
              language,
              '저장한 장소',
              'Saved places',
              '保存した場所',
              '已保存地点',
              '已儲存地點',
            ),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: <Widget>[
            AnimatedBuilder(
              animation: _tripStore,
              builder: (context, _) => Tooltip(
                message: _syncLabel(_tripStore.syncStatus, language),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(
                    _tripStore.syncStatus == TripLibrarySyncStatus.synced
                        ? Icons.cloud_done_outlined
                        : Icons.phone_iphone_rounded,
                    color: LalaVisualColors.primaryBlue,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: _body(context, language),
      ),
    );
  }

  Widget _body(BuildContext context, String language) {
    final ids = SavedPlaceStore.current.toList()..sort();
    if (_status == _SavedProjectionStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ids.isEmpty) {
      return _EmptyState(
        language: language,
        icon: Icons.bookmark_border_rounded,
        title: _copy(
          language,
          '저장한 장소가 없어요.',
          'No saved places yet.',
          '保存した場所はありません。',
          '暂无已保存地点。',
          '尚無已儲存地點。',
        ),
        detail: _copy(
          language,
          '장소 상세에서 저장하면 여기에 모아 볼 수 있어요.',
          'Save a place from its details to collect it here.',
          '場所の詳細から保存すると、ここで確認できます。',
          '在地点详情中保存后可在此查看。',
          '在地點詳情中儲存後可在此查看。',
        ),
      );
    }
    final categories =
        _places.values.map((place) => place.category).toSet().toList()..sort();
    final visibleIds = ids
        .where((id) {
          if (_category == 'all') return true;
          return _places[id]?.category == _category;
        })
        .toList(growable: false);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: <Widget>[
          Text(
            _copy(
              language,
              '현재 선택 지역의 공개 정보로 장소 상태를 다시 확인합니다.',
              'Place status is refreshed from public data for your selected region.',
              '選択地域の公開情報で場所の状態を再確認します。',
              '使用当前所选地区的公开信息更新地点状态。',
              '使用目前所選地區的公開資訊更新地點狀態。',
            ),
            style: const TextStyle(color: LalaVisualColors.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                ChoiceChip(
                  label: Text(_copy(language, '전체', 'All', 'すべて', '全部', '全部')),
                  selected: _category == 'all',
                  onSelected: (_) => setState(() => _category = 'all'),
                ),
                for (final category in categories) ...<Widget>[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(categoryLabel(category, language: language)),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
                ],
              ],
            ),
          ),
          if (_status == _SavedProjectionStatus.error) ...<Widget>[
            const SizedBox(height: 12),
            _InlineNotice(
              language: language,
              onRetry: _load,
              text: _copy(
                language,
                '최신 장소 정보를 불러오지 못했어요. 저장 항목은 그대로 유지됩니다.',
                'Current place details are unavailable. Saved items are preserved.',
                '最新の場所情報を取得できません。保存項目は維持されます。',
                '无法加载最新地点信息，已保存项目仍会保留。',
                '無法載入最新地點資訊，已儲存項目仍會保留。',
              ),
            ),
          ],
          const SizedBox(height: 14),
          for (final id in visibleIds) ...<Widget>[
            _SavedPlaceCard(
              placeId: id,
              place: _places[id],
              language: language,
              onOpen: _places[id] == null
                  ? null
                  : () => context.push(
                      LalaRoutePaths.placeDetailFor(id),
                      extra: _places[id],
                    ),
              onMap: _places[id] == null
                  ? null
                  : () {
                      SelectedPlaceStore.set(id);
                      context.go(LalaRoutePaths.mapRoute);
                    },
              onPlan: _places[id] == null
                  ? null
                  : () {
                      widget.actionController.dispatch(
                        LocalSignalPlaceActionRequest(
                          placeId: id,
                          action: LocalSignalPlaceAction.addToPlan,
                        ),
                      );
                      context.go(LalaRoutePaths.mapRoute);
                    },
              onRemove: () => _confirmRemove(context, language, id),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    String language,
    String placeId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _copy(
            language,
            '저장에서 삭제할까요?',
            'Remove saved place?',
            '保存から削除しますか？',
            '从已保存中移除？',
            '從已儲存中移除？',
          ),
        ),
        content: Text(
          _copy(
            language,
            '일정 기록은 삭제되지 않습니다.',
            'Past trip records are not deleted.',
            '過去の旅行記録は削除されません。',
            '不会删除历史行程记录。',
            '不會刪除過往行程記錄。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_copy(language, '삭제', 'Remove', '削除', '移除', '移除')),
          ),
        ],
      ),
    );
    if (confirmed == true) SavedPlaceStore.remove(placeId);
  }
}

class _SavedPlaceCard extends StatelessWidget {
  const _SavedPlaceCard({
    required this.placeId,
    required this.place,
    required this.language,
    required this.onOpen,
    required this.onMap,
    required this.onPlan,
    required this.onRemove,
  });

  final String placeId;
  final LalaPlace? place;
  final String language;
  final VoidCallback? onOpen;
  final VoidCallback? onMap;
  final VoidCallback? onPlan;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final current = place;
    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: LalaVisualColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  current == null
                      ? Icons.cloud_off_outlined
                      : Icons.place_outlined,
                  color: LalaVisualColors.primaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      current == null
                          ? _copy(
                              language,
                              '현재 정보를 확인할 수 없는 장소',
                              'Place details currently unavailable',
                              '現在情報を確認できない場所',
                              '当前无法确认信息的地点',
                              '目前無法確認資訊的地點',
                            )
                          : placeDisplayName(current, language),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      current == null
                          ? _copy(
                              language,
                              '저장 ID는 유지되며 다시 불러올 수 있어요.',
                              'The saved ID is retained for a later refresh.',
                              '保存IDは維持され、後で再取得できます。',
                              '保存 ID 会保留，可稍后刷新。',
                              '儲存 ID 會保留，可稍後重新整理。',
                            )
                          : '${categoryLabel(current.category, language: language)} · ${sourceLabel(current.source, language: language)}',
                      style: const TextStyle(
                        color: LalaVisualColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _copy(
                  language,
                  '저장에서 삭제',
                  'Remove saved place',
                  '保存から削除',
                  '移除已保存地点',
                  '移除已儲存地點',
                ),
                onPressed: onRemove,
                icon: const Icon(Icons.bookmark_remove_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(_copy(language, '상세', 'Details', '詳細', '详情', '詳情')),
              ),
              OutlinedButton.icon(
                onPressed: onMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(_copy(language, '지도', 'Map', '地図', '地图', '地圖')),
              ),
              FilledButton.icon(
                onPressed: onPlan,
                icon: const Icon(Icons.playlist_add_rounded),
                label: Text(
                  _copy(
                    language,
                    '일정에 추가',
                    'Add to plan',
                    '予定に追加',
                    '加入行程',
                    '加入行程',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.language,
    required this.onRetry,
    required this.text,
  });

  final String language;
  final VoidCallback onRetry;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    color: const Color(0xFFFFF7ED),
    child: Row(
      children: <Widget>[
        const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309)),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
        TextButton(
          onPressed: onRetry,
          child: Text(_copy(language, '재시도', 'Retry', '再試行', '重试', '重試')),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.language,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final String language;
  final IconData icon;
  final String title;
  final String detail;

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
        ],
      ),
    ),
  );
}

String _syncLabel(TripLibrarySyncStatus status, String language) =>
    switch (status) {
      TripLibrarySyncStatus.synced => _copy(
        language,
        '계정과 동기화됨',
        'Synced to account',
        'アカウントと同期済み',
        '已同步到账号',
        '已同步至帳號',
      ),
      TripLibrarySyncStatus.syncing => _copy(
        language,
        '동기화 중',
        'Syncing',
        '同期中',
        '同步中',
        '同步中',
      ),
      TripLibrarySyncStatus.conflict => _copy(
        language,
        '동기화 충돌',
        'Sync conflict',
        '同期の競合',
        '同步冲突',
        '同步衝突',
      ),
      TripLibrarySyncStatus.error => _copy(
        language,
        '기기에 저장됨 · 동기화 필요',
        'Saved on device · sync needed',
        '端末に保存・同期が必要',
        '已保存到设备 · 需同步',
        '已儲存到裝置 · 需同步',
      ),
      TripLibrarySyncStatus.localOnly => _copy(
        language,
        '이 기기에 저장됨',
        'Saved on this device',
        'この端末に保存',
        '已保存到此设备',
        '已儲存到此裝置',
      ),
    };

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
