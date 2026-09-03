import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/place/widgets/featured_place_header.dart';
import 'package:lala_next_app/features/place/widgets/place_context_card.dart';
import 'package:lala_next_app/features/place/widgets/public_data_proof_row.dart';
import 'package:lala_next_app/features/place/widgets/signal_grid.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_entry_card.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_sheet.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/labels/dataset_freshness_label.dart';
import 'package:lala_next_app/shared/labels/source_label.dart';

/// S-12: a standalone canonical place route.
///
/// The selected real place is normally supplied in [initialPlace]. A direct
/// link without route state performs one bounded `/places` lookup and accepts
/// only an exact canonical ID match.
class PlaceDetailPage extends StatefulWidget {
  const PlaceDetailPage({
    super.key,
    required this.placeId,
    required this.backendFactory,
    required this.initialConfig,
    required this.actionController,
    required this.docentExperienceController,
    this.initialPlace,
    this.preferencesStore,
  });

  final String placeId;
  final LalaPlace? initialPlace;
  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LocalSignalActionController actionController;
  final DocentExperienceController docentExperienceController;
  final TravelPreferencesStore? preferencesStore;

  @override
  State<PlaceDetailPage> createState() => _PlaceDetailPageState();
}

class _PlaceDetailPageState extends State<PlaceDetailPage> {
  LalaPlace? _place;
  LalaWeather? _weather;
  String? _source;
  String? _dataAsOf;
  String? _contextError;
  bool _loading = true;
  bool _unavailable = false;
  bool _showEvidence = false;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPlace;
    if (initial != null && initial.placeId == widget.placeId) {
      _place = initial;
      _source = initial.source;
      _loading = false;
    }
    OnboardingState.languageListenable.addListener(_handleLanguageChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _loadEpoch += 1;
    OnboardingState.languageListenable.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    unawaited(_load(refreshPlace: widget.initialPlace == null));
  }

  Future<void> _load({bool refreshPlace = true}) async {
    final epoch = ++_loadEpoch;
    final language = OnboardingState.language;
    final existing = _place;
    if (mounted) {
      setState(() {
        _loading = existing == null;
        _contextError = null;
        _unavailable = false;
      });
    }

    LalaPlace? place = existing;
    var source = _source;
    var dataAsOf = _dataAsOf;
    LalaBackend? lookupBackend;
    LalaBackend? contextBackend;
    try {
      if (place == null || refreshPlace) {
        lookupBackend = widget.backendFactory(
          widget.initialConfig.copyWith(category: 'all', lang: language),
        );
        final response = await lookupBackend.getPlaces();
        final payload = response.data;
        if (!response.ok || payload == null) {
          throw StateError('place lookup unavailable');
        }
        final matches = payload.places.where(
          (candidate) => candidate.placeId == widget.placeId,
        );
        if (matches.isNotEmpty) {
          place = matches.first;
          source = payload.source;
          dataAsOf = payload.dataAsOf;
        } else if (existing == null) {
          if (!mounted || epoch != _loadEpoch) return;
          setState(() {
            _loading = false;
            _unavailable = true;
          });
          return;
        }
      }

      if (place == null) return;
      contextBackend = widget.backendFactory(
        widget.initialConfig.copyWith(
          lat: place.lat,
          lng: place.lng,
          category: 'all',
          lang: language,
        ),
      );
      LalaWeather? weather;
      try {
        final weatherResponse = await contextBackend.getWeather();
        if (weatherResponse.ok) {
          weather = weatherResponse.data;
        }
      } on Object {
        // Place detail remains useful without transient weather context.
      }
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _place = place;
        _weather = weather;
        _source = source;
        _dataAsOf = dataAsOf;
        _loading = false;
        _unavailable = false;
      });
    } on Object {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _loading = false;
        if (existing == null) {
          _contextError = lalaCopyMulti(
            language,
            ko: '장소 정보를 불러오지 못했어요.',
            en: 'Could not load this place.',
            ja: 'スポット情報を読み込めませんでした。',
            zhHans: '无法加载地点信息。',
            zhHant: '無法載入地點資訊。',
          );
        } else {
          _contextError = lalaCopyMulti(
            language,
            ko: '최신 날씨와 출처 정보를 확인하지 못했어요.',
            en: 'Latest weather and source context is unavailable.',
            ja: '最新の天気と出典情報を確認できませんでした。',
            zhHans: '无法确认最新天气和来源信息。',
            zhHant: '無法確認最新天氣與來源資訊。',
          );
        }
      });
    } finally {
      lookupBackend?.close();
      contextBackend?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: OnboardingState.languageListenable,
      builder: (context, language, _) {
        return Scaffold(
          key: const ValueKey('place-detail-page'),
          backgroundColor: LalaVisualColors.surface,
          appBar: AppBar(
            backgroundColor: LalaVisualColors.surface,
            surfaceTintColor: Colors.transparent,
            title: Text(
              lalaCopyMulti(
                language,
                ko: '장소 상세',
                en: 'Place details',
                ja: 'スポット詳細',
                zhHans: '地点详情',
                zhHant: '地點詳情',
              ),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: SafeArea(top: false, child: _buildBody(context, language)),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, String language) {
    if (_loading && _place == null) {
      // Why: a bare spinner is invisible to screen readers; announce the
      // loading state in the active locale (same contract as the map chrome).
      return Center(
        child: Semantics(
          container: true,
          label: lalaCopyMulti(
            language,
            ko: '장소 정보를 불러오는 중',
            en: 'Loading place details',
            ja: 'スポット情報を読み込み中',
            zhHans: '正在加载地点信息',
            zhHant: '正在載入地點資訊',
          ),
          child: const CircularProgressIndicator(
            key: ValueKey('place-detail-loading'),
          ),
        ),
      );
    }
    if (_unavailable) {
      return _PlaceUnavailable(
        language: language,
        onMap: () => context.go(LalaRoutePaths.mapRoute),
      );
    }
    final place = _place;
    if (place == null) {
      return _PlaceLoadError(
        language: language,
        message: _contextError,
        onRetry: _load,
      );
    }

    final source = _source ?? place.source;
    final freshness = datasetFreshnessLabel(_dataAsOf, language);
    final score = place.score;
    final components = score?.components;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: SavedPlaceStore.listenable,
      builder: (context, savedIds, _) {
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const ValueKey('place-detail-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              LalaVisualTokens.pageGutter,
              8,
              LalaVisualTokens.pageGutter,
              30,
            ),
            children: <Widget>[
              FeaturedPlaceHeader(
                place: place,
                language: language,
                showEvidence: _showEvidence,
                saved: savedIds.contains(place.placeId),
                onToggleSaved: () => SavedPlaceStore.toggle(place.placeId),
              ),
              const SizedBox(height: 12),
              if (_contextError != null) ...<Widget>[
                _ContextNotice(message: _contextError!),
                const SizedBox(height: 12),
              ],
              _PlaceActions(
                language: language,
                onAddToPlan: () =>
                    _handoffToMap(place, LocalSignalPlaceAction.addToPlan),
                onDocent: () {
                  SelectedPlaceStore.set(place.placeId);
                  unawaited(widget.docentExperienceController.playPlace(place));
                  context.push(LalaRoutePaths.docentPlayer);
                },
                onMap: () =>
                    _handoffToMap(place, LocalSignalPlaceAction.viewPlace),
                onRestaurantHelp: place.category.toLowerCase() == 'restaurant'
                    ? () => _showRestaurantHelp(language)
                    : null,
              ),
              const SizedBox(height: 12),
              PlaceContextCard(
                place: place,
                language: language,
                weather: _weather,
                source: source,
                showEvidence: _showEvidence,
              ),
              if (place.category.toLowerCase() == 'restaurant') ...<Widget>[
                const SizedBox(height: 12),
                RestaurantCommunicationEntryCard(
                  language: language,
                  store: widget.preferencesStore,
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('place-detail-toggle-evidence'),
                onPressed: () => setState(() => _showEvidence = !_showEvidence),
                icon: Icon(
                  _showEvidence
                      ? Icons.visibility_off_outlined
                      : Icons.fact_check_outlined,
                ),
                label: Text(
                  _showEvidence
                      ? lalaCopyMulti(
                          language,
                          ko: '상세 근거 접기',
                          en: 'Hide detailed evidence',
                          ja: '詳細な根拠を閉じる',
                          zhHans: '收起详细依据',
                          zhHant: '收起詳細依據',
                        )
                      : lalaCopyMulti(
                          language,
                          ko: '추천 근거 자세히 보기',
                          en: 'View recommendation evidence',
                          ja: 'おすすめの根拠を詳しく見る',
                          zhHans: '查看推荐依据',
                          zhHant: '查看推薦依據',
                        ),
                ),
              ),
              if (_showEvidence) ...<Widget>[
                const SizedBox(height: 12),
                SignalGrid(
                  language: language,
                  localSpending: components?.localSpendingScore,
                  demandDispersion: components?.demandDispersionScore,
                  cultureRelevance: components?.cultureRelevanceScore,
                  weatherFit: components?.weatherFitScore,
                ),
                const SizedBox(height: 12),
                PublicDataProofRow(
                  place: place,
                  language: language,
                  source: source,
                  weather: _weather,
                  score: score,
                ),
              ],
              if (source.trim().isNotEmpty || freshness != null) ...<Widget>[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (source.trim().isNotEmpty)
                      _MetaChip(
                        icon: Icons.verified_outlined,
                        label: sourceLabel(source, language: language),
                      ),
                    if (freshness != null)
                      _MetaChip(
                        icon: Icons.schedule_outlined,
                        label: freshness,
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _handoffToMap(LalaPlace place, LocalSignalPlaceAction action) {
    SelectedPlaceStore.set(place.placeId);
    widget.actionController.dispatch(
      LocalSignalPlaceActionRequest(placeId: place.placeId, action: action),
    );
    context.go(LalaRoutePaths.mapRoute);
  }

  Future<void> _showRestaurantHelp(String language) async {
    final store = widget.preferencesStore ?? TravelPreferencesStore.instance;
    await store.ensureLoaded();
    if (!mounted) return;
    await showRestaurantCommunicationSheet(
      context: context,
      language: language,
      preferences: store.value,
    );
  }
}

class _PlaceActions extends StatelessWidget {
  const _PlaceActions({
    required this.language,
    required this.onAddToPlan,
    required this.onDocent,
    required this.onMap,
    this.onRestaurantHelp,
  });

  final String language;
  final VoidCallback onAddToPlan;
  final VoidCallback onDocent;
  final VoidCallback onMap;
  final VoidCallback? onRestaurantHelp;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionCount = onRestaurantHelp == null ? 3 : 4;
        final columns = actionCount == 4 ? 2 : 3;
        final width = (constraints.maxWidth - (8 * (columns - 1))) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _ActionButton(
              key: const ValueKey('place-detail-add-to-plan'),
              width: width,
              icon: Icons.calendar_month_outlined,
              label: lalaCopyMulti(
                language,
                ko: '일정 추가',
                en: 'Add to plan',
                ja: '予定に追加',
                zhHans: '加入行程',
                zhHant: '加入行程',
              ),
              primary: true,
              onTap: onAddToPlan,
            ),
            _ActionButton(
              key: const ValueKey('place-detail-open-docent'),
              width: width,
              icon: Icons.headphones_outlined,
              label: lalaCopyMulti(
                language,
                ko: '도슨트',
                en: 'Docent',
                ja: 'ガイド',
                zhHans: '导览',
                zhHant: '導覽',
              ),
              onTap: onDocent,
            ),
            _ActionButton(
              key: const ValueKey('place-detail-show-on-map'),
              width: width,
              icon: Icons.map_outlined,
              label: lalaCopyMulti(
                language,
                ko: '지도',
                en: 'Map',
                ja: '地図',
                zhHans: '地图',
                zhHant: '地圖',
              ),
              onTap: onMap,
            ),
            if (onRestaurantHelp != null)
              _ActionButton(
                key: const ValueKey('place-detail-restaurant-help'),
                width: width,
                icon: Icons.record_voice_over_outlined,
                label: lalaCopyMulti(
                  language,
                  ko: '소통 도움',
                  en: 'Staff help',
                  ja: '会話サポート',
                  zhHans: '沟通帮助',
                  zhHant: '溝通協助',
                ),
                onTap: onRestaurantHelp!,
              ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.width,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final double width;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    // Why: fixed 68px height + FittedBox(scaleDown) cancelled large-text
    // growth; the minimum-size style keeps the compact viewport while
    // letting the button grow under text scaling.
    return SizedBox(
      width: width,
      child: primary
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 68),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    LalaVisualTokens.controlRadius,
                  ),
                ),
              ),
              child: _ActionContent(icon: icon, label: label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 68),
                foregroundColor: LalaVisualColors.ink,
                side: const BorderSide(color: LalaVisualColors.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    LalaVisualTokens.controlRadius,
                  ),
                ),
              ),
              child: _ActionContent(icon: icon, label: label),
            ),
    );
  }
}

class _ActionContent extends StatelessWidget {
  const _ActionContent({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 21),
        const SizedBox(height: 4),
        // Two lines + ellipsis instead of scale-down so scaled text grows.
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: LalaVisualColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: LalaVisualColors.primaryPressed),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: LalaVisualColors.primaryPressed,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextNotice extends StatelessWidget {
  const _ContextNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // Why: refresh failures land here after the page is already read; a
    // live region tells screen-reader users the context is stale.
    return Semantics(
      key: const ValueKey('place-detail-stale-notice'),
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
          border: Border.all(color: const Color(0xFFF4C96A)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.info_outline_rounded, color: Color(0xFF9A5A00)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: LalaVisualColors.ink,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceUnavailable extends StatelessWidget {
  const _PlaceUnavailable({required this.language, required this.onMap});

  final String language;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.location_off_outlined,
      title: lalaCopyMulti(
        language,
        ko: '이 장소는 현재 제공되지 않아요.',
        en: 'This place is currently unavailable.',
        ja: 'このスポットは現在利用できません。',
        zhHans: '此地点目前不可用。',
        zhHant: '此地點目前無法使用。',
      ),
      detail: lalaCopyMulti(
        language,
        ko: '지역이나 데이터 범위가 바뀌었을 수 있어요. 지도에서 다른 장소를 확인해 주세요.',
        en: 'The region or data coverage may have changed. Choose another place on the map.',
        ja: '地域やデータ範囲が変わった可能性があります。地図で別のスポットを確認してください。',
        zhHans: '地区或数据范围可能已变化，请在地图上选择其他地点。',
        zhHant: '地區或資料範圍可能已變更，請在地圖上選擇其他地點。',
      ),
      actionLabel: lalaCopyMulti(
        language,
        ko: '지도로 돌아가기',
        en: 'Back to map',
        ja: '地図に戻る',
        zhHans: '返回地图',
        zhHant: '返回地圖',
      ),
      onAction: onMap,
    );
  }
}

class _PlaceLoadError extends StatelessWidget {
  const _PlaceLoadError({
    required this.language,
    required this.message,
    required this.onRetry,
  });

  final String language;
  final String? message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.cloud_off_outlined,
      title:
          message ??
          lalaCopyMulti(
            language,
            ko: '장소 정보를 불러오지 못했어요.',
            en: 'Could not load this place.',
            ja: 'スポット情報を読み込めませんでした。',
            zhHans: '无法加载地点信息。',
            zhHant: '無法載入地點資訊。',
          ),
      detail: lalaCopyMulti(
        language,
        ko: '연결을 확인한 뒤 다시 시도해 주세요.',
        en: 'Check your connection and try again.',
        ja: '接続を確認してもう一度お試しください。',
        zhHans: '请检查网络后重试。',
        zhHant: '請檢查網路後再試一次。',
      ),
      actionLabel: lalaCopyMulti(
        language,
        ko: '다시 시도',
        en: 'Try again',
        ja: '再試行',
        zhHans: '重试',
        zhHant: '重試',
      ),
      onAction: () => unawaited(onRetry()),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LalaVisualTokens.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: LalaVisualColors.muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LalaVisualColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LalaVisualColors.muted,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
