// ONMU P1: 검색 탭 본문 — 추천 장소 검색/필터.
// LalaAppConfig.fromEnvironment() + LalaApiBackend 로 백엔드를 구성하고,
// GeolocatorLalaLocationProvider 로 현재 위치를 잡아 getPlaces() 로 추천을 불러온다.
// 카테고리 칩과 검색바로 client-side 필터링(home_page 의 패턴과 동일).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/home/home_view_helpers.dart'
    show filterPlaces;
import 'package:lala_next_app/features/location/widgets/default_region_indicator.dart';
import 'package:lala_next_app/features/place/place_helpers.dart';
import 'package:lala_next_app/features/place/widgets/category_badge.dart';
import 'package:lala_next_app/features/place/widgets/empty_place_state.dart';
import 'package:lala_next_app/features/place/widgets/place_thumb.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';
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

enum _SearchLoadStatus { loading, data, error }

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

  late final LalaAppConfig _baseConfig;
  late LalaAppConfig _config;
  late final LalaLocationProvider _locationProvider;
  late final LalaBackendFactory _backendFactory;
  late LalaBackend _backend;

  _SearchLoadStatus _status = _SearchLoadStatus.loading;
  List<LalaPlace> _places = const <LalaPlace>[];
  String? _error;

  // Active region context retained across onboarding/tabs (null = disclosed
  // default region). Seeded from the shared store so a manual/current choice
  // made elsewhere drives this tab's place calls.
  RegionContext? _region = RegionContextStore.current;

  // Monotonic load token. A store-driven reload or a manual retry can start
  // while a device-location request is still in flight; only the newest load may
  // write results so a late response cannot clobber a newer context.
  int _loadGeneration = 0;
  late final VoidCallback _onRegionChanged;

  String _selectedCategory = 'all';
  String _query = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _baseConfig = LalaAppConfig.fromEnvironment();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    RegionContextStore.listenable.removeListener(_onRegionChanged);
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
      _error = null;
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
      _error = null;
    });
    final lat = context?.lat ?? _baseConfig.lat;
    final lng = context?.lng ?? _baseConfig.lng;
    _config = _baseConfig.copyWith(lat: lat, lng: lng, radiusM: _radiusM);
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
        _status = _SearchLoadStatus.data;
      });
    } on LalaApiException catch (error) {
      if (generation != _loadGeneration || !mounted) {
        return;
      }
      setState(() {
        final message = error.message.trim();
        _error = message.isEmpty ? _fallbackErrorMessage() : message;
        _status = _SearchLoadStatus.error;
      });
    } on Object {
      if (generation != _loadGeneration || !mounted) {
        return;
      }
      setState(() {
        _error = _fallbackErrorMessage();
        _status = _SearchLoadStatus.error;
      });
    }
  }

  String _fallbackErrorMessage() {
    return lalaCopy(
      _language,
      ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
      en: 'Could not load recommendations. Please try again shortly.',
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
        return const _SearchLoadingView();
      case _SearchLoadStatus.error:
        return _SearchErrorView(message: _error!, onRetry: _load);
      case _SearchLoadStatus.data:
        return _SearchResultsView(
          places: _visiblePlaces,
          hasQuery: _query.trim().isNotEmpty || _selectedCategory != 'all',
          language: _language,
        );
    }
  }
}

/// 상단 검색 바 + 커뮤니티 진입 + 새로고침 버튼.
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
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
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
            hintText: lalaCopy(
              language,
              ko: '장소·지역 검색',
              en: 'Search places or areas',
            ),
            hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF64748B),
            ),
            suffixIcon: IconButton(
              tooltip: lalaCopy(language, ko: '필터', en: 'Filter'),
              onPressed: onResetFilters,
              icon: const Icon(
                Icons.filter_list_rounded,
                color: Color(0xFF64748B),
              ),
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 0,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
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
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selected;
          return FilterChip(
            label: Text(
              categoryFilterLabel(category, language),
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF334155),
                fontWeight: FontWeight.w900,
              ),
            ),
            selected: isSelected,
            onSelected: (_) => onSelect(category),
            selectedColor: const Color(0xFF2B6CB0),
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            showCheckmark: false,
            // 지도 칩과 동일한 컴팩트 언어: shrink wrap으로 40dp 이하 타겟.
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFF2B6CB0)
                  : const Color(0xFFE2E8F0),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          );
        },
      ),
    );
  }
}

/// 로딩 상태 본문: 요청 진행 중에만 결과 모양의 중성 스켈레톤 3줄.
/// 데이터/에러 도착 시 이 위젯은 더 이상 렌더되지 않는다(_buildBody 분기).
class _SearchLoadingView extends StatelessWidget {
  const _SearchLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: 3,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
        child: const _SearchSkeletonRow(),
      ),
    );
  }
}

/// 결과 타일 모양의 중성 스켈레톤(이미지 96x88 + 텍스트 레일). 가짜 매장명/이미지 없음.
class _SearchSkeletonRow extends StatelessWidget {
  const _SearchSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('search-skeleton-row'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
          const SizedBox(width: 12),
          const LalaSkeleton(width: 96, height: 88, radius: 8),
        ],
      ),
    );
  }
}

/// 에러 상태 본문(메시지 + 재시도).
class _SearchErrorView extends StatelessWidget {
  const _SearchErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 36,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('재시도'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2B6CB0),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 결과 본문(빈 상태 / 세로 리스트).
class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({
    required this.places,
    required this.hasQuery,
    required this.language,
  });

  final List<LalaPlace> places;
  final bool hasQuery;
  final String language;

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyPlaceState(language: language),
              const SizedBox(height: 12),
              Text(
                lalaCopy(
                  language,
                  // Why: an empty result is not "preparing" — the data arrived and
                  // there is nothing here. Say so honestly instead of implying a
                  // perpetual pending state.
                  ko: hasQuery ? '조건에 맞는 장소가 없어요.' : '이 주변엔 아직 추천이 없어요.',
                  en: hasQuery
                      ? 'No places match your search.'
                      : 'No recommendations here yet.',
                ),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: places.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final place = places[index];
        return _SearchPlaceTile(place: place, language: language);
      },
    );
  }
}

/// 검색 결과용 풀폭 장소 타일(CategoryBadge + PlaceThumb 재사용).
class _SearchPlaceTile extends StatelessWidget {
  const _SearchPlaceTile({required this.place, required this.language});

  final LalaPlace place;
  final String language;

  @override
  Widget build(BuildContext context) {
    final hasImage = hasOfficialPlaceImage(place);
    return Container(
      key: ValueKey('search-place-tile-${place.placeId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 6),
            color: Color(0x10000000),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CategoryBadge(category: place.category, language: language),
                    if (place.distanceM > 0)
                      Text(
                        '${place.distanceM}m',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  placeDisplayName(place, language),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.14,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 13,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        placeRegionLabel(place, language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (hasImage) ...[
            const SizedBox(width: 12),
            PlaceThumb(place: place),
          ],
        ],
      ),
    );
  }
}
