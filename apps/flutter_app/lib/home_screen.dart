import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'manual_location_options.dart';
import 'features/place/widgets/place_image.dart';
import 'features/home/home_view_helpers.dart';
import 'features/weather/weather_helpers.dart';
import 'shared/l10n/place_labels.dart';
import 'shared/labels/dust_label.dart';
part 'lala_guide.dart';

const _homeJade = Color(0xFF31786C);
const _homeInk = Color(0xFF292725);

class DiscoveryHome extends StatefulWidget {
  const DiscoveryHome({
    super.key,
    required this.searchController,
    required this.travelStyles,
    required this.travelMode,
    required this.language,
    required this.loading,
    required this.error,
    required this.places,
    required this.weather,
    required this.dailyPlan,
    required this.savedIds,
    required this.lat,
    required this.lng,
    required this.region,
    required this.onRegion,
    required this.onManualRegion,
    required this.onLocate,
    required this.onSave,
    required this.onPlace,
    required this.onMap,
    required this.onSavedPlaces,
    required this.onPlan,
    required this.onSettings,
    required this.onRefresh,
  });
  final TextEditingController searchController;
  final List<String> travelStyles;
  final String travelMode;
  final String language;
  final bool loading;
  final String? error;
  final List<LalaPlace> places;
  final LalaWeather? weather;
  final LalaDailyPlan? dailyPlan;
  final Set<String> savedIds;
  final double lat, lng;
  final ManualLocationOption? region;
  final ValueChanged<ManualLocationOption> onRegion;
  final ValueChanged<String> onSave;
  final ValueChanged<LalaPlace> onPlace;
  final VoidCallback onManualRegion,
      onLocate,
      onMap,
      onSavedPlaces,
      onPlan,
      onSettings,
      onRefresh;
  @override
  State<DiscoveryHome> createState() => DiscoveryHomeState();
}

class _HomeInfoChip extends StatelessWidget {
  const _HomeInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F7F4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE9E4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _homeJade),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF456059),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentPlaceCard extends StatelessWidget {
  const _RecentPlaceCard({
    required this.place,
    required this.language,
    required this.onTap,
  });

  final LalaPlace place;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE3EAE7)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: PlaceImage(place: place, width: 72, height: 72),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        placeDisplayName(place, language),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        placeRegionLabel(place, language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF77827E),
                          fontSize: 11,
                        ),
                      ),
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

class DiscoveryHomeState extends State<DiscoveryHome> {
  String _query = '', _category = 'all';
  final bool _savedOnly = false;
  final List<String> _recentPlaceIds = <String>[];
  String t(String ko, String en) => widget.language == 'ko' ? ko : en;
  TextEditingController get _search => widget.searchController;
  final _resultsKey = GlobalKey();
  void updateSearch(String value) =>
      setState(() => _query = value.trim().toLowerCase());

  void _openPlace(LalaPlace place) {
    setState(() {
      _recentPlaceIds.remove(place.placeId);
      _recentPlaceIds.insert(0, place.placeId);
      if (_recentPlaceIds.length > 6) _recentPlaceIds.removeLast();
    });
    unawaited(_saveRecentPlaces());
    widget.onPlace(place);
  }

  Future<void> _restoreRecentPlaces() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final restored = preferences.getStringList('lala.recent_places.v1');
      if (!mounted || restored == null) return;
      setState(() {
        _recentPlaceIds
          ..clear()
          ..addAll(restored.take(6));
      });
    } on Object {
      /* Discovery works without optional history storage. */
    }
  }

  Future<void> _saveRecentPlaces() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(
        'lala.recent_places.v1',
        List.of(_recentPlaceIds),
      );
    } on Object {
      /* Keep history in memory if storage is unavailable. */
    }
  }

  List<LalaPlace> get _recentPlaces => _recentPlaceIds
      .map(
        (id) => widget.places.cast<LalaPlace?>().firstWhere(
          (place) => place?.placeId == id,
          orElse: () => null,
        ),
      )
      .whereType<LalaPlace>()
      .toList(growable: false);
  @override
  void initState() {
    super.initState();
    _query = _search.text.trim().toLowerCase();
    unawaited(_restoreRecentPlaces());
  }

  Widget _heading(String title, String action, VoidCallback callback) =>
      Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(onPressed: callback, child: Text(action)),
          ],
        ),
      );

  Widget _photo(LalaPlace place, {double height = 160}) => Container(
    height: height,
    width: double.infinity,
    color: const Color(0xFFEAF1EE),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const Center(
          child: Icon(
            Icons.account_balance_outlined,
            size: 40,
            color: _homeJade,
          ),
        ),
        PlaceImage(place: place, width: double.infinity, height: height),
      ],
    ),
  );

  Widget _placeCard(LalaPlace place) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE3EAE7)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              InkWell(onTap: () => _openPlace(place), child: _photo(place)),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  tooltip: t('장소 저장', 'Save place'),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _homeJade,
                  ),
                  onPressed: () => widget.onSave(place.placeId),
                  icon: Icon(
                    widget.savedIds.contains(place.placeId)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              placeDisplayName(place, widget.language),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.language != 'ko' &&
                    place.nameKo?.trim().isNotEmpty == true) ...[
                  Text(
                    place.nameKo!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF4F5D58),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  '${placeContextTitle(place.category, widget.language)} · ${_distanceLabel(place.distanceM)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF77827E),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HomeInfoChip(
                      icon: Icons.auto_awesome_outlined,
                      label: _recommendationReason(place),
                    ),
                    _HomeInfoChip(
                      icon: Icons.headphones_outlined,
                      label: t('도슨트 요청 가능', 'Docent available'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openPlace(place),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(t('장소 알아보기', 'View place')),
            ),
          ),
        ],
      ),
    ),
  );

  String _distanceLabel(int distanceM) {
    if (distanceM < 1000) return '${distanceM}m';
    return '${(distanceM / 1000).toStringAsFixed(1)}km';
  }

  String _recommendationReason(LalaPlace place) {
    final matchingStyle = widget.travelStyles.cast<String?>().firstWhere(
      (style) =>
          {
            'history': 'attraction',
            'nature': 'attraction',
            'food': 'restaurant',
            'kculture': 'culture_venue',
            'market': 'event',
          }[style] ==
          place.category,
      orElse: () => null,
    );
    if (matchingStyle != null) {
      final label = switch (matchingStyle) {
        'history' => t('역사 취향', 'history interest'),
        'nature' => t('자연 취향', 'nature interest'),
        'food' => t('음식 취향', 'food interest'),
        'kculture' => t('문화 취향', 'culture interest'),
        'market' => t('시장·축제 취향', 'market interest'),
        _ => t('여행 취향', 'your interests'),
      };
      return t('관심 분야: $label', 'Your interest: $label');
    }
    if (place.isOngoing == true) {
      return t('현재 진행 중인 행사', 'Happening now');
    }
    final components = place.score?.components;
    if ((components?.weatherFitScore ?? 0) >= .75) {
      return t('오늘 날씨와 잘 맞아요', 'Fits today’s weather');
    }
    if ((components?.cultureRelevanceScore ?? 0) >= .75) {
      return t('문화 연계성이 높아요', 'Strong cultural relevance');
    }
    if (place.distanceM <= 1000) {
      return t('가까이 있어요', 'Close to you');
    }
    if ((place.score?.finalScore ?? 0) >= .8) {
      return t('로컬 가치 점수가 높아요', 'High local-value score');
    }
    return t('현재 지역 추천', 'Recommended in this area');
  }

  Widget _searchField() => TextField(
    key: const ValueKey('home-search'),
    controller: _search,
    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    decoration: InputDecoration(
      hintText: t('도시 · 명소 · 이야기 검색', 'Search places and stories'),
      prefixIcon: const Icon(Icons.search),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(40),
        borderSide: const BorderSide(color: Color(0xFFDDE5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(40),
        borderSide: const BorderSide(color: Color(0xFFDDE5E1)),
      ),
    ),
  );

  Future<void> _guide() async {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final String? action;
    if (wide) {
      action = await showDialog<String>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: SizedBox(
            width: 820,
            height: MediaQuery.sizeOf(context).height * .88,
            child: _LalaGuide(language: widget.language),
          ),
        ),
      );
    } else {
      action = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => _ExpandableGuide(language: widget.language),
      );
    }
    if (mounted && action == 'region') widget.onManualRegion();
  }

  @override
  Widget build(BuildContext context) {
    final nearby = [...manualLocationOptions]
      ..sort((a, b) {
        double distance(ManualLocationOption item) =>
            math.pow(item.lat - widget.lat, 2).toDouble() +
            math.pow((item.lng - widget.lng) * .8, 2).toDouble();
        return distance(a).compareTo(distance(b));
      });
    final regions =
        (widget.travelMode == 'undecided'
                ? featuredManualLocationOptions
                : nearby)
            .where((region) => _query.isEmpty || region.matches(_query))
            .take(5)
            .toList();
    final preferredCategories = widget.travelStyles
        .map(
          (style) => {
            'history': 'attraction',
            'nature': 'attraction',
            'food': 'restaurant',
            'kculture': 'culture_venue',
            'market': 'event',
          }[style],
        )
        .toSet();
    final ranked = [
      ...widget.places.where((p) => preferredCategories.contains(p.category)),
      ...widget.places.where((p) => !preferredCategories.contains(p.category)),
    ];
    final visible = ranked
        .where(
          (p) =>
              (_category == 'all' || p.category == _category) &&
              (!_savedOnly || widget.savedIds.contains(p.placeId)) &&
              (_query.isEmpty ||
                  '${p.name} ${p.nameKo} ${p.nameEn} ${p.address}'
                      .toLowerCase()
                      .contains(_query)),
        )
        .toList();
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _homeJade,
          primary: _homeJade,
          surface: Colors.white,
        ),
        textTheme: Theme.of(
          context,
        ).textTheme.apply(bodyColor: _homeInk, displayColor: _homeInk),
      ),
      child: ColoredBox(
        color: Colors.white,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final columns = wide
                ? 4
                : box.maxWidth >= 600
                ? 3
                : box.maxWidth < 360
                ? 1
                : 2;
            return SingleChildScrollView(
              key: const PageStorageKey('discovery-home-scroll'),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 20,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!wide)
                          Row(
                            children: [
                              const Text(
                                'LALA',
                                style: TextStyle(
                                  fontSize: 34,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w900,
                                  color: _homeJade,
                                ),
                              ),
                              const SizedBox(width: 16),
                              if (wide)
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    t(
                                      '한국을 듣는\n새로운 여행',
                                      'A new way to\nexplore Korea',
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              if (wide)
                                Expanded(child: _searchField())
                              else
                                const Spacer(),
                              const SizedBox(width: 12),
                              IconButton(
                                tooltip: t('이용 안내', 'Travel guide'),
                                onPressed: _guide,
                                icon: const Icon(Icons.info_outline),
                              ),
                            ],
                          ),
                        if (!wide) ...[
                          const SizedBox(height: 16),
                          _searchField(),
                        ],
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(
                            height: wide ? 250 : 215,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  'assets/images/lala-hwaseong-haenggung.png',
                                  fit: BoxFit.cover,
                                  alignment: Alignment.centerRight,
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFF0F8F4),
                                        Color(0xEDF0F8F4),
                                        Color(0x08F0F8F4),
                                      ],
                                      stops: [0, .38, 1],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(wide ? 32 : 22),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t(
                                            '처음 만나는 한국,\n이야기로 더 가까이',
                                            'Discover Korea,\none story at a time',
                                          ),
                                          style: TextStyle(
                                            fontSize: wide ? 30 : 23,
                                            height: 1.3,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          t('LALA 이용 안내', 'Your guide to LALA'),
                                          style: const TextStyle(
                                            color: _homeJade,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                          onPressed: _guide,
                                          child: Text(t('둘러보기 →', 'Explore →')),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _travelStatusCard(),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: widget.onLocate,
                              icon: const Icon(Icons.my_location, size: 18),
                              label: Text(t('내 주변', 'Near me')),
                            ),
                            OutlinedButton.icon(
                              onPressed: widget.onPlan,
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                              ),
                              label: Text(
                                widget.travelMode == 'plan_trip'
                                    ? t('여행 계획 중', 'Planning a trip')
                                    : t('여행 계획', 'Plan a trip'),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: widget.onManualRegion,
                              icon: const Icon(Icons.location_on_outlined),
                              label: Text(
                                '${widget.region?.label(widget.language) ?? (widget.travelMode == 'undecided' ? t('여행지를 선택해 주세요', 'Choose a destination') : t('현재 탐색 지역', 'Exploring this area'))}  ›',
                              ),
                            ),
                          ],
                        ),
                        _heading(
                          widget.travelMode == 'undecided'
                              ? t('어디로 떠나볼까요?', 'Where would you like to go?')
                              : t('가까운 지역', 'Nearby areas'),
                          t('지역 변경 ›', 'Change area ›'),
                          widget.onManualRegion,
                        ),
                        SizedBox(
                          height: 118,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: regions.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(width: wide ? 44 : 16),
                            itemBuilder: (context, i) {
                              final region = regions[i];
                              final selected = widget.region?.id == region.id;
                              return SizedBox(
                                width: 94,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () => widget.onRegion(region),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 76,
                                        height: 76,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: selected
                                              ? const Color(0xFFD4E9E1)
                                              : const Color(0xFFEDF3F0),
                                          border: Border.all(
                                            color: selected
                                                ? _homeJade
                                                : const Color(0xFFE4EDE8),
                                            width: 2,
                                          ),
                                        ),
                                        child: Icon(
                                          [
                                            Icons.account_balance_outlined,
                                            Icons.landscape_outlined,
                                            Icons.park_outlined,
                                            Icons.location_city_outlined,
                                            Icons.explore_outlined,
                                          ][i],
                                          color: _homeJade,
                                          size: 32,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        region.label(widget.language),
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in [
                              ('all', t('전체', 'All')),
                              ('attraction', t('명소', 'Sights')),
                              ('restaurant', t('음식 · 카페', 'Food & cafés')),
                              ('culture_venue', t('문화', 'Culture')),
                              ('event', t('축제 · 행사', 'Events')),
                            ])
                              ChoiceChip(
                                label: Text(item.$2),
                                selected: _category == item.$1,
                                onSelected: (_) =>
                                    setState(() => _category = item.$1),
                                selectedColor: const Color(0xFFDCEEE6),
                                showCheckmark: false,
                              ),
                          ],
                        ),
                        SizedBox(key: _resultsKey),
                        _heading(
                          _query.isNotEmpty
                              ? t(
                                  '‘${_search.text.trim()}’ 검색 결과 ${visible.length}곳',
                                  '${visible.length} results for ‘${_search.text.trim()}’',
                                )
                              : _savedOnly
                              ? t('저장한 장소', 'Saved places')
                              : t('지금 둘러보기 좋은 곳', 'Places to explore'),
                          t('지도 보기 ›', 'View map ›'),
                          widget.onMap,
                        ),
                        if (widget.loading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: LinearProgressIndicator(),
                          ),
                        if (widget.error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t(
                                      '장소를 불러오지 못했어요. 다시 시도해 주세요.',
                                      'Could not load places. Please try again.',
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: widget.onRefresh,
                                  child: Text(t('다시 시도', 'Retry')),
                                ),
                              ],
                            ),
                          ),
                        if (visible.isEmpty && !widget.loading)
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F5F2),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.travel_explore,
                                  size: 34,
                                  color: _homeJade,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _query.isNotEmpty
                                      ? t(
                                          '‘${_search.text.trim()}’과 일치하는 장소가 없어요.',
                                          'No places match ‘${_search.text.trim()}’.',
                                        )
                                      : t(
                                          widget.travelMode == 'undecided'
                                              ? '지역을 선택하면 장소를 보여드릴게요.'
                                              : '조건에 맞는 장소가 아직 없어요.',
                                          widget.travelMode == 'undecided'
                                              ? 'Choose an area to discover places.'
                                              : 'No places match yet.',
                                        ),
                                ),
                                TextButton(
                                  onPressed: _query.isNotEmpty
                                      ? () {
                                          _search.clear();
                                          setState(() => _query = '');
                                        }
                                      : widget.onManualRegion,
                                  child: Text(
                                    _query.isNotEmpty
                                        ? t('검색어 지우기', 'Clear search')
                                        : t(
                                            '다른 지역 둘러보기',
                                            'Explore another area',
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        LayoutBuilder(
                          builder: (context, grid) {
                            final width =
                                (grid.maxWidth - (columns - 1) * 14) / columns;
                            return Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              children: visible
                                  .take(12)
                                  .map(
                                    (p) => SizedBox(
                                      width: width,
                                      child: _placeCard(p),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                        if (_recentPlaces.isNotEmpty) ...[
                          _heading(
                            t('최근 본 장소', 'Recently viewed'),
                            t('지도 보기 ›', 'View map ›'),
                            widget.onMap,
                          ),
                          SizedBox(
                            height: 104,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _recentPlaces.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final place = _recentPlaces[index];
                                return _RecentPlaceCard(
                                  place: place,
                                  language: widget.language,
                                  onTap: () => _openPlace(place),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Flex(
                          direction: wide ? Axis.horizontal : Axis.vertical,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (wide)
                              Expanded(child: _planCard())
                            else
                              _planCard(),
                            SizedBox(
                              width: wide ? 18 : 0,
                              height: wide ? 0 : 16,
                            ),
                            if (wide)
                              Expanded(child: _savedCard())
                            else
                              _savedCard(),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _planCard() => _actionCard(
    Icons.route_outlined,
    t('이야기를 따라 걷는 코스', 'Follow a trail of stories'),
    t(
      '여행할 지역의 장소로 나만의 하루를 계획해요.',
      'Build your day around places in your destination.',
    ),
    t('코스 계획하기 →', 'Plan a route →'),
    widget.onPlan,
  );

  Widget _travelStatusCard() {
    final slots = widget.dailyPlan?.slots ?? const <LalaPlanSlot>[];
    final hasPlan = slots.isNotEmpty;
    final regionLabel =
        widget.region?.label(widget.language) ??
        (widget.travelMode == 'explore_now'
            ? t('현재 위치 주변', 'Around your current location')
            : t('여행지를 선택해 주세요', 'Choose a destination'));
    final weatherLabel = widget.weather == null
        ? null
        : '${temperatureLabel(widget.weather!.temp)} · ${dustSituationLabel(widget.weather!.dust, widget.language)}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4E8E1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasPlan ? Icons.route_outlined : Icons.explore_outlined,
              color: _homeJade,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPlan
                      ? t('오늘의 여행 일정', 'Your plan for today')
                      : widget.travelMode == 'undecided'
                      ? t('먼저 여행지를 선택해 주세요', 'Choose a destination to begin')
                      : t(
                          '$regionLabel 여행을 둘러보고 있어요',
                          'Exploring $regionLabel',
                        ),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  hasPlan
                      ? t(
                          '${slots.length}개 장소가 일정에 있어요${weatherLabel == null ? '' : ' · $weatherLabel'}',
                          '${slots.length} stops in your plan${weatherLabel == null ? '' : ' · $weatherLabel'}',
                        )
                      : weatherLabel ??
                            t(
                              '주변 장소와 로컬 이야기를 찾아보세요.',
                              'Discover nearby places and local stories.',
                            ),
                  style: const TextStyle(color: Color(0xFF60706A)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: hasPlan ? widget.onPlan : widget.onMap,
                      child: Text(
                        hasPlan
                            ? t('내 여행 계속하기', 'Continue my trip')
                            : t('지도에서 보기', 'View on map'),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onManualRegion,
                      child: Text(t('지역 변경', 'Change area')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedCard() {
    final savedPlaces = widget.places
        .where((place) => widget.savedIds.contains(place.placeId))
        .take(3)
        .toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3EAE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bookmark_border, color: _homeJade, size: 30),
          const SizedBox(height: 12),
          Text(
            t('다시 만나고 싶은 곳', 'Places to come back to'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              '${widget.savedIds.length}개의 장소를 저장했어요.',
              '${widget.savedIds.length} saved places.',
            ),
            style: const TextStyle(color: Color(0xFF77827E)),
          ),
          if (savedPlaces.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final place in savedPlaces) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PlaceImage(place: place, width: 64, height: 52),
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.savedIds.length > savedPlaces.length)
                  Text(
                    '+${widget.savedIds.length - savedPlaces.length}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onSavedPlaces,
            child: Text(t('저장한 장소 보기 →', 'View saved places →')),
          ),
          if (savedPlaces.isNotEmpty)
            OutlinedButton.icon(
              onPressed: widget.onPlan,
              icon: const Icon(Icons.route_outlined),
              label: Text(t('일정 열기', 'Open your plan')),
            ),
        ],
      ),
    );
  }

  Widget _actionCard(
    IconData icon,
    String title,
    String subtitle,
    String action,
    VoidCallback callback,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE3EAE7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _homeJade, size: 30),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: Color(0xFF77827E))),
        const SizedBox(height: 8),
        TextButton(onPressed: callback, child: Text(action)),
      ],
    ),
  );
}
