import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../../core/backend/lala_backend.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/location/region_context.dart';
import '../../../../core/navigation/local_signal_action.dart';
import '../../../../features/location/widgets/manual_location_sheet.dart';
import '../../../../features/onboarding/onboarding_state.dart';
import '../../../../manual_location_options.dart';
import '../../../../shared/l10n/lala_copy.dart';
import '../../../../shared/widgets/lala_skeleton.dart';
import '../../domain/local_signal_aggregate.dart';
import '../../domain/local_signal_public.dart';
import '../widgets/local_signal_contribution_composer.dart';
import 'local_signal_detail_page.dart';

enum _LocalSignalsStatus { loading, loaded, empty, disabled, error }

class LocalSignalsPage extends StatefulWidget {
  const LocalSignalsPage({
    required this.backendFactory,
    required this.initialConfig,
    this.onPlaceAction,
    this.onOpenDetail,
    super.key,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final ValueChanged<LocalSignalPlaceActionRequest>? onPlaceAction;
  final ValueChanged<LocalSignalDetailArguments>? onOpenDetail;

  @override
  State<LocalSignalsPage> createState() => _LocalSignalsPageState();
}

class _LocalSignalsPageState extends State<LocalSignalsPage> {
  _LocalSignalsStatus _status = _LocalSignalsStatus.loading;
  List<LocalSignalPublicItem> _items = const <LocalSignalPublicItem>[];
  String? _nextCursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _disposed = false;
  int _requestGeneration = 0;

  // Governed aggregate read model: loaded in parallel with the feed. A failed
  // aggregate fetch degrades to "no aggregate section" — it must never break
  // the signals feed or render a fabricated aggregate.
  LocalSignalAggregates? _aggregates;
  bool _aggregatesFailed = false;

  String get _language => OnboardingState.language;

  @override
  void initState() {
    super.initState();
    RegionContextStore.listenable.addListener(_onRegionChanged);
    OnboardingState.languageListenable.addListener(_onLanguageChanged);
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    RegionContextStore.listenable.removeListener(_onRegionChanged);
    OnboardingState.languageListenable.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onRegionChanged() {
    if (_disposed) return;
    _load();
  }

  void _onLanguageChanged() {
    if (_disposed) return;
    _load();
  }

  String? get _coarseRegion {
    final context = RegionContextStore.current;
    // Current-location context carries precise coordinates and its synthetic
    // id is not a server region code. Local Signals only receives manual,
    // coarse region identifiers.
    if (context?.source == RegionSource.manual) {
      return context!.regionId;
    }
    return null;
  }

  RegionContext? get _manualRegion {
    final context = RegionContextStore.current;
    return context?.source == RegionSource.manual ? context : null;
  }

  /// F-071: the feed-level contribution entry. Policy: offered once the feed
  /// resolves to real data or an honest empty (aggregate-only included);
  /// hidden while loading (transient), on error (retry is the honest next
  /// action), and in the disabled/readiness state — that flag is externally
  /// owned and off, so inviting writes the server has not announced readiness
  /// for would end in a governed 503. Requires a detail route (always present
  /// in the app) so the button never dead-ends.
  bool get _shareEntryVisible =>
      widget.onOpenDetail != null &&
      (_status == _LocalSignalsStatus.loaded ||
          _status == _LocalSignalsStatus.empty);

  void _openContribution() {
    final manual = _manualRegion;
    widget.onOpenDetail!(
      LocalSignalDetailArguments.contribute(
        region: manual == null
            ? null
            : (code: manual.regionId, label: manual.label(_language)),
      ),
    );
  }

  Future<void> _load({bool append = false}) async {
    if (_loadingMore && append) return;
    final generation = ++_requestGeneration;
    if (!append && mounted) {
      setState(() {
        _status = _LocalSignalsStatus.loading;
        _items = const <LocalSignalPublicItem>[];
        _nextCursor = null;
        _hasMore = false;
        _loadingMore = false;
        _aggregates = null;
        _aggregatesFailed = false;
      });
    }
    if (append && mounted) setState(() => _loadingMore = true);

    final backend = widget.backendFactory(
      widget.initialConfig.copyWith(lang: _language),
    );
    // The aggregate read is best-effort alongside the feed: governance
    // flag-off and unavailable stores are honest-empty on the server, and a
    // transport failure here only hides the aggregate section. Awaiting keeps
    // both reads inside the backend's lifetime (close() runs after both).
    Future<void>? aggregatesFuture;
    if (!append) {
      aggregatesFuture = _loadAggregates(backend, generation);
    }
    try {
      final response = await backend.getLocalSignals(
        region: _coarseRegion,
        cursor: append ? _nextCursor : null,
      );
      final data = response.data;
      if (data == null) throw const FormatException('Missing feed data.');
      final feed = LocalSignalsFeed.fromJson(data);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = append
            ? <LocalSignalPublicItem>[..._items, ...feed.items]
            : feed.items;
        _nextCursor = feed.nextCursor;
        _hasMore = feed.hasMore && feed.nextCursor != null;
        _loadingMore = false;
        _status = _items.isEmpty
            ? _LocalSignalsStatus.empty
            : _LocalSignalsStatus.loaded;
      });
    } on LalaApiException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingMore = false;
        _status = error.code == 'LOCAL_SIGNALS_DISABLED'
            ? _LocalSignalsStatus.disabled
            : _LocalSignalsStatus.error;
      });
    } on Object {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _loadingMore = false;
        _status = _LocalSignalsStatus.error;
      });
    } finally {
      if (aggregatesFuture != null) {
        await aggregatesFuture;
      }
      backend.close();
    }
  }

  Future<void> _loadAggregates(dynamic backend, int generation) async {
    try {
      final response = await backend.getLocalSignalAggregates(
        weeks: 4,
        limit: 10,
        placeId: null,
        category: null,
      );
      final data = response.data;
      if (data == null) throw const FormatException('Missing aggregates data.');
      final aggregates = LocalSignalAggregates.fromJson(data);
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _aggregates = aggregates);
    } on Object {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _aggregatesFailed = true);
    }
  }

  Future<void> _openRegionPicker() async {
    final selected = await showModalBottomSheet<ManualLocationOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualLocationSheet(language: _language),
    );
    if (selected != null && mounted) {
      await RegionContextStore.setAndFlush(RegionContext.manual(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = _language;
    final activeRegion = RegionContextStore.current;
    final regionLabel = activeRegion?.source == RegionSource.manual
        ? activeRegion!.label(language)
        : lalaCopyMulti(
            language,
            ko: '전국',
            en: 'Nationwide',
            ja: '全国',
            zhHans: '全国',
            zhHant: '全國',
          );
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: _Header(
                    language: language,
                    regionLabel: regionLabel,
                    onChooseRegion: _openRegionPicker,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: _contentSliver(language),
              ),
              if (_shareEntryVisible)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  sliver: SliverToBoxAdapter(
                    child: LocalSignalContributionEntry(
                      entryKey: const ValueKey(
                        'local-signals-contribution-entry',
                      ),
                      buttonKey: const ValueKey(
                        'local-signals-share-experience',
                      ),
                      language: language,
                      // Auth state is unknown on this page; the entry copy
                      // stays sign-in-honest for both guests and users.
                      authenticated: null,
                      contextLabel: _manualRegion?.label(language),
                      onPressed: _openContribution,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contentSliver(String language) {
    switch (_status) {
      case _LocalSignalsStatus.loading:
        return const SliverToBoxAdapter(child: _LoadingState());
      case _LocalSignalsStatus.disabled:
        return SliverToBoxAdapter(child: _DisabledState(language: language));
      case _LocalSignalsStatus.error:
        return SliverToBoxAdapter(
          child: _ErrorState(language: language, onRetry: () => _load()),
        );
      case _LocalSignalsStatus.empty:
        // Honest empty feed + governed aggregates when approved data exists:
        // the aggregate section stands on its own truth, clearly labeled as
        // system aggregates rather than user posts.
        if (_aggregates case final aggregates? when aggregates.available) {
          return SliverMainAxisGroup(
            slivers: <Widget>[
              _aggregatesSliver(language, aggregates),
              SliverToBoxAdapter(child: _EmptyState(language: language)),
            ],
          );
        }
        return SliverToBoxAdapter(child: _EmptyState(language: language));
      case _LocalSignalsStatus.loaded:
        // available=false means the governed read model honestly has no
        // aggregate rows — no section at all (header would crash on
        // items.first and an empty section is not honest data).
        if (_aggregates case final aggregates? when aggregates.available) {
          return SliverMainAxisGroup(
            slivers: <Widget>[
              _aggregatesSliver(language, aggregates),
              _signalsList(language),
            ],
          );
        }
        if (_aggregatesFailed) {
          return SliverMainAxisGroup(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _AggregatesUnavailable(language: language),
              ),
              _signalsList(language),
            ],
          );
        }
        return _signalsList(language);
    }
  }

  SliverList _signalsList(String language) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index < _items.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SignalCard(
              key: ValueKey('local-signal-${_items[index].id}'),
              signal: _items[index],
              language: language,
              onPlaceAction: widget.onPlaceAction,
              onOpenDetail: widget.onOpenDetail,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: Center(
            child: _loadingMore
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : OutlinedButton(
                    key: const ValueKey('local-signals-load-more'),
                    onPressed: _hasMore ? () => _load(append: true) : null,
                    child: Text(
                      lalaCopyMulti(
                        language,
                        ko: '더 보기',
                        en: 'Load more',
                        ja: 'もっと見る',
                        zhHans: '加载更多',
                        zhHant: '載入更多',
                      ),
                    ),
                  ),
          ),
        );
      }, childCount: _items.length + (_hasMore ? 1 : 0)),
    );
  }

  /// Aggregate section: only rendered when the governed read model returned
  /// available data. Provenance + freshness are always shown so a reader
  /// cannot mistake these for user posts; place/plan actions reuse the same
  /// callbacks as signal cards.
  Widget _aggregatesSliver(String language, LocalSignalAggregates aggregates) {
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AggregatesHeader(
                language: language,
                aggregates: aggregates,
              ),
            );
          }
          final aggregate = aggregates.items[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AggregateCard(
              key: ValueKey(
                'local-signal-aggregate-${aggregate.placeId ?? aggregate.placeNameKo}-${aggregate.weekStart}',
              ),
              aggregate: aggregate,
              aggregateEnvelope: aggregates,
              language: language,
              onPlaceAction: widget.onPlaceAction,
              onOpenDetail: widget.onOpenDetail,
            ),
          );
        }, childCount: 1 + aggregates.items.length),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.language,
    required this.regionLabel,
    required this.onChooseRegion,
  });

  final String language;
  final String regionLabel;
  final VoidCallback onChooseRegion;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          lalaCopyMulti(
            language,
            ko: '로컬 신호',
            en: 'Local Signals',
            ja: 'ローカル信号',
            zhHans: '本地信号',
            zhHant: '在地訊號',
          ),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          lalaCopyMulti(
            language,
            ko: '장소와 지역에 연결된 짧고 날짜가 명확한 관찰을 모아요.',
            en: 'Short, dated observations connected to places and areas.',
            ja: 'スポットや地域に結びついた、短く日付の明確な観察を集めます。',
            zhHans: '汇集与地点和地区相关的简短、日期明确的观察。',
            zhHant: '彙集與地點和地區相關的簡短、日期明確的觀察。',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('local-signals-region-picker'),
                onPressed: onChooseRegion,
                icon: const Icon(Icons.location_on_outlined, size: 18),
                label: Text(regionLabel),
              ),
            ),
            const SizedBox(width: 8),
            Chip(
              avatar: const Icon(Icons.visibility_outlined, size: 16),
              label: Text(
                lalaCopyMulti(
                  language,
                  ko: '공개 읽기',
                  en: 'Public reading',
                  ja: '公開読み取り',
                  zhHans: '公开阅读',
                  zhHant: '公開閱讀',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('local-signals-loading'),
      children: List<Widget>.generate(
        3,
        (index) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LalaSkeletonLine(width: 110, height: 14),
                  SizedBox(height: 12),
                  LalaSkeletonLine(width: double.infinity, height: 18),
                  SizedBox(height: 8),
                  LalaSkeletonLine(width: 220, height: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DisabledState extends StatelessWidget {
  const _DisabledState({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) => _StatusCard(
    key: const ValueKey('local-signals-disabled'),
    icon: Icons.pause_circle_outline,
    title: lalaCopyMulti(
      language,
      ko: '로컬 신호를 준비 중이에요',
      en: 'Local Signals is not ready',
      ja: 'ローカル信号を準備中です',
      zhHans: '本地信号准备中',
      zhHant: '在地訊號準備中',
    ),
    message: lalaCopyMulti(
      language,
      ko: '현재 공개 데이터가 없어 보여드릴 수 없어요. 준비되면 이 화면에 공개 신호만 표시합니다.',
      en: 'There is no public data available right now. Published signals will appear here when ready.',
      ja: '現在公開できるデータがありません。準備が整い次第、公開シグナルのみをここに表示します。',
      zhHans: '当前没有可公开的数据。就绪后将仅在此显示已发布的信号。',
      zhHant: '當前沒有可公開的資料。就緒後將僅在此顯示已發布的訊號。',
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) => _StatusCard(
    key: const ValueKey('local-signals-empty'),
    icon: Icons.inbox_outlined,
    title: lalaCopyMulti(
      language,
      ko: '아직 공개 신호가 없어요',
      en: 'No public signals yet',
      ja: 'まだ公開シグナルがありません',
      zhHans: '暂无公开信号',
      zhHant: '暫無公開訊號',
    ),
    message: lalaCopyMulti(
      language,
      ko: '다른 지역을 선택하거나 나중에 다시 확인해 주세요.',
      en: 'Choose another area or check again later.',
      ja: '別の地域を選ぶか、後でもう一度ご確認ください。',
      zhHans: '请选择其他地区或稍后再查看。',
      zhHant: '請選擇其他地區或稍後再查看。',
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.language, required this.onRetry});

  final String language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _StatusCard(
    key: const ValueKey('local-signals-error'),
    icon: Icons.cloud_off_outlined,
    title: lalaCopyMulti(
      language,
      ko: '로컬 신호를 불러오지 못했어요',
      en: 'Could not load Local Signals',
      ja: 'ローカル信号を読み込めませんでした',
      zhHans: '无法加载本地信号',
      zhHant: '無法載入在地訊號',
    ),
    message: lalaCopyMulti(
      language,
      ko: '잠시 후 다시 시도해 주세요.',
      en: 'Please try again in a moment.',
      ja: 'しばらくしてからもう一度お試しください。',
      zhHans: '请稍后重试。',
      zhHant: '請稍後重試。',
    ),
    action: TextButton(
      onPressed: onRetry,
      child: Text(
        lalaCopyMulti(
          language,
          ko: '다시 시도',
          en: 'Try again',
          ja: '再試行',
          zhHans: '重试',
          zhHant: '重試',
        ),
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...<Widget>[const SizedBox(height: 8), action!],
        ],
      ),
    ),
  );
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.signal,
    required this.language,
    required this.onPlaceAction,
    required this.onOpenDetail,
    super.key,
  });

  final LocalSignalPublicItem signal;
  final String language;
  final ValueChanged<LocalSignalPlaceActionRequest>? onPlaceAction;
  final ValueChanged<LocalSignalDetailArguments>? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = <String>[
      signal.kind.label(language),
      if (signal.localityCode != null) signal.localityCode!,
      if (_dateLabel(signal.observationDate ?? signal.publishedAt) != null)
        _dateLabel(signal.observationDate ?? signal.publishedAt)!,
    ];
    if (signal.translationAvailable) {
      metadata.add(
        lalaCopyMulti(
          language,
          ko: '번역 제공',
          en: 'Translated view',
          ja: '翻訳表示',
          zhHans: '翻译显示',
          zhHant: '翻譯顯示',
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              metadata.join(' · '),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              signal.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(signal.body, style: theme.textTheme.bodyMedium),
            if (signal.commercialDisclosure !=
                LocalSignalCommercialDisclosure.none) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                signal.commercialDisclosure.label(language),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (onOpenDetail != null) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  key: ValueKey('local-signal-detail-${signal.id}'),
                  onPressed: () =>
                      onOpenDetail!(LocalSignalDetailArguments.public(signal)),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(
                    lalaCopyMulti(
                      language,
                      ko: '신호 자세히 보기',
                      en: 'Open signal detail',
                      ja: 'シグナルの詳細を見る',
                      zhHans: '查看信号详情',
                      zhHant: '查看訊號詳情',
                    ),
                  ),
                ),
              ),
            ],
            if (signal.placeLinks.isNotEmpty && onPlaceAction != null) ...[
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: ValueKey('local-signal-place-action-${signal.id}'),
                    onPressed: () => onPlaceAction!(
                      LocalSignalPlaceActionRequest(
                        placeId: signal.placeLinks.first.placeId,
                        action: LocalSignalPlaceAction.viewPlace,
                      ),
                    ),
                    icon: const Icon(Icons.place_outlined, size: 18),
                    label: Text(
                      lalaCopyMulti(
                        language,
                        ko: '장소 보기',
                        en: 'View place',
                        ja: 'スポットを見る',
                        zhHans: '查看地点',
                        zhHant: '查看地點',
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: ValueKey('local-signal-plan-action-${signal.id}'),
                    onPressed: () => onPlaceAction!(
                      LocalSignalPlaceActionRequest(
                        placeId: signal.placeLinks.first.placeId,
                        action: LocalSignalPlaceAction.addToPlan,
                      ),
                    ),
                    icon: const Icon(Icons.route_outlined, size: 18),
                    label: Text(
                      lalaCopyMulti(
                        language,
                        ko: '일정에서 보기',
                        en: 'Open plan',
                        ja: 'プランで見る',
                        zhHans: '在计划中查看',
                        zhHant: '在計畫中查看',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _dateLabel(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}-$month-$day';
}

class _AggregatesHeader extends StatelessWidget {
  const _AggregatesHeader({required this.language, required this.aggregates});

  final String language;
  final LocalSignalAggregates aggregates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.insights_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                lalaCopyMulti(
                  language,
                  ko: '이번 달 로컬 관심 지표',
                  en: 'Local interest this month',
                  ja: '今月のローカル注目度',
                  zhHans: '本月本地关注指标',
                  zhHant: '本月在地關注指標',
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Honest provenance: aggregated review mentions (system data), with
        // the aggregation date — never presented as user posts.
        Text(
          '${aggregates.items.first.providerLabel(language)} · ${aggregates.freshnessLabel(language)}',
          key: const ValueKey('local-signals-aggregates-provenance'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AggregateCard extends StatelessWidget {
  const _AggregateCard({
    required this.aggregate,
    required this.aggregateEnvelope,
    required this.language,
    required this.onPlaceAction,
    required this.onOpenDetail,
    super.key,
  });

  final LocalSignalPlaceAggregate aggregate;
  final LocalSignalAggregates aggregateEnvelope;
  final String language;
  final ValueChanged<LocalSignalPlaceActionRequest>? onPlaceAction;
  final ValueChanged<LocalSignalDetailArguments>? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPlace = aggregate.placeId != null && onPlaceAction != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    aggregate.placeNameKo,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  lalaCopyMulti(
                    language,
                    ko: '언급 ${aggregate.mentionCount}건',
                    en: '${aggregate.mentionCount} mentions',
                    ja: '言及${aggregate.mentionCount}件',
                    zhHans: '${aggregate.mentionCount} 次提及',
                    zhHant: '${aggregate.mentionCount} 次提及',
                  ),
                  key: ValueKey(
                    'local-signal-aggregate-count-${aggregate.placeNameKo}',
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              // Provenance lives in the section header once; the card shows
              // only its aggregation window.
              '${aggregate.weekStart} ~ ${aggregate.weekEnd}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasPlace)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: ValueKey(
                        'local-signal-aggregate-place-${aggregate.placeId}',
                      ),
                      onPressed: () => onPlaceAction!(
                        LocalSignalPlaceActionRequest(
                          placeId: aggregate.placeId!,
                          action: LocalSignalPlaceAction.viewPlace,
                        ),
                      ),
                      icon: const Icon(Icons.place_outlined, size: 18),
                      label: Text(
                        lalaCopyMulti(
                          language,
                          ko: '장소 보기',
                          en: 'View place',
                          ja: 'スポットを見る',
                          zhHans: '查看地点',
                          zhHant: '查看地點',
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: ValueKey(
                        'local-signal-aggregate-plan-${aggregate.placeId}',
                      ),
                      onPressed: () => onPlaceAction!(
                        LocalSignalPlaceActionRequest(
                          placeId: aggregate.placeId!,
                          action: LocalSignalPlaceAction.addToPlan,
                        ),
                      ),
                      icon: const Icon(Icons.route_outlined, size: 18),
                      label: Text(
                        lalaCopyMulti(
                          language,
                          ko: '일정에서 보기',
                          en: 'Open plan',
                          ja: 'プランで見る',
                          zhHans: '在计划中查看',
                          zhHant: '在計畫中查看',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (onOpenDetail != null)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  key: ValueKey(
                    'local-signal-aggregate-detail-${aggregate.placeId ?? aggregate.placeNameKo}',
                  ),
                  onPressed: () => onOpenDetail!(
                    LocalSignalDetailArguments.aggregate(
                      aggregate,
                      aggregateEnvelope,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(
                    lalaCopyMulti(
                      language,
                      ko: '집계 자세히 보기',
                      en: 'Open aggregate detail',
                      ja: '集計の詳細を見る',
                      zhHans: '查看汇总详情',
                      zhHant: '查看彙總詳情',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AggregatesUnavailable extends StatelessWidget {
  const _AggregatesUnavailable({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              // Honest unavailable: the aggregate read failed, so the section
              // is explicitly not shown rather than silently hidden or faked.
              lalaCopyMulti(
                language,
                ko: '집계 지표를 지금 불러올 수 없어요',
                en: 'Aggregated stats are unavailable right now',
                ja: '集計指標を現在読み込めません',
                zhHans: '暂时无法加载汇总指标',
                zhHant: '暫時無法載入彙總指標',
              ),
              key: const ValueKey('local-signals-aggregates-unavailable'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
