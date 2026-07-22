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
import 'package:lala_next_app/features/home/home_view_helpers.dart' show filterPlaces;
import 'package:lala_next_app/features/place/place_helpers.dart';
import 'package:lala_next_app/features/place/widgets/category_badge.dart';
import 'package:lala_next_app/features/place/widgets/empty_place_state.dart';
import 'package:lala_next_app/features/place/widgets/place_thumb.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';

/// 검색 탭: 추천 장소를 불러와 카테고리/검색어로 필터링한다.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

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
  late LalaBackend _backend;

  _SearchLoadStatus _status = _SearchLoadStatus.loading;
  List<LalaPlace> _places = const <LalaPlace>[];
  String? _error;

  String _selectedCategory = 'all';
  String _query = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _baseConfig = LalaAppConfig.fromEnvironment();
    _config = _baseConfig.copyWith(radiusM: _radiusM);
    _locationProvider = const GeolocatorLalaLocationProvider();
    _backend = LalaApiBackend(_config);
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _backend.close();
    super.dispose();
  }

  String get _language => _config.lang;

  Future<void> _load() async {
    setState(() {
      _status = _SearchLoadStatus.loading;
      _error = null;
    });

    var lat = _baseConfig.lat;
    var lng = _baseConfig.lng;
    try {
      final result = await _locationProvider.requestCurrentLocation();
      if (result.status == LalaLocationResultStatus.found &&
          result.location != null) {
        lat = result.location!.lat;
        lng = result.location!.lng;
      }
    } on Object {
      // 위치 미확정 시 기본 위치(LalaAppConfig)로 폴백.
    }

    _config = _baseConfig.copyWith(lat: lat, lng: lng, radiusM: _radiusM);
    _backend.close();
    _backend = LalaApiBackend(_config);

    try {
      final envelope = await _backend.getPlaces();
      final places = envelope.data?.places ?? const <LalaPlace>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _places = places;
        _status = _SearchLoadStatus.data;
      });
    } on LalaApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        final message = error.message.trim();
        _error = message.isEmpty ? _fallbackErrorMessage() : message;
        _status = _SearchLoadStatus.error;
      });
    } on Object {
      if (!mounted) {
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
              onRefresh: _load,
            ),
            _CategoryChipBar(
              categories: _kSearchCategories,
              selected: _selectedCategory,
              language: _language,
              onSelect: (category) =>
                  setState(() => _selectedCategory = category),
            ),
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

/// 상단 검색 바 + 새로고침 버튼.
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.language,
    required this.onChanged,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final String language;
  final ValueChanged<String> onChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      tooltip: lalaCopy(language, ko: '지우기', en: 'Clear'),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                      icon: const Icon(
                        Icons.cancel,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                    );
                  },
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.6,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: lalaCopy(language, ko: '새로고침', en: 'Refresh'),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            color: const Color(0xFF2B6CB0),
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selected;
          return FilterChip(
            label: Text(
              categoryFilterLabel(category, language),
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : const Color(0xFF334155),
                fontWeight: FontWeight.w900,
              ),
            ),
            selected: isSelected,
            onSelected: (_) => onSelect(category),
            selectedColor: const Color(0xFF2B6CB0),
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            showCheckmark: false,
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFF2B6CB0)
                  : const Color(0xFFE2E8F0),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          );
        },
      ),
    );
  }
}

/// 로딩 상태 본문.
class _SearchLoadingView extends StatelessWidget {
  const _SearchLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(height: 14),
            Text(
              '추천 장소를 불러오는 중...',
              style: TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
                  ko: hasQuery ? '조건에 맞는 장소가 없어요.' : '이 주변 추천을 준비 중입니다.',
                  en: hasQuery
                      ? 'No places match your search.'
                      : 'Recommendations are still being prepared here.',
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
