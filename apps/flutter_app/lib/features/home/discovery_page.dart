import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import '../../core/backend/lala_backend.dart';
import '../../core/config/app_config.dart';
import '../../core/location/lala_location.dart';
import '../../core/location/region_context.dart';
import '../../core/routing/lala_route_paths.dart';
import '../../core/state/plan_context_store.dart';
import '../../core/state/saved_place_store.dart';
import '../../home_screen.dart';
import '../trip_library/data/trip_library_store.dart';
import '../trip_library/domain/trip_library_models.dart';
import '../../manual_location_options.dart';
import '../location/widgets/manual_location_sheet.dart';
import '../onboarding/onboarding_state.dart';
import '../settings/data/privacy_settings_store.dart';
import '../preferences/data/travel_preferences_store.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
    super.key,
    required this.backendFactory,
    required this.initialConfig,
    required this.locationProvider,
  });
  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;
  final LalaLocationProvider locationProvider;
  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  final _search = TextEditingController();
  List<LalaPlace> _places = const [];
  LalaWeather? _weather;
  bool _loading = false;
  String? _error;
  int _epoch = 0;
  int _planEpoch = 0;
  LalaDailyPlan? _todayPlan;
  List<LalaPlace> _savedPlaces = const [];
  int _savedEpoch = 0;
  String _todayKey = tripLibraryDateKey();
  Timer? _todayTimer;

  @override
  void initState() {
    super.initState();
    RegionContextStore.listenable.addListener(_reload);
    OnboardingState.languageListenable.addListener(_reload);
    PrivacySettingsStore.instance.addListener(_privacyChanged);
    unawaited(TravelPreferencesStore.instance.ensureLoaded());
    _privacyChanged();
    _reload();
    TripLibraryStore.instance.addListener(_loadTodayPlan);
    _loadTodayPlan();
    SavedPlaceStore.listenable.addListener(_loadSavedPlaces);
    _loadSavedPlaces();
    _todayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_todayKey != tripLibraryDateKey()) {
        _loadTodayPlan();
      }
    });
  }

  @override
  void dispose() {
    _epoch++;
    _planEpoch++;
    _savedEpoch++;
    SavedPlaceStore.listenable.removeListener(_loadSavedPlaces);
    _todayTimer?.cancel();
    TripLibraryStore.instance.removeListener(_loadTodayPlan);
    RegionContextStore.listenable.removeListener(_reload);
    OnboardingState.languageListenable.removeListener(_reload);
    PrivacySettingsStore.instance.removeListener(_privacyChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPlaces() async {
    final epoch = ++_savedEpoch;
    final ids = SavedPlaceStore.current.toList().reversed.take(3).toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _savedPlaces = const []);
      return;
    }
    final backend = widget.backendFactory(
      widget.initialConfig.copyWith(lang: OnboardingState.language),
    );
    try {
      final result = await backend.lookupPlaces(ids);
      if (mounted && epoch == _savedEpoch) {
        setState(
          () => _savedPlaces = result.ok
              ? [
                  for (final id in ids)
                    ...?result.data?.places.where((place) => place.placeId == id),
                ]
              : const [],
        );
      }
    } on Object {
      if (mounted && epoch == _savedEpoch) {
        setState(() => _savedPlaces = const []);
      }
    } finally {
      backend.close();
    }
  }

  Future<void> _loadTodayPlan() async {
    final epoch = ++_planEpoch;
    final library = TripLibraryStore.instance;
    final today = tripLibraryDateKey();
    _todayKey = today;
    if (!library.accountConnected) {
      if (mounted) setState(() => _todayPlan = null);
      return;
    }
    try {
      final plan = await library.readSavedPlan(today);
      if (mounted && epoch == _planEpoch && today == tripLibraryDateKey()) {
        setState(() => _todayPlan = plan);
      }
    } on Object {
      if (mounted && epoch == _planEpoch) setState(() => _todayPlan = null);
    }
  }

  void _reload() => unawaited(_load());

  void _privacyChanged() {
    if (!PrivacySettingsStore.instance.locationRecommendationsEnabled &&
        RegionContextStore.current?.source == RegionSource.current) {
      RegionContextStore.clear();
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final region = RegionContextStore.current;
    setState(() {
      _loading = true;
      _error = null;
      _weather = null;
      _places = [];
    });
    // Never describe the default coordinates as the user's nearby location.
    if (region == null) {
      setState(() => _loading = false);
      return;
    }
    final backend = widget.backendFactory(
      widget.initialConfig.copyWith(
        lat: region.lat,
        lng: region.lng,
        lang: OnboardingState.language,
      ),
    );
    try {
      final places = await backend.getPlaces();
      if (!places.ok || places.data == null) {
        throw StateError('places unavailable');
      }
      LalaWeather? weather;
      try {
        final response = await backend.getWeather();
        if (response.ok) weather = response.data;
      } on Object {
        /* Place discovery remains available without weather. */
      }
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _places = places.data!.places;
        _weather = weather;
      });
    } on Object {
      if (!mounted || epoch != _epoch) return;
      setState(
        () => _error = OnboardingState.language == 'ko'
            ? '장소를 불러오지 못했어요. 다시 시도해 주세요.'
            : 'Could not load places. Please try again.',
      );
    } finally {
      backend.close();
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _chooseRegion() async {
    final selected = await showModalBottomSheet<ManualLocationOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ManualLocationSheet(language: OnboardingState.language),
    );
    if (selected != null && mounted) {
      await RegionContextStore.setAndFlush(RegionContext.manual(selected));
    }
  }

  Future<void> _locate() async {
    final ko = OnboardingState.language == 'ko';
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ko ? '현재 위치 사용' : 'Use current location'),
        content: Text(
          ko
              ? '가까운 장소를 찾기 위해 현재 위치를 사용합니다. 좌표는 기기에 저장하지 않습니다.'
              : 'Use your location to find nearby places. Coordinates are not stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ko ? '취소' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ko ? '허용' : 'Allow'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    try {
      final result = await widget.locationProvider.requestCurrentLocation();
      if (!mounted) return;
      if (result.location != null &&
          result.status == LalaLocationResultStatus.found) {
        await PrivacySettingsStore.instance.setLocationRecommendationsEnabled(
          true,
        );
        await RegionContextStore.setAndFlush(
          RegionContext.current(
            lat: result.location!.lat,
            lng: result.location!.lng,
          ),
        );
      } else if (result.status == LalaLocationResultStatus.permanentlyDenied) {
        await context.push(LalaRoutePaths.privacyLocation);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ko
                  ? '위치를 확인하지 못했어요. 현재 위치로 버튼을 눌러 다시 시도해 주세요.'
                  : 'Location unavailable. Tap Use my location to retry.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ko ? '위치를 확인하지 못했어요.' : 'Location unavailable.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      SavedPlaceStore.listenable,
      PlanContextStore.listenable,
      TravelPreferencesStore.instance,
      RegionContextStore.listenable,
    ]),
    builder: (context, _) {
      final region = RegionContextStore.current;
      final manual = manualLocationOptions.where(
        (option) => option.id == region?.regionId,
      );
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: DiscoveryHome(
            searchController: _search,
            travelStyles: TravelPreferencesStore.instance.value.interests
                .map(
                  (value) => switch (value.name) {
                    'localFood' || 'cafe' => 'food',
                    'shopping' || 'arts' => 'kculture',
                    _ => value.name,
                  },
                )
                .toList(),
            travelMode: region == null
                ? 'undecided'
                : region.source == RegionSource.current
                ? 'explore_now'
                : 'plan_trip',
            language: OnboardingState.language,
            loading: _loading,
            error: _error,
            places: _places,
            weather: _weather,
            dailyPlan: _todayPlan,
            savedIds: SavedPlaceStore.current,
            savedPlaces: _savedPlaces,
            lat: region?.lat ?? widget.initialConfig.lat,
            lng: region?.lng ?? widget.initialConfig.lng,
            region: manual.isEmpty ? null : manual.first,
            onRegion: (option) =>
                RegionContextStore.set(RegionContext.manual(option)),
            onManualRegion: _chooseRegion,
            onLocate: _locate,
            onSave: SavedPlaceStore.toggle,
            onPlace: (place) => context.push(
              LalaRoutePaths.placeDetailFor(place.placeId),
              extra: place,
            ),
            onMap: () => context.go(LalaRoutePaths.mapRoute),
            onSavedPlaces: () => context.push(LalaRoutePaths.savedPlaces),
            onPlan: () {
              if (_todayPlan != null) PlanContextStore.set(_todayPlan);
              context.go(LalaRoutePaths.plan);
            },
            onSettings: () => context.go(LalaRoutePaths.profile),
            onRefresh: _reload,
          ),
        ),
      );
    },
  );
}
