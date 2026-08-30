// ONMU P1: 검색 탭 본문 — 추천 장소 검색/필터.
// LalaAppConfig.fromEnvironment() + LalaApiBackend 로 백엔드를 구성하고,
// GeolocatorLalaLocationProvider 로 현재 위치를 잡아 getPlaces() 로 추천을 불러온다.
// 카테고리 칩과 검색바로 client-side 필터링(home_page 의 패턴과 동일).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/home/home_view_helpers.dart'
    show filterPlaces;
import 'package:lala_next_app/features/location/widgets/default_region_indicator.dart';
import 'package:lala_next_app/features/location/widgets/manual_location_sheet.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/place/place_helpers.dart';
import 'package:lala_next_app/features/place/widgets/category_badge.dart';
import 'package:lala_next_app/features/place/widgets/empty_place_state.dart';
import 'package:lala_next_app/features/place/widgets/place_image.dart';
import 'package:lala_next_app/features/place/widgets/place_reason_freshness.dart';
import 'package:lala_next_app/manual_location_options.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';
import 'package:lala_next_app/shared/labels/dataset_freshness_label.dart';
import 'package:lala_next_app/shared/labels/source_label.dart';
import 'package:lala_next_app/shared/widgets/lala_skeleton.dart';

/// 검색 탭: 추천 장소를 불러와 카테고리/검색어로 필터링한다.
class SearchPage extends StatefulWidget {
  const SearchPage({this.locationProvider, this.backendFactory, super.key});

  /// 테스트 주입용 위치 프로바이더(기본 = Geolocator 하이브리드).
  final LalaLocationProvider? locationProvider;

  /// 테스트 주입용 백엔드 팩토리(기본 = LalaApiBackend).
  final LalaBackendFactory? backendFactory;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

// Per-state honesty (playbook §2/§13.5): five distinct outcomes, never
// conflated. `loaded` is a real result list (never a skeleton); `empty` is a
// genuine no-data result (never shares a message with a failure); `unavailable`
// is "could not reach the service" (network/timeout); `error` is "the service
// responded with an error". An API failure is never shown with the same copy as
// the empty no-data state.
enum _SearchLoadStatus { loading, loaded, empty, unavailable, error }

/// 검색에 노출할 카테고리 라인업(전체/명소/맛집/행사/문화).
const List<String> _kSearchCategories = <String>[
  'all',
  'attraction',
  'restaurant',
  'event',
  'culture_venue',
];

class _SearchPageState extends State<SearchPage> {
  static const int _radiusM = 2000;

  late LalaAppConfig _baseConfig;
  late LalaAppConfig _config;
  late final LalaLocationProvider _locationProvider;
  late final LalaBackendFactory _backendFactory;
  late LalaBackend _backend;

  _SearchLoadStatus _status = _SearchLoadStatus.loading;
  List<LalaPlace> _places = const <LalaPlace>[];
  // 결과 카드의 출처/신선도 영역은 응답 envelope 의 실제 값만 사용한다(03-bindings §2:
  // dataset 출처 = LalaPlacesResponse.source, dataset 신선도 = dataAsOf). 값이 없으면
  // 해당 칩을 렌더하지 않는다 — 발명된 출처/시각을 표시하지 않는다.
  String _datasetSource = '';
  String? _datasetDataAsOf;
  // 안내문은 unavailable/error 상태에서만 사용. empty(no-data) 는 별도 copy.
  String _failureMessage = '';

  // Active region context retained across onboarding/tabs (null = disclosed
  // default region). Seeded from the shared store so a manual/current choice
  // made elsewhere drives this tab's place calls.
  RegionContext? _region = RegionContextStore.current;

  // Monotonic load token. A store-driven reload or a manual retry can start
  // while a device-location request is still in flight; only the newest load may
  // write results so a late response cannot clobber a newer context.
  int _loadGeneration = 0;
  late final VoidCallback _onRegionChanged;
  late final VoidCallback _onLanguageChanged;

  String _selectedCategory = 'all';
  String _query = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _baseConfig = LalaAppConfig.fromEnvironment().copyWith(
      lang: OnboardingState.language,
    );
    _config = _baseConfig.copyWith(radiusM: _radiusM);
    _locationProvider =
        widget.locationProvider ?? const GeolocatorLalaLocationProvider();
    _backendFactory = widget.backendFactory ?? LalaApiBackend.new;
    _backend = _backendFactory(_config);
    _searchController = TextEditingController();
    // React to a region choice made in onboarding or on another tab: rebuild the
    // backend from the shared coordinates WITHOUT re-requesting device location,
    // so a manual choice cannot be overwritten by a later location fetch.
    _onRegionChanged = () {
      if (!mounted) {
        return;
      }
      final next = RegionContextStore.current;
      // Ignore our own publishes and no-op notifications.
      if (next == _region) {
        return;
      }
      _reloadFromStore(next);
    };
    RegionContextStore.listenable.addListener(_onRegionChanged);
    _onLanguageChanged = () {
      if (!mounted) {
        return;
      }
      final next = OnboardingState.language;
      if (next == _language) {
        return;
      }
      _reloadForLanguage(next);
    };
    OnboardingState.languageListenable.addListener(_onLanguageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    RegionContextStore.listenable.removeListener(_onRegionChanged);
    OnboardingState.languageListenable.removeListener(_onLanguageChanged);
    _searchController.dispose();
    _backend.close();
    super.dispose();
  }

  String get _language => _config.lang;

  // True when the active results come from the disclosed default region (no real
  // current/manual context). The UI must badge this honestly.
  bool get _regionIsDefault => _region == null;

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _status = _SearchLoadStatus.loading;
      _failureMessage = '';
    });

    // 온보딩/다른 탭에서 확정된 컨텍스트(수동 선택 또는 현재 위치)를 기본 좌표보다
    // 우선한다. 없으면 공개된 기본 지역(LalaAppConfig)으로 폴백한다.
    var lat = _region?.lat ?? _baseConfig.lat;
    var lng = _region?.lng ?? _baseConfig.lng;
    // Why: only resolve live geolocation when no real context exists yet. A
    // context already in the store (a manual choice retained from onboarding, or
    // a current fix from another tab) is a deliberate selection that this tab's
    // initial device-location request must not overwrite. After-mount changes
    // arrive via _reloadFromStore, which never requests location.
    if (_region == null) {
      try {
        final result = await _locationProvider.requestCurrentLocation();
        // Stale guard: a store-driven reload or retry may have started while this
        // device-location request was in flight — discard so a late response
        // cannot overwrite a newer context.
        if (generation != _loadGeneration || !mounted) {
          return;
        }
        if (result.status == LalaLocationResultStatus.found &&
            result.location != null) {
          lat = result.location!.lat;
          lng = result.location!.lng;
          _region = RegionContext.current(lat: lat, lng: lng);
          RegionContextStore.set(_region);
        }
        // denied / permanentlyDenied / unavailable: 기존 컨텍스트(수동 선택 또는
        // 기본 지역)를 유지. 절대 임의의 위치를 끼워 넣지 않는다.
      } on Object {
        // 위치 미확정 시 현재 컨텍스트(수동 선택 또는 기본 지역)를 유지.
        if (generation != _loadGeneration || !mounted) {
          return;
        }
      }
    }

    _config = _baseConfig.copyWith(lat: lat, lng: lng, radiusM: _radiusM);
    _backend.close();
    _backend = _backendFactory(_config);
    await _fetchPlaces(generation);
  }

  /// 공유 store 의 컨텍스트로 백엔드를 재구성한다. 기기 위치를 다시 요청하지 않으므로,
  /// 온보딩/다른 탭의 수동 선택이 뒤늦은 위치 응답에 덮어씌워지지 않는다.
  void _reloadFromStore(RegionContext? context) {
    final generation = ++_loadGeneration;
    setState(() {
      _region = context;
      _status = _SearchLoadStatus.loading;
      _failureMessage = '';
    });
    final lat = context?.lat ?? _baseConfig.lat;
    final lng = context?.lng ?? _baseConfig.lng;
    _config = _baseConfig.copyWith(lat: lat, lng: lng, radiusM: _radiusM);
    _backend.close();
    _backend = _backendFactory(_config);
    _fetchPlaces(generation);
  }

  /// Rebuilds both UI and request config from the persisted language SSOT.
  /// Location is retained and geolocation is not re-requested.
  void _reloadForLanguage(String language) {
    final generation = ++_loadGeneration;
    setState(() {
      _baseConfig = _baseConfig.copyWith(lang: language);
      _config = _config.copyWith(lang: language);
      _status = _SearchLoadStatus.loading;
      _failureMessage = '';
    });
    _backend.close();
    _backend = _backendFactory(_config);
    _fetchPlaces(generation);
  }

  Future<void> _fetchPlaces(int generation) async {
    try {
      final envelope = await _backend.getPlaces();
      if (generation != _loadGeneration || !mounted) {
        return;
      }
      final places = envelope.data?.places ?? const <LalaPlace>[];
      setState(() {
        _places = places;
        _datasetSource = envelope.data?.source ?? '';
        _datasetDataAsOf = envelope.data?.dataAsOf;
        // loaded vs empty: a real non-empty result is never a skeleton; an empty
        // list is a genuine no-data result, not a failure.
        _status = places.isEmpty
            ? _SearchLoadStatus.empty
            : _SearchLoadStatus.loaded;
      });
    } on Object catch (failure) {
      if (generation != _loadGeneration || !mounted) {
        return;
      }
      // Why: the client throws LalaApiException for both unreachable
      // (NETWORK_ERROR/REQUEST_TIMEOUT/statusCode 0) and responded-error
      // (HTTP_4xx/5xx). Splitting on the code keeps an API failure's copy
      // distinct from the empty no-data message and from a reachability failure.
      final status = _searchFailureStatus(failure);
      setState(() {
        _failureMessage = _failureCopy(status);
        _status = status;
      });
    }
  }

  /// 도달 실패(unavailable)와 오류 응답(error)을 예외 코드로 구분한다.
  _SearchLoadStatus _searchFailureStatus(Object failure) {
    if (failure is LalaApiException) {
      final code = failure.code;
      final networkUnreachable =
          code == 'NETWORK_ERROR' ||
          code == 'REQUEST_TIMEOUT' ||
          failure.statusCode == 0;
      return networkUnreachable
          ? _SearchLoadStatus.unavailable
          : _SearchLoadStatus.error;
    }
    // 비-API 예외(직렬화/파싱 등)는 서비스 도달과 무관하므로 error 로 분류.
    return _SearchLoadStatus.error;
  }

  String _failureCopy(_SearchLoadStatus status) {
    return switch (status) {
      _SearchLoadStatus.unavailable => lalaCopyMulti(
        _language,
        ko: '일시적으로 서버에 연결할 수 없어요. 네트워크를 확인 후 다시 시도해 주세요.',
        en: 'Could not reach the service. Check your connection and try again.',
        ja: 'サーバーに一時的に接続できません。ネットワークを確認してもう一度お試しください。',
        zhHans: '暂时无法连接服务器，请检查网络后重试。',
        zhHant: '暫時無法連線伺服器，請檢查網路後重試。',
      ),
      _SearchLoadStatus.error => lalaCopyMulti(
        _language,
        ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
        en: 'Could not load recommendations. Please try again shortly.',
        ja: 'おすすめスポットを読み込めませんでした。しばらくしてからもう一度お試しください。',
        zhHans: '无法加载推荐地点，请稍后重试。',
        zhHant: '無法載入推薦地點，請稍後重試。',
      ),
      _SearchLoadStatus.loading ||
      _SearchLoadStatus.loaded ||
      _SearchLoadStatus.empty => '',
    };
  }

  List<LalaPlace> get _visiblePlaces {
    var filtered = filterPlaces(_places, _selectedCategory);
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered
          .where((place) {
            final name = placeDisplayName(place, _language).toLowerCase();
            final region = placeRegionLabel(place, _language).toLowerCase();
            return name.contains(query) || region.contains(query);
          })
          .toList(growable: false);
    }
    return filtered;
  }

  // Cross-tab selection (§13.4): publish through the SAME shared store the map
  // tab writes to (persistence + cold-restart hydration ride along), then hand
  // off to the map branch — the surface that owns the selection detail sheet —
  // so a search tap lands exactly like a map tap.
  void _selectPlace(LalaPlace place) {
    SelectedPlaceStore.set(place.placeId);
    context.go(LalaRoutePaths.mapRoute);
  }

  Future<void> _openRegionPicker() async {
    final selected = await showModalBottomSheet<ManualLocationOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualLocationSheet(
        language: _language,
        activeRegionId: _region?.source == RegionSource.manual
            ? _region?.regionId
            : null,
        activeRegionLabel: _regionLabel,
      ),
    );
    if (selected != null && mounted) {
      await RegionContextStore.setAndFlush(RegionContext.manual(selected));
    }
  }

  String get _regionLabel {
    final region = _region;
    if (region != null) {
      return region.label(_language);
    }
    return lalaCopyMulti(
      _language,
      ko: '기본 지역 · 수원',
      en: 'Default region · Suwon',
      ja: '既定の地域 · 水原',
      zhHans: '默认地区 · 水原',
      zhHant: '預設地區 · 水原',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LalaVisualColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SearchHeader(
              controller: _searchController,
              language: _language,
              onChanged: (value) => setState(() => _query = value),
              onResetFilters: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _selectedCategory = 'all';
                });
              },
            ),
            _SearchRegionContextRow(
              language: _language,
              regionLabel: _regionLabel,
              isDefault: _regionIsDefault,
              onPressed: _openRegionPicker,
            ),
            _CategoryChipBar(
              categories: _kSearchCategories,
              selected: _selectedCategory,
              language: _language,
              onSelect: (category) =>
                  setState(() => _selectedCategory = category),
            ),
            if (_regionIsDefault) DefaultRegionIndicator(language: _language),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_status) {
      case _SearchLoadStatus.loading:
        return _SearchLoadingView(language: _language);
      case _SearchLoadStatus.unavailable:
        return _SearchFailureView(
          key: const ValueKey('search-unavailable-view'),
          kind: _SearchFailureKind.unavailable,
          message: _failureMessage,
          language: _language,
          onRetry: _load,
        );
      case _SearchLoadStatus.error:
        return _SearchFailureView(
          key: const ValueKey('search-error-view'),
          kind: _SearchFailureKind.error,
          message: _failureMessage,
          language: _language,
          onRetry: _load,
        );
      case _SearchLoadStatus.empty:
        return _SearchEmptyView(
          language: _language,
          hasQuery: _query.trim().isNotEmpty || _selectedCategory != 'all',
          onResetFilters: () {
            _searchController.clear();
            setState(() {
              _query = '';
              _selectedCategory = 'all';
            });
          },
        );
      case _SearchLoadStatus.loaded:
        return _SearchResultsView(
          places: _visiblePlaces,
          language: _language,
          datasetSource: _datasetSource,
          datasetDataAsOf: _datasetDataAsOf,
          onSelectPlace: _selectPlace,
        );
    }
  }
}

/// 검색 요청의 실제 지역 컨텍스트를 항상 드러내고 전국 직접 선택으로 연결한다.
/// null 컨텍스트는 현재 위치가 아니라 공개된 기본 지역임을 label/icon으로 구분한다.
class _SearchRegionContextRow extends StatelessWidget {
  const _SearchRegionContextRow({
    required this.language,
    required this.regionLabel,
    required this.isDefault,
    required this.onPressed,
  });

  final String language;
  final String regionLabel;
  final bool isDefault;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final contextLabel = lalaCopyMulti(
      language,
      ko: '탐색 지역',
      en: 'Exploration region',
      ja: '探索地域',
      zhHans: '探索地区',
      zhHant: '探索地區',
    );
    final changeLabel = lalaCopyMulti(
      language,
      ko: '변경',
      en: 'Change',
      ja: '変更',
      zhHans: '更改',
      zhHant: '變更',
    );
    final semanticLabel = '$contextLabel, $regionLabel, $changeLabel';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LalaVisualTokens.pageGutter,
        4,
        LalaVisualTokens.pageGutter,
        2,
      ),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: OutlinedButton(
          key: const ValueKey('search-region-picker'),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            foregroundColor: LalaVisualColors.ink,
            backgroundColor: LalaVisualColors.card,
            side: const BorderSide(color: LalaVisualColors.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                LalaVisualTokens.controlRadius,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                isDefault
                    ? Icons.location_searching_rounded
                    : Icons.location_on_outlined,
                size: 20,
                color: isDefault
                    ? LalaVisualColors.muted
                    : LalaVisualColors.primaryBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      contextLabel,
                      style: const TextStyle(
                        color: LalaVisualColors.muted,
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      regionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: LalaVisualColors.ink,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                changeLabel,
                style: const TextStyle(
                  color: LalaVisualColors.primaryBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: LalaVisualColors.primaryBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 결과 세트 출처/데이터 기준 시각 칩(PlaceFreshnessText 와 같은 메타 스타일).
/// 11sp 미만으로 줄이지 않는다(04-responsive §3).
class _SearchDatasetMetaText extends StatelessWidget {
  const _SearchDatasetMetaText(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: LalaVisualColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: LalaVisualColors.primaryPressed,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 상단 검색 바.
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.language,
    required this.onChanged,
    required this.onResetFilters,
  });

  final TextEditingController controller;
  final String language;
  final ValueChanged<String> onChanged;

  /// 필터 아이콘: 카테고리/검색어 필터를 한 번에 지운다.
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    // 모바일 비주얼 계약 remediation D: 헤더는 필드(선행 검색 아이콘 + placeholder +
    // 후행 필터 아이콘 하나)만. 커뮤니티/새로고침 버튼은 이 헤더에서 뺀다(라우트/서비스 유지).
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LalaVisualTokens.pageGutter,
        18,
        LalaVisualTokens.pageGutter,
        4,
      ),
      child: SizedBox(
        height: 48,
        child: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: lalaCopyMulti(
              language,
              ko: '장소·지역 검색',
              en: 'Search places or areas',
              ja: 'スポット・地域を検索',
              zhHans: '搜索地点或地区',
              zhHant: '搜尋地點或地區',
            ),
            hintStyle: const TextStyle(color: LalaVisualColors.muted),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: LalaVisualColors.primaryBlue,
            ),
            suffixIcon: IconButton(
              tooltip: lalaCopyMulti(
                language,
                ko: '필터',
                en: 'Filter',
                ja: 'フィルター',
                zhHans: '筛选',
                zhHant: '篩選',
              ),
              onPressed: onResetFilters,
              icon: const Icon(
                Icons.filter_list_rounded,
                color: LalaVisualColors.primaryBlue,
              ),
            ),
            filled: true,
            fillColor: LalaVisualColors.card,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 0,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                LalaVisualTokens.controlRadius,
              ),
              borderSide: const BorderSide(color: LalaVisualColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                LalaVisualTokens.controlRadius,
              ),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 카테고리 필터 칩 가로 스크롤.
class _CategoryChipBar extends StatelessWidget {
  const _CategoryChipBar({
    required this.categories,
    required this.selected,
    required this.language,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final String language;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selected;
          final accent = category == 'all'
              ? LalaVisualColors.primaryBlue
              : categoryColor(category);
          final selectedTextColor = category == 'restaurant'
              ? LalaVisualColors.restaurantInk
              : Colors.white;
          // 접근성(§13.5): 칩 터치 타겟이 44dp 이상이 되도록 padding 으로 채운다.
          // (compact label 사이즈 자체는 유지하되 hit 영역만 44dp 확보.)
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: FilterChip(
                label: Text(
                  categoryFilterLabel(category, language),
                  style: TextStyle(
                    color: isSelected
                        ? selectedTextColor
                        : LalaVisualColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => onSelect(category),
                selectedColor: accent,
                backgroundColor: Colors.white,
                checkmarkColor: selectedTextColor,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                side: BorderSide(
                  color: isSelected ? accent : LalaVisualColors.line,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 로딩 상태 본문: 요청 진행 중에만 결과 모양의 중성 스켈레톤 3줄.
/// 데이터/에러 도착 시 이 위젯은 더 이상 렌더되지 않는다(_buildBody 분기).
class _SearchLoadingView extends StatelessWidget {
  const _SearchLoadingView({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    // 시맨틱: 로딩 상태를 화면 읽기 사용자에게 알린다(진행률/단계 주장 없이).
    return Semantics(
      container: true,
      label: lalaCopyMulti(
        language,
        ko: '추천 장소를 불러오는 중',
        en: 'Loading recommendations',
        ja: 'おすすめスポットを読み込み中',
        zhHans: '正在加载推荐地点',
        zhHant: '正在載入推薦地點',
      ),
      child: ListView.builder(
        key: const ValueKey('search-loading-view'),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        itemCount: 3,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
          child: const _SearchSkeletonRow(),
        ),
      ),
    );
  }
}

/// 결과 타일 모양의 중성 스켈레톤(좌측 미디어 96x88 + 우측 텍스트 레일 — 재구성된
/// 결과 타일과 동일 구조). 가짜 매장명/이미지 없음.
class _SearchSkeletonRow extends StatelessWidget {
  const _SearchSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('search-skeleton-row'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LalaVisualColors.card,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const LalaSkeleton(
            width: 96,
            height: 88,
            radius: LalaVisualTokens.controlRadius,
          ),
          const SizedBox(width: LalaVisualTokens.contentGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const LalaSkeleton(width: 64, height: 18, radius: 9),
                const SizedBox(height: 12),
                const LalaSkeletonLine(width: 150),
                const SizedBox(height: 8),
                const LalaSkeletonLine(width: 110),
                const SizedBox(height: 8),
                const LalaSkeletonLine(width: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 실패 본문(unavailable / error). 두 상태는 서로 다른 아이콘·카피로 구분되며,
/// 빈 상태(no-data)의 카피와 절대 겹치지 않는다. 색상만으로 상태를 알리지 않도록
/// 아이콘 + 텍스트 쌍을 항상 함께 표시한다(§13.5 접근성).
enum _SearchFailureKind { unavailable, error }

class _SearchFailureView extends StatelessWidget {
  const _SearchFailureView({
    super.key,
    required this.kind,
    required this.message,
    required this.language,
    required this.onRetry,
  });

  final _SearchFailureKind kind;
  final String message;
  final String language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isUnavailable = kind == _SearchFailureKind.unavailable;
    // 아이콘과 색상을 함께 써 색상 단독 신호를 피한다.
    final icon = isUnavailable
        ? Icons.wifi_off_rounded
        : Icons.error_outline_rounded;
    final accent = isUnavailable
        ? const Color(0xFF475569)
        : const Color(0xFFB45309);
    final retryLabel = lalaCopyMulti(
      language,
      ko: '재시도',
      en: 'Retry',
      ja: '再試行',
      zhHans: '重试',
      zhHant: '重試',
    );
    // 시맨틱: 화면 읽기 사용자에게 상태 종류까지 전달.
    final semanticsLabel = lalaCopyMulti(
      language,
      ko: isUnavailable ? '서버 연결 불가. $message' : '추천 불러오기 실패. $message',
      en: isUnavailable
          ? 'Service unreachable. $message'
          : 'Failed to load recommendations. $message',
      ja: isUnavailable ? 'サーバーに接続できません。$message' : 'おすすめの読み込みに失敗しました。$message',
      zhHans: isUnavailable ? '无法连接服务器。$message' : '加载推荐失败。$message',
      zhHant: isUnavailable ? '無法連線伺服器。$message' : '載入推薦失敗。$message',
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: accent),
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: semanticsLabel,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 최소 44dp 터치 타겟: 버튼 기본 최소 높이를 보장한다.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(retryLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2B6CB0),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 빈 상태(no-data): 정상 로드되었으나 표시할 장소가 없다(또는 필터 결과 없음).
/// 실패 카피와 구분되는 고유 안내문을 쓰며, '불러오는 중' 로딩 상태와도 섞이지 않는다.
class _SearchEmptyView extends StatelessWidget {
  const _SearchEmptyView({
    required this.language,
    required this.hasQuery,
    required this.onResetFilters,
  });

  final String language;
  final bool hasQuery;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    final message = lalaCopyMulti(
      language,
      // Why: the data already loaded — an empty list is an empty result, not a
      // "loading" or failure state. Copy is distinct from both the skeleton and
      // any failure message.
      ko: hasQuery ? '조건에 맞는 장소가 없어요.' : '이 주변엔 아직 추천이 없어요.',
      en: hasQuery
          ? 'No places match your search.'
          : 'No recommendations here yet.',
      ja: hasQuery ? '条件に合うスポットが見つかりません。' : 'この周辺にはまだおすすめがありません。',
      zhHans: hasQuery ? '没有符合搜索条件的地点。' : '这附近暂无推荐。',
      zhHant: hasQuery ? '沒有符合搜尋條件的地點。' : '這附近暫無推薦。',
    );
    final semanticsLabel = lalaCopyMulti(
      language,
      ko: '빈 추천. $message',
      en: 'Empty recommendations. $message',
      ja: 'おすすめなし。$message',
      zhHans: '暂无推荐。$message',
      zhHant: '暫無推薦。$message',
    );
    final actionLabel = lalaCopyMulti(
      language,
      ko: '필터 초기화',
      en: 'Reset filters',
      ja: 'フィルターをリセット',
      zhHans: '重置筛选',
      zhHant: '重設篩選',
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyPlaceState(language: language),
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: semanticsLabel,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (hasQuery) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: OutlinedButton.icon(
                  onPressed: onResetFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: Text(actionLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2B6CB0),
                    side: const BorderSide(color: Color(0xFFB9D4F3)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    minimumSize: const Size.fromHeight(44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 결과 본문(세로 리스트). loaded 전용 — 빈/실패 분기는 _buildBody 에서 별도 위젯으로
/// 분리되었다. 실제 결과가 있을 때만 렌더되므로 여기서 빈 분기는 다루지 않는다.
class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({
    required this.places,
    required this.language,
    required this.datasetSource,
    required this.datasetDataAsOf,
    required this.onSelectPlace,
  });

  final List<LalaPlace> places;
  final String language;

  /// 결과 세트의 실제 출처/데이터 기준 시각(응답 envelope). 값이 없으면 칩 미표시.
  final String datasetSource;
  final String? datasetDataAsOf;

  final ValueChanged<LalaPlace> onSelectPlace;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('search-results-view'),
      // 00-ground-truth §4: 일반 화면 gutter 24dp.
      padding: const EdgeInsets.fromLTRB(
        LalaVisualTokens.pageGutter,
        8,
        LalaVisualTokens.pageGutter,
        24,
      ),
      itemCount: places.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final place = places[index];
        return _SearchPlaceTile(
          place: place,
          language: language,
          datasetSource: datasetSource,
          datasetDataAsOf: datasetDataAsOf,
          onTap: () => onSelectPlace(place),
        );
      },
    );
  }
}

/// 검색 결과용 풀폭 장소 타일(CategoryBadge + PlaceThumb 재사용).
class _SearchPlaceTile extends StatelessWidget {
  const _SearchPlaceTile({
    required this.place,
    required this.language,
    required this.datasetSource,
    required this.datasetDataAsOf,
    required this.onTap,
  });

  final LalaPlace place;
  final String language;

  /// 결과 세트의 실제 출처/데이터 기준 시각(응답 envelope). 값이 없으면 칩 미표시.
  final String datasetSource;
  final String? datasetDataAsOf;

  /// 타일 탭 → 공유 선택 스토어 게시 + 지도 탭 전환(_selectPlace).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = placeDisplayName(place, language);
    final region = placeRegionLabel(place, language);
    // S2 계약: source/dataset data_as_of 가 없으면 source/freshness 칩을 숨긴다.
    final sourceChip = sourceLabel(datasetSource, language: language);
    final freshnessChip = datasetFreshnessLabel(datasetDataAsOf, language);
    final reason = placeReasonText(place);
    final accent = categoryColor(place.category);
    return Material(
      color: LalaVisualColors.card,
      borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
      child: InkWell(
        key: ValueKey('search-place-tile-tap-${place.placeId}'),
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        onTap: onTap,
        child: Semantics(
          container: true,
          // 접근성(§13.5): 장소명/카테고리/거리/지역/reason을 하나의 시맨틱 라벨로 합쳐 전달
          // (placeCardSemanticsLabel SSOT — 다른 표면과 동일 문구 보증).
          label: placeCardSemanticsLabel(place, language),
          button: true,
          child: Container(
            key: ValueKey('search-place-tile-${place.placeId}'),
            // 최소 44dp 터치 타겟 보장(내용이 짧아도 타일 전체 높이 하한선).
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LalaVisualColors.card,
              borderRadius: BorderRadius.circular(
                LalaVisualTokens.controlRadius,
              ),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 16,
                  offset: Offset(0, 5),
                  color: Color(0x0F27466B),
                ),
              ],
            ),
            // S2 계약 재구성: 좌측 고정 미디어 프레임 → 우측 '이름 → 한 줄 reason →
            // compact 메타 → 실제 dataset 출처/신선도' 순서.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SearchPlaceMediaFrame(place: place, language: language),
                const SizedBox(width: LalaVisualTokens.contentGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              key: ValueKey(
                                'search-place-name-${place.placeId}',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: LalaVisualColors.ink,
                                    fontWeight: FontWeight.w900,
                                    height: 1.14,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: LalaVisualColors.muted,
                          ),
                        ],
                      ),
                      if (reason != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          key: ValueKey('search-place-reason-${place.placeId}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                              LalaVisualTokens.controlRadius,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 13,
                                color: accent,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  reason,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: LalaVisualColors.ink,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CategoryBadge(
                            category: place.category,
                            language: language,
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: LalaVisualColors.muted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              region,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: LalaVisualColors.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (place.distanceM > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${place.distanceM}m',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: LalaVisualColors.muted,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      // 실제 값이 있을 때만 렌더되는 출처/신선도 영역(빈 줄 없음).
                      if (sourceChip != '-' ||
                          freshnessChip != null ||
                          (place.freshness?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (sourceChip != '-')
                              _SearchDatasetMetaText(sourceChip),
                            if (place.freshness?.isNotEmpty ?? false)
                              PlaceFreshnessText(place: place),
                            if (freshnessChip != null)
                              _SearchDatasetMetaText(freshnessChip),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 결과 미디어 프레임(좌측 고정 96x88, 반경 8). 공식 이미지가 있을 때만 실제
/// 이미지를 채우고, 없으면 카테고리 색의 place 아이콘 placeholder 를 둔다 —
/// 다른 장소 사진을 대체해 끼워 넣지 않는다(00-ground-truth §3 금지).
/// 이미지 유무와 무관하게 치수가 고정되어 레이아웃이 흔들리지 않는다.
class _SearchPlaceMediaFrame extends StatelessWidget {
  const _SearchPlaceMediaFrame({required this.place, required this.language});

  final LalaPlace place;
  final String language;

  @override
  Widget build(BuildContext context) {
    final hasImage = hasOfficialPlaceImage(place);
    return Container(
      key: ValueKey('search-place-media-${place.placeId}'),
      width: 96,
      height: 88,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: categoryColor(place.category).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        border: Border.all(
          color: categoryColor(place.category).withValues(alpha: 0.24),
        ),
      ),
      child: hasImage
          ? PlaceImage(place: place, width: 96, height: 88)
          : Center(
              // S4 계약의 정직한 이미지 부재 문구 재사용(다른 장소 사진 대체 금지).
              child: Semantics(
                label: lalaCopyMulti(
                  language,
                  ko: '이미지 준비 중',
                  en: 'Image pending',
                  ja: '画像準備中',
                  zhHans: '图片准备中',
                  zhHant: '圖片準備中',
                ),
                child: Icon(
                  Icons.place_rounded,
                  size: 28,
                  color: categoryColor(place.category),
                ),
              ),
            ),
    );
  }
}
