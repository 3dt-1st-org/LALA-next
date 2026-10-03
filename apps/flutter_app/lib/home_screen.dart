import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'app/lala_visual_tokens.dart';
import 'manual_location_options.dart';
import 'features/place/widgets/place_image.dart';
import 'shared/l10n/place_labels.dart';
part 'lala_guide.dart';

const _homeJade = LalaVisualColors.primary;
const _homeInk = LalaVisualColors.ink;

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
    this.savedPlaces = const [],
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
  final List<LalaPlace> savedPlaces;
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

class DiscoveryHomeState extends State<DiscoveryHome> {
  String _query = '', _category = 'all';
  final bool _savedOnly = false;
  String t(String ko, String en) => widget.language == 'ko' ? ko : en;
  TextEditingController get _search => widget.searchController;
  final _resultsKey = GlobalKey();
  void updateSearch(String value) =>
      setState(() => _query = value.trim().toLowerCase());

  void _openPlace(LalaPlace place) => widget.onPlace(place);

  @override
  void initState() {
    super.initState();
    _query = _search.text.trim().toLowerCase();
  }

  double _sectionFontSize(double regular) {
    final width = MediaQuery.sizeOf(context).width;
    return width < 400
        ? 16
        : width < 680
        ? 18
        : regular;
  }

  Widget _sectionHeader(Widget title, Widget action) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (box.maxWidth / scale < 280) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: 8),
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: action),
          ),
        ],
      );
    },
  );

  Widget _heading(String title, String action, VoidCallback callback) =>
      Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: _sectionHeader(
          Text(
            title,
            style: TextStyle(
              fontSize: _sectionFontSize(22),
              fontWeight: FontWeight.w800,
            ),
          ),
          TextButton.icon(
            onPressed: callback,
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(action),
          ),
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
      border: Border.all(color: const Color(0xFFDCE7E1)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _openPlace(place),
            child: _photo(place, height: 150),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (switch (place.category) {
                    'attraction' => t('명소', 'Sights'),
                    'restaurant' => t('음식 · 카페', 'Food & cafés'),
                    'culture_venue' => t('문화', 'Culture'),
                    'event' => t('축제 · 행사', 'Events'),
                    _ => t('장소', 'Place'),
                  }).toUpperCase(),
                  style: const TextStyle(fontSize: 11, color: _homeJade),
                ),
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _openPlace(place),
                        child: Text(
                          placeDisplayName(place, widget.language),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: t('장소 저장', 'Save place'),
                      onPressed: () => widget.onSave(place.placeId),
                      iconSize: 20,
                      icon: Icon(
                        widget.savedIds.contains(place.placeId)
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                      ),
                    ),
                  ],
                ),
                if (widget.language != 'ko' &&
                    place.nameKo?.trim().isNotEmpty == true)
                  Text(
                    place.nameKo!.trim(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF62766F),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${t('탐색 지역 기준', 'From exploration area')} · ${_distanceLabel(place.distanceM)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF62766F),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _openPlace(place),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFEEF5F1),
                    foregroundColor: _homeJade,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.headphones_outlined, size: 18),
                  label: Text(t('해설 듣기', 'Listen to story')),
                ),
              ],
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

  Widget _searchField() => TextField(
    key: const ValueKey('home-search'),
    controller: _search,
    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    decoration: InputDecoration(
      hintText: t('이 지역의 장소 이름 검색', 'Search places in this area'),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDE5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
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
        colorScheme: LalaDesignTheme.colorScheme,
        textTheme: LalaDesignTheme.textTheme(Theme.of(context).textTheme),
      ),
      child: ColoredBox(
        color: Colors.white,
        child: LayoutBuilder(
          builder: (context, box) {
            final compact = box.maxWidth < 680;
            final columns = box.maxWidth >= 680
                ? 3
                : box.maxWidth >= 440
                ? 2
                : 1;
            return SingleChildScrollView(
              key: const PageStorageKey('discovery-home-scroll'),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1024),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: box.maxWidth >= 680 ? 30 : 20,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'LALA',
                              style: TextStyle(
                                fontSize: 28,
                                letterSpacing: 3,
                                fontWeight: FontWeight.w700,
                                color: _homeJade,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _guide,
                                  icon: const Icon(Icons.info_outline),
                                  label: Text(t('이용 안내', 'How to use')),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: Color(0xFFDCE7E1), height: 1),
                        const SizedBox(height: 26),
                        if (widget.dailyPlan?.slots.any(
                              (slot) => slot.place != null,
                            ) ??
                            false) ...[
                          _travelStatusCard(),
                          const SizedBox(height: 20),
                        ],
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7F3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final label = Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t('탐색 지역', 'Exploring'),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF62766F),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.travelMode == 'explore_now'
                                              ? t(
                                                  '현재 위치 주변',
                                                  'Near your location',
                                                )
                                              : widget.region?.label(
                                                      widget.language,
                                                    ) ??
                                                    t(
                                                      '지역을 선택해 주세요',
                                                      'Choose an area',
                                                    ),
                                          style: const TextStyle(fontSize: 17),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                              final actions = Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  OutlinedButton(
                                    onPressed: widget.onManualRegion,
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: _homeInk,
                                      side: const BorderSide(
                                        color: Color(0xFFDCE7E1),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 18,
                                      ),
                                    ),
                                    child: Text(t('지역 변경', 'Change area')),
                                  ),
                                  TextButton.icon(
                                    onPressed: widget.onLocate,
                                    icon: const Icon(Icons.my_location),
                                    label: Text(t('현재 위치로', 'Use my location')),
                                  ),
                                ],
                              );
                              if (constraints.maxWidth /
                                      (MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) /
                                          14) <
                                  480) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    label,
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: actions,
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: label),
                                  const SizedBox(width: 16),
                                  actions,
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          t('가까운 곳부터, 나답게', 'A LITTLE CLOSER TO KOREA'),
                          style: const TextStyle(
                            color: _homeJade,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t(
                            '오늘은 어디를 둘러볼까요?',
                            'Find your next little discovery.',
                          ),
                          style: TextStyle(
                            fontSize: box.maxWidth < 400
                                ? 22
                                : compact
                                ? 26
                                : 32,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _searchField(),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final item in [
                                ('all', t('전체', 'All')),
                                ('attraction', t('명소', 'Sights')),
                                ('restaurant', t('음식 · 카페', 'Food & cafés')),
                                ('culture_venue', t('문화', 'Culture')),
                                ('event', t('축제 · 행사', 'Events')),
                              ])
                                Padding(
                                  padding: EdgeInsets.only(
                                    right: compact ? 6 : 8,
                                  ),
                                  child: ChoiceChip(
                                    label: Text(item.$2),
                                    selected: _category == item.$1,
                                    onSelected: (_) =>
                                        setState(() => _category = item.$1),
                                    selectedColor: _homeJade,
                                    backgroundColor: Colors.white,
                                    labelStyle: TextStyle(
                                      color: _category == item.$1
                                          ? Colors.white
                                          : _homeInk,
                                      fontSize: compact ? 12 : 13,
                                    ),
                                    shape: const StadiumBorder(),
                                    side: BorderSide(
                                      color: _category == item.$1
                                          ? _homeJade
                                          : const Color(0xFFDCE7E1),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 6 : 12,
                                      vertical: compact ? 8 : 12,
                                    ),
                                    showCheckmark: false,
                                  ),
                                ),
                            ],
                          ),
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
                          t('지도에서 보기', 'View on map'),
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
                            if (compact) {
                              return SingleChildScrollView(
                                key: const ValueKey('home-place-carousel'),
                                scrollDirection: Axis.horizontal,
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final place in visible.take(6))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 14,
                                          ),
                                          child: SizedBox(
                                            width: grid.maxWidth * 0.86,
                                            child: _placeCard(place),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            final width =
                                (grid.maxWidth - (columns - 1) * 14) / columns;
                            return Wrap(
                              spacing: 14,
                              runSpacing: 14,
                              children: visible
                                  .take(6)
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
                        const SizedBox(height: 28),
                        _savedCard(),
                        if (widget.dailyPlan == null) ...[
                          const SizedBox(height: 16),
                          _planCard(),
                        ],
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
    t('나만의 하루 일정', 'Plan your day'),
    t(
      '여행할 지역의 장소로 나만의 하루를 계획해요.',
      'Build your day around places in your destination.',
    ),
    t('일정 만들기', 'Create plan'),
    widget.onPlan,
  );

  Widget _travelStatusCard() {
    final places = widget.dailyPlan!.slots
        .where((slot) => slot.place != null)
        .map((slot) => slot.place!)
        .toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('오늘의 여행', 'Your trip today'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              '계정에 저장된 오늘 일정 · ${places.length}곳',
              'Today’s saved itinerary · ${places.length} places',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            places.map((p) => placeDisplayName(p, widget.language)).join(' → '),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: widget.onPlan,
            icon: const Icon(Icons.route_outlined),
            label: Text(t('오늘 일정 보기', 'View today’s plan')),
          ),
        ],
      ),
    );
  }

  Widget _savedCard() {
    final places = widget.savedPlaces
        .where((p) => widget.savedIds.contains(p.placeId))
        .take(3)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          Text(
            '${t('저장한 장소', 'Saved places')} · ${widget.savedIds.length}',
            style: TextStyle(
              fontSize: _sectionFontSize(22),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton(
            onPressed: widget.onSavedPlaces,
            child: Text(t('전체 보기', 'View all')),
          ),
        ),
        Text(
          t('탐색 지역과 관계없이 저장한 장소', 'Saved places, across all areas'),
          style: const TextStyle(color: Color(0xFF62766F), fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (places.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFDCE7E1)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              widget.savedIds.isEmpty
                  ? t(
                      '북마크를 눌러 마음에 드는 장소를 모아보세요.',
                      'Tap a bookmark to keep your favourite places here.',
                    )
                  : t(
                      '전체 보기에서 저장한 장소를 확인해 주세요.',
                      'Open View all to see your saved places.',
                    ),
            ),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 600 ? 2 : 1;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: places
                  .map(
                    (place) => SizedBox(
                      width: (box.maxWidth - (columns - 1) * 16) / columns,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDCE7E1)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: PlaceImage(
                                place: place,
                                width: 52,
                                height: 58,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: () => _openPlace(place),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      placeDisplayName(place, widget.language),
                                    ),
                                    if (widget.language != 'ko' &&
                                        place.nameKo != null)
                                      Text(
                                        place.nameKo!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF62766F),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: t('저장 해제', 'Remove saved place'),
                              onPressed: () => widget.onSave(place.placeId),
                              icon: const Icon(Icons.bookmark, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _cardHeader(
    IconData icon,
    String title,
    String action,
    VoidCallback onPressed,
  ) => _sectionHeader(
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _homeJade, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: _sectionFontSize(20),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
    TextButton(onPressed: onPressed, child: Text(action)),
  );

  Widget _actionCard(
    IconData icon,
    String title,
    String subtitle,
    String action,
    VoidCallback callback,
  ) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 400 ? 14 : 22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE3EAE7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader(icon, title, action, callback),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: Color(0xFF77827E))),
      ],
    ),
  );
}
