// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'kakao_map_view.dart';

void main() {
  runApp(const LalaApp());
}

typedef LalaBackendFactory = LalaBackend Function(LalaAppConfig config);

class LalaApp extends StatelessWidget {
  const LalaApp({
    super.key,
    this.backendFactory = LalaApiBackend.new,
    this.initialConfig = const LalaAppConfig.fromEnvironment(),
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF2B6CB0),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF2B6CB0),
          secondary: const Color(0xFFF5C842),
          tertiary: const Color(0xFFC53030),
          surface: const Color(0xFFF7FAFC),
          surfaceContainerLowest: Colors.white,
        );

    return MaterialApp(
      title: 'LALA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        fontFamily: 'Pretendard',
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: LalaHomePage(
        backendFactory: backendFactory,
        initialConfig: initialConfig,
      ),
    );
  }
}

class LalaAppConfig {
  const LalaAppConfig({
    required this.baseUri,
    this.bearerToken = '',
    this.apiKey = '',
    this.kakaoJavascriptKey = '',
    this.lat = 37.2636,
    this.lng = 127.0286,
    this.radiusM = 50000,
  });

  const LalaAppConfig.fromEnvironment()
    : baseUri = const String.fromEnvironment(
        'LALA_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8080',
      ),
      bearerToken = const String.fromEnvironment('LALA_API_BEARER_TOKEN'),
      apiKey = const String.fromEnvironment('LALA_IOS_API_KEY'),
      kakaoJavascriptKey = const String.fromEnvironment('KAKAO_JAVASCRIPT_KEY'),
      lat = 37.2636,
      lng = 127.0286,
      radiusM = 50000;

  final String baseUri;
  final String bearerToken;
  final String apiKey;
  final String kakaoJavascriptKey;
  final double lat;
  final double lng;
  final int radiusM;

  bool get hasAuth => bearerToken.trim().isNotEmpty || apiKey.trim().isNotEmpty;
  LalaAuthMode get authMode =>
      LalaAuthMode.fromCredentials(bearerToken: bearerToken, apiKey: apiKey);

  LalaAppConfig copyWith({
    String? baseUri,
    String? bearerToken,
    String? apiKey,
    String? kakaoJavascriptKey,
    double? lat,
    double? lng,
    int? radiusM,
  }) {
    return LalaAppConfig(
      baseUri: baseUri ?? this.baseUri,
      bearerToken: bearerToken ?? this.bearerToken,
      apiKey: apiKey ?? this.apiKey,
      kakaoJavascriptKey: kakaoJavascriptKey ?? this.kakaoJavascriptKey,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusM: radiusM ?? this.radiusM,
    );
  }
}

abstract class LalaBackend {
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth();

  Future<LalaEnvelope<LalaReadiness>> getReadiness();

  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces();

  Future<LalaEnvelope<LalaWeather>> getWeather();

  Future<LalaEnvelope<LalaIntervention>> getIntervention();

  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan();

  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
  });

  Future<LalaAudioResponse> createDocentAudio({required String script});

  void close();
}

class LalaApiBackend implements LalaBackend {
  LalaApiBackend(this.config)
    : _client = LalaApiClient(
        baseUri: Uri.parse(config.baseUri),
        bearerToken: config.bearerToken,
        apiKey: config.apiKey,
      );

  final LalaAppConfig config;
  final LalaApiClient _client;

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getHealth() {
    return _client.getHealth();
  }

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() {
    return _client.getReadiness();
  }

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() {
    return _client.getPlaces(
      lat: config.lat,
      lng: config.lng,
      radiusM: config.radiusM,
    );
  }

  @override
  Future<LalaEnvelope<LalaWeather>> getWeather() {
    return _client.getWeather(lat: config.lat, lng: config.lng);
  }

  @override
  Future<LalaEnvelope<LalaIntervention>> getIntervention() {
    return _client.getIntervention(
      lat: config.lat,
      lng: config.lng,
      radiusM: config.radiusM,
    );
  }

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan() {
    return _client.createDailyPlan(
      lat: config.lat,
      lng: config.lng,
      radiusM: config.radiusM,
    );
  }

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
  }) {
    return _client.createDocentScript(
      placeId: place.placeId,
      category: place.category,
      language: 'ko',
      mode: 'brief',
    );
  }

  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) {
    return _client.createDocentAudio(script: script, language: 'ko');
  }

  @override
  void close() {
    _client.close();
  }
}

class LalaHomePage extends StatefulWidget {
  const LalaHomePage({
    required this.backendFactory,
    required this.initialConfig,
    super.key,
  });

  final LalaBackendFactory backendFactory;
  final LalaAppConfig initialConfig;

  @override
  State<LalaHomePage> createState() => _LalaHomePageState();
}

class _LalaHomePageState extends State<LalaHomePage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _bearerTokenController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _kakaoJavascriptKeyController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late final TextEditingController _radiusController;
  late LalaBackend _backend;

  bool _loading = false;
  String? _error;
  LalaEnvelope<Map<String, dynamic>>? _health;
  LalaEnvelope<LalaReadiness>? _readiness;
  LalaEnvelope<LalaPlacesResponse>? _places;
  LalaEnvelope<LalaWeather>? _weather;
  LalaEnvelope<LalaIntervention>? _intervention;
  LalaEnvelope<LalaDailyPlan>? _dailyPlan;
  LalaEnvelope<LalaDocentScript>? _docentScript;
  LalaAudioResponse? _docentAudio;
  bool _audioLoading = false;
  String? _audioError;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _baseUrlController = TextEditingController(text: config.baseUri);
    _bearerTokenController = TextEditingController(text: config.bearerToken);
    _apiKeyController = TextEditingController(text: config.apiKey);
    _kakaoJavascriptKeyController = TextEditingController(
      text: config.kakaoJavascriptKey,
    );
    _latController = TextEditingController(text: config.lat.toStringAsFixed(4));
    _lngController = TextEditingController(text: config.lng.toStringAsFixed(4));
    _radiusController = TextEditingController(text: '${config.radiusM}');
    _backend = widget.backendFactory(config);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _backend.close();
    _baseUrlController.dispose();
    _bearerTokenController.dispose();
    _apiKeyController.dispose();
    _kakaoJavascriptKeyController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  LalaAppConfig _currentConfig() {
    return LalaAppConfig(
      baseUri: _baseUrlController.text.trim(),
      bearerToken: _bearerTokenController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      kakaoJavascriptKey: _kakaoJavascriptKeyController.text.trim(),
      lat: double.tryParse(_latController.text.trim()) ?? 37.2636,
      lng: double.tryParse(_lngController.text.trim()) ?? 127.0286,
      radiusM: int.tryParse(_radiusController.text.trim()) ?? 50000,
    );
  }

  Future<void> _refresh() async {
    final config = _currentConfig();
    setState(() {
      _loading = true;
      _error = null;
      _audioError = null;
      _docentAudio = null;
    });

    _backend.close();
    _backend = widget.backendFactory(config);

    try {
      final health = await _backend.getHealth();
      final readiness = await _backend.getReadiness();
      LalaEnvelope<LalaPlacesResponse>? places;
      LalaEnvelope<LalaWeather>? weather;
      LalaEnvelope<LalaIntervention>? intervention;
      LalaEnvelope<LalaDailyPlan>? dailyPlan;
      LalaEnvelope<LalaDocentScript>? docentScript;
      String? loadError;

      try {
        places = await _backend.getPlaces();
        weather = await _backend.getWeather();
        intervention = await _backend.getIntervention();
        dailyPlan = await _backend.createDailyPlan();
        final placeItems = places.data?.places ?? const <LalaPlace>[];
        final firstPlace = _featuredPlace(placeItems);
        if (firstPlace != null) {
          docentScript = await _backend.createDocentScript(place: firstPlace);
        }
      } on Object catch (error) {
        loadError = _safeErrorMessage(error);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _health = health;
        _readiness = readiness;
        _places = places;
        _weather = weather;
        _intervention = intervention;
        _dailyPlan = dailyPlan;
        _docentScript = docentScript;
        _docentAudio = null;
        _audioError = null;
        _error = loadError;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _safeErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _safeErrorMessage(Object error) {
    if (error is LalaApiException) {
      return '${error.code}: ${error.message}';
    }
    if (error is FormatException) {
      return error.message;
    }
    return 'Unable to load the LALA API snapshot.';
  }

  Future<void> _fetchAudio() async {
    final script = _docentScript?.data?.script;
    if (script == null || script.trim().isEmpty) {
      return;
    }

    setState(() {
      _audioLoading = true;
      _audioError = null;
    });

    try {
      final audio = await _backend.createDocentAudio(script: script);
      if (!mounted) {
        return;
      }
      setState(() {
        _docentAudio = audio;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _audioError = _safeErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _audioLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _currentConfig();
    final configPanel = _ConfigPanel(
      baseUrlController: _baseUrlController,
      bearerTokenController: _bearerTokenController,
      apiKeyController: _apiKeyController,
      kakaoJavascriptKeyController: _kakaoJavascriptKeyController,
      latController: _latController,
      lngController: _lngController,
      radiusController: _radiusController,
      loading: _loading,
      onRefresh: _refresh,
    );

    return Scaffold(
      endDrawer: Drawer(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: configPanel,
          ),
        ),
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) => _Dashboard(
            loading: _loading,
            error: _error,
            health: _health,
            readiness: _readiness,
            places: _places,
            weather: _weather,
            intervention: _intervention,
            dailyPlan: _dailyPlan,
            docentScript: _docentScript,
            docentAudio: _docentAudio,
            audioLoading: _audioLoading,
            audioError: _audioError,
            authMode: config.authMode,
            kakaoJavascriptKey: config.kakaoJavascriptKey,
            onFetchAudio: _fetchAudio,
            onRefresh: _refresh,
            onOpenSettings: () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
      ),
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.baseUrlController,
    required this.bearerTokenController,
    required this.apiKeyController,
    required this.kakaoJavascriptKeyController,
    required this.latController,
    required this.lngController,
    required this.radiusController,
    required this.loading,
    required this.onRefresh,
  });

  final TextEditingController baseUrlController;
  final TextEditingController bearerTokenController;
  final TextEditingController apiKeyController;
  final TextEditingController kakaoJavascriptKeyController;
  final TextEditingController latController;
  final TextEditingController lngController;
  final TextEditingController radiusController;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Backend',
      icon: Icons.dns_outlined,
      fill: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bearerTokenController,
            decoration: const InputDecoration(
              labelText: 'Bearer token',
              prefixIcon: Icon(Icons.key_outlined),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: apiKeyController,
            decoration: const InputDecoration(
              labelText: 'Migration API key',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: kakaoJavascriptKeyController,
            decoration: const InputDecoration(
              labelText: 'Kakao JavaScript key',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: latController,
                  decoration: const InputDecoration(
                    labelText: 'Lat',
                    prefixIcon: Icon(Icons.my_location_outlined),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: lngController,
                  decoration: const InputDecoration(
                    labelText: 'Lng',
                    prefixIcon: Icon(Icons.explore_outlined),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: radiusController,
            decoration: const InputDecoration(
              labelText: 'Radius meters',
              prefixIcon: Icon(Icons.radio_button_checked),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.sync),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.loading,
    required this.error,
    required this.health,
    required this.readiness,
    required this.places,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.audioLoading,
    required this.audioError,
    required this.authMode,
    required this.kakaoJavascriptKey,
    required this.onFetchAudio,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  final bool loading;
  final String? error;
  final LalaEnvelope<Map<String, dynamic>>? health;
  final LalaEnvelope<LalaReadiness>? readiness;
  final LalaEnvelope<LalaPlacesResponse>? places;
  final LalaEnvelope<LalaWeather>? weather;
  final LalaEnvelope<LalaIntervention>? intervention;
  final LalaEnvelope<LalaDailyPlan>? dailyPlan;
  final LalaEnvelope<LalaDocentScript>? docentScript;
  final LalaAudioResponse? docentAudio;
  final bool audioLoading;
  final String? audioError;
  final LalaAuthMode authMode;
  final String kakaoJavascriptKey;
  final VoidCallback onFetchAudio;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final topPlaces = places?.data?.places ?? const <LalaPlace>[];
    final topPlace = _featuredPlace(topPlaces);
    final visibleError = topPlaces.isEmpty ? null : error;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        return Stack(
          children: [
            Positioned.fill(
              child: _LegacyMapCanvas(
                places: topPlaces,
                selectedPlace: topPlace,
                weather: weather?.data,
                kakaoJavascriptKey: kakaoJavascriptKey,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _TopMapChrome(
                loading: loading,
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings,
              ),
            ),
            Positioned(
              right: 16,
              top: isWide ? 154 : 186,
              child: _WeatherMapPill(weather: weather?.data),
            ),
            Positioned(
              right: 16,
              top: isWide ? 218 : 304,
              child: _FloatingMapControls(onRefresh: onRefresh),
            ),
            if (visibleError != null)
              Positioned(
                left: 16,
                right: 16,
                top: isWide ? 112 : 132,
                child: _MapToast(
                  icon: Icons.error_outline,
                  label: visibleError,
                  color: Theme.of(context).colorScheme.errorContainer,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _MapBottomDock(
                isWide: isWide,
                places: topPlaces,
                source: places?.data?.source,
                topPlace: topPlace,
                weather: weather?.data,
                intervention: intervention?.data,
                dailyPlan: dailyPlan?.data,
                docentScript: docentScript?.data,
                docentAudio: docentAudio,
                audioLoading: audioLoading,
                audioError: audioError,
                onFetchAudio: onFetchAudio,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopMapChrome extends StatelessWidget {
  const _TopMapChrome({
    required this.loading,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 22,
                  offset: Offset(0, 8),
                  color: Color(0x18000000),
                ),
              ],
            ),
            child: Row(
              children: [
                const _LalaWordmark(),
                const Spacer(),
                const _NavTab(label: '지도', selected: true),
                const _NavTab(label: '코스'),
                const _NavTab(label: '도슨트'),
                Tooltip(
                  message: '개발 설정',
                  child: TextButton(
                    onPressed: onOpenSettings,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1A202C),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    child: const Text('설정'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CategoryChip(
                  label: '전체',
                  active: true,
                  color: colorScheme.primary,
                ),
                _CategoryChip(
                  label: '명소',
                  active: false,
                  color: const Color(0xFFC53030),
                ),
                _CategoryChip(
                  label: '맛집',
                  active: false,
                  color: const Color(0xFFF5C842),
                ),
                _CategoryChip(
                  label: '행사',
                  active: false,
                  color: const Color(0xFF2B6CB0),
                ),
                _CategoryChip(
                  label: '문화',
                  active: false,
                  color: const Color(0xFF0F766E),
                ),
              ],
            ),
          ),
          if (loading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
          foregroundColor: selected
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFF1A202C),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 28 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapBottomDock extends StatelessWidget {
  const _MapBottomDock({
    required this.isWide,
    required this.places,
    required this.source,
    required this.topPlace,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.audioLoading,
    required this.audioError,
    required this.onFetchAudio,
  });

  final bool isWide;
  final List<LalaPlace> places;
  final String? source;
  final LalaPlace? topPlace;
  final LalaWeather? weather;
  final LalaIntervention? intervention;
  final LalaDailyPlan? dailyPlan;
  final LalaDocentScript? docentScript;
  final LalaAudioResponse? docentAudio;
  final bool audioLoading;
  final String? audioError;
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final maxHeight = isWide ? 360.0 : 430.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [
            BoxShadow(
              blurRadius: 28,
              offset: Offset(0, -10),
              color: Color(0x22000000),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 10, 16, isWide ? 16 : 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: _FeaturedPlacePanel(
                    place: topPlace,
                    weather: weather,
                    intervention: intervention,
                    dailyPlan: dailyPlan,
                    docentScript: docentScript,
                    docentAudio: docentAudio,
                    audioLoading: audioLoading,
                    audioError: audioError,
                    source: source,
                    onFetchAudio: onFetchAudio,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedPlacePanel extends StatelessWidget {
  const _FeaturedPlacePanel({
    required this.place,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.audioLoading,
    required this.audioError,
    required this.source,
    required this.onFetchAudio,
  });

  final LalaPlace? place;
  final LalaWeather? weather;
  final LalaIntervention? intervention;
  final LalaDailyPlan? dailyPlan;
  final LalaDocentScript? docentScript;
  final LalaAudioResponse? docentAudio;
  final bool audioLoading;
  final String? audioError;
  final String? source;
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final currentPlace = place ?? _fallbackFeaturedPlace();
    final score = currentPlace.score;
    final components = score?.components;
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FeaturedPlaceHeader(place: currentPlace),
        const SizedBox(height: 12),
        _SignalGrid(
          localSpending: components?.localSpendingScore,
          demandDispersion: components?.demandDispersionScore,
          cultureRelevance: components?.cultureRelevanceScore,
          weatherFit: components?.weatherFitScore,
        ),
        const SizedBox(height: 12),
        _DocentSubtitle(
          place: currentPlace,
          script: docentScript?.script,
          action:
              intervention?.recommendedAction ??
              (slots.isEmpty ? null : slots.first.title),
          audioLoading: audioLoading,
          audioError: audioError,
          docentAudio: docentAudio,
          canFetchAudio:
              docentScript?.script.trim().isNotEmpty == true && !audioLoading,
          onFetchAudio: onFetchAudio,
        ),
        const SizedBox(height: 12),
        _PublicDataProofRow(
          source: source ?? currentPlace.source,
          weather: weather,
          score: score,
        ),
      ],
    );
  }

  LalaPlace _fallbackFeaturedPlace() {
    return const LalaPlace(
      placeId: 'hwaseong-haenggung',
      name: '화성행궁',
      category: 'attraction',
      lat: 37.2819,
      lng: 127.0142,
      address: '경기도 수원시 팔달구 정조로 825',
      distanceM: 145,
      source: 'public_mvp_snapshot',
      score: LalaPlaceScore(
        finalScore: 0.86,
        formulaVersion: 'local-value-v1',
        components: LalaPlaceScoreComponents(
          localSpendingScore: 0.82,
          demandDispersionScore: 0.78,
          weatherFitScore: 0.74,
          reviewQualityScore: null,
          cultureRelevanceScore: 0.91,
        ),
        dataBasis: 'public_mvp_snapshot',
        features: {
          'signals': <String>['tour_api', 'card_spending'],
        },
      ),
    );
  }
}

class _FeaturedPlaceHeader extends StatelessWidget {
  const _FeaturedPlaceHeader({required this.place});

  final LalaPlace place;

  @override
  Widget build(BuildContext context) {
    final score = place.score?.percent ?? 86;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            'assets/images/lala-hwaseong-haenggung.png',
            width: 94,
            height: 94,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CategoryBadge(category: place.category),
                  const Spacer(),
                  IconButton(
                    tooltip: '저장',
                    onPressed: () {},
                    icon: const Icon(Icons.favorite_border),
                  ),
                ],
              ),
              Text(
                place.nameKo ?? place.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 5),
              _InlineIconText(icon: Icons.place_outlined, label: place.address),
              const SizedBox(height: 7),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _InlineIconText(
                    icon: Icons.directions_walk,
                    label: '${place.distanceM}m',
                  ),
                  Text(
                    '로컬 점수',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF1A202C),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '$score',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFC53030),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    '/100',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineIconText extends StatelessWidget {
  const _InlineIconText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF64748B)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignalGrid extends StatelessWidget {
  const _SignalGrid({
    required this.localSpending,
    required this.demandDispersion,
    required this.cultureRelevance,
    required this.weatherFit,
  });

  final double? localSpending;
  final double? demandDispersion;
  final double? cultureRelevance;
  final double? weatherFit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SignalMeter(
              label: '내국인 소비',
              value: localSpending ?? 0.82,
              color: const Color(0xFFC53030),
            ),
          ),
          Expanded(
            child: _SignalMeter(
              label: '수요 분산',
              value: demandDispersion ?? 0.78,
              color: const Color(0xFFF5C842),
            ),
          ),
          Expanded(
            child: _SignalMeter(
              label: '문화 연계',
              value: cultureRelevance ?? 0.91,
              color: const Color(0xFF2B6CB0),
            ),
          ),
          Expanded(
            child: _SignalMeter(
              label: '날씨 적합',
              value: weatherFit ?? 0.74,
              color: const Color(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalMeter extends StatelessWidget {
  const _SignalMeter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bounded = value.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF1A202C),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            bounded.toStringAsFixed(2),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: bounded,
              minHeight: 7,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicDataProofRow extends StatelessWidget {
  const _PublicDataProofRow({
    required this.source,
    required this.weather,
    required this.score,
  });

  final String? source;
  final LalaWeather? weather;
  final LalaPlaceScore? score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '공공데이터 기반 정보',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w900,
            ),
          ),
          _ProofChip(label: 'TourAPI'),
          _ProofChip(label: _sourceLabel(source)),
          _ProofChip(
            label: score == null ? '카드소비' : _basisLabel(score!.dataBasis),
          ),
          _ProofChip(label: weather == null ? '날씨' : weather!.dust.gradeKo),
        ],
      ),
    );
  }
}

class _ProofChip extends StatelessWidget {
  const _ProofChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.check_circle, size: 17),
      label: Text(label),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFD7E3F5)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
    );
  }
}

class _PlaceRail extends StatelessWidget {
  const _PlaceRail({required this.places, required this.source});

  final List<LalaPlace> places;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final items = places.isEmpty
        ? const <LalaPlace>[]
        : places.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.expand_less, size: 18),
            const SizedBox(width: 6),
            Text(
              '추천 장소',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            _InlineMeta('${items.length}곳 · ${_sourceLabel(source)}'),
          ],
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const _EmptyPlaceState()
        else
          SizedBox(
            height: 164,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _LegacyPlaceCard(place: items[index], selected: index == 0),
            ),
          ),
      ],
    );
  }
}

class _RouteAndDocentPanel extends StatelessWidget {
  const _RouteAndDocentPanel({
    required this.place,
    required this.weather,
    required this.intervention,
    required this.dailyPlan,
    required this.docentScript,
    required this.docentAudio,
    required this.audioLoading,
    required this.audioError,
    required this.onFetchAudio,
  });

  final LalaPlace? place;
  final LalaWeather? weather;
  final LalaIntervention? intervention;
  final LalaDailyPlan? dailyPlan;
  final LalaDocentScript? docentScript;
  final LalaAudioResponse? docentAudio;
  final bool audioLoading;
  final String? audioError;
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final script = docentScript?.script;
    final canFetchAudio =
        script != null && script.trim().isNotEmpty && !audioLoading;
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _CompactInfoTile(
                icon: Icons.route,
                label: '오늘 코스',
                value: slots.isEmpty ? '날씨 기준 대체 동선 준비 중' : slots.first.title,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CompactInfoTile(
                icon: Icons.cloud,
                label: '날씨',
                value: weather == null
                    ? '확인 중'
                    : '${weather!.temp} · ${weather!.dust.gradeKo}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DocentSubtitle(
          place: place,
          script: script,
          action: intervention?.recommendedAction,
          audioLoading: audioLoading,
          audioError: audioError,
          docentAudio: docentAudio,
          canFetchAudio: canFetchAudio,
          onFetchAudio: onFetchAudio,
        ),
      ],
    );
  }
}

class _DocentSubtitle extends StatelessWidget {
  const _DocentSubtitle({
    required this.place,
    required this.script,
    required this.action,
    required this.audioLoading,
    required this.audioError,
    required this.docentAudio,
    required this.canFetchAudio,
    required this.onFetchAudio,
  });

  final LalaPlace? place;
  final String? script;
  final String? action;
  final bool audioLoading;
  final String? audioError;
  final LalaAudioResponse? docentAudio;
  final bool canFetchAudio;
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = _docentBody(place: place, script: script);
    final actionLabel = _docentActionLabel(place: place, action: action);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A202C),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B6CB0).withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          color: Color(0xFFF5C842),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            place == null
                                ? 'AI 도슨트 한 줄 설명'
                                : '${place!.name} 도슨트',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFBEE3F8),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (docentAudio != null)
                          Text(
                            '${docentAudio!.bytes.length} bytes',
                            style: const TextStyle(
                              color: Color(0xFFCBD5E0),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.38,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (actionLabel != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        actionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF5C842),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (audioError != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        audioError!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorScheme.tertiaryContainer),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: '자동 도슨트',
                onPressed: () {},
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.volume_up),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: canFetchAudio ? onFetchAudio : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: audioLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.volume_up),
                label: Text(audioLoading ? '음성 생성 중' : 'AI 도슨트 듣기'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('오늘 코스에 추가'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2B6CB0),
                  side: const BorderSide(color: Color(0xFF2B6CB0)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegacyMapCanvas extends StatelessWidget {
  const _LegacyMapCanvas({
    required this.places,
    required this.selectedPlace,
    required this.weather,
    required this.kakaoJavascriptKey,
  });

  final List<LalaPlace> places;
  final LalaPlace? selectedPlace;
  final LalaWeather? weather;
  final String kakaoJavascriptKey;

  @override
  Widget build(BuildContext context) {
    final selected = selectedPlace;
    final centerLat = selected?.lat ?? 37.2823;
    final centerLng = selected?.lng ?? 127.0179;
    final mapPlaces = places.isEmpty
        ? _fallbackMapPlaces()
        : places
              .take(12)
              .map(
                (place) => KakaoMapPlace(
                  id: place.placeId,
                  name: place.nameKo ?? place.name,
                  category: place.category,
                  lat: place.lat,
                  lng: place.lng,
                  scorePercent: place.score?.percent,
                  selected: place.placeId == selected?.placeId,
                ),
              )
              .toList();

    return Stack(
      children: [
        Positioned.fill(
          child: buildKakaoMapView(
            javascriptKey: kakaoJavascriptKey,
            centerLat: centerLat,
            centerLng: centerLng,
            level: 4,
            places: mapPlaces,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.02),
                    Colors.white.withValues(alpha: 0.26),
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 22,
          top: 260,
          child: _MapLocationLabel(
            label: weather?.location?.trim().isNotEmpty == true
                ? weather!.location!
                : '수원시',
          ),
        ),
      ],
    );
  }

  List<KakaoMapPlace> _fallbackMapPlaces() {
    return const [
      KakaoMapPlace(
        id: 'hwaseong-haenggung',
        name: '화성행궁',
        category: 'attraction',
        lat: 37.2819,
        lng: 127.0142,
        scorePercent: 86,
        selected: true,
      ),
      KakaoMapPlace(
        id: 'suwon-hwaseong',
        name: '수원화성',
        category: 'culture_venue',
        lat: 37.2870,
        lng: 127.0110,
        scorePercent: 82,
      ),
      KakaoMapPlace(
        id: 'haenggung-cafe-street',
        name: '행궁동 카페거리',
        category: 'restaurant',
        lat: 37.2828,
        lng: 127.0101,
        scorePercent: 78,
      ),
    ];
  }
}

class _MapLocationLabel extends StatelessWidget {
  const _MapLocationLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 5),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF1A202C),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _FloatingMapControls extends StatelessWidget {
  const _FloatingMapControls({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MapFab(
          tooltip: '내 위치',
          icon: Icons.my_location,
          label: '내 위치',
          onPressed: onRefresh,
        ),
        const SizedBox(height: 12),
        _MapFab(
          tooltip: '자동 도슨트',
          icon: Icons.auto_awesome,
          label: '자동 도슨트',
          onPressed: () {},
        ),
      ],
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.96),
          foregroundColor: Theme.of(context).colorScheme.primary,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFD7E3F5)),
          ),
        ),
      ),
    );
  }
}

class _LegacyPlaceCard extends StatelessWidget {
  const _LegacyPlaceCard({required this.place, required this.selected});

  final LalaPlace place;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final categoryColor = _categoryColor(place.category);
    return Container(
      width: 270,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? categoryColor : const Color(0xFFE2E8F0),
          width: selected ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 16,
            offset: Offset(0, 8),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CategoryBadge(category: place.category),
                    const SizedBox(width: 8),
                    Text(
                      '${place.distanceM}m',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _localReason(place),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(Icons.auto_graph, size: 16, color: categoryColor),
                    const SizedBox(width: 5),
                    Text(
                      '${place.score?.percent ?? '-'} 로컬 점수',
                      style: TextStyle(
                        color: categoryColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _PlaceThumb(place: place),
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'restaurant' => const Color(0xFFC53030),
      'event' => const Color(0xFFF5C842),
      'culture_venue' => const Color(0xFF2B6CB0),
      _ => const Color(0xFF1A202C),
    };
  }

  String _localReason(LalaPlace place) {
    final score = place.score;
    if (score == null) {
      return place.address;
    }
    final components = score.components;
    if ((components.demandDispersionScore ?? 0) >= 0.8) {
      return '관광 수요 분산 효과가 높은 로컬 후보';
    }
    if ((components.cultureRelevanceScore ?? 0) >= 0.7) {
      return '공식 문화데이터와 연결된 장소';
    }
    if ((components.localSpendingScore ?? 0) >= 0.6) {
      return '지역 소비 신호가 살아있는 주변 경험';
    }
    return _basisLabel(score.dataBasis);
  }
}

class _PlaceThumb extends StatelessWidget {
  const _PlaceThumb({required this.place});

  final LalaPlace place;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.asset(
        'assets/images/lala-hwaseong-haenggung.png',
        width: 76,
        height: 76,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final color = switch (category) {
      'restaurant' => const Color(0xFFC53030),
      'event' => const Color(0xFFF5C842),
      'culture_venue' => const Color(0xFF2B6CB0),
      _ => const Color(0xFF1A202C),
    };
    final textColor = category == 'event'
        ? const Color(0xFF1A202C)
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _categoryLabel(category),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CompactInfoTile extends StatelessWidget {
  const _CompactInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2B6CB0)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LalaWordmark extends StatelessWidget {
  const _LalaWordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LALA',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 4),
              color: Color(0x14000000),
            ),
          ],
        ),
        child: const Text(
          'LALA',
          style: TextStyle(
            color: Color(0xFF2B6CB0),
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.active,
    required this.color,
  });

  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? color : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 4),
              color: Color(0x12000000),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? (color == const Color(0xFFF5C842)
                      ? const Color(0xFF1A202C)
                      : Colors.white)
                : const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _WeatherMapPill extends StatelessWidget {
  const _WeatherMapPill({required this.weather});

  final LalaWeather? weather;

  @override
  Widget build(BuildContext context) {
    final label = weather == null
        ? '날씨 확인 중'
        : '${weather!.temp} · 미세먼지 ${weather!.dust.gradeKo}';
    return _SmallStatusPill(
      icon: Icons.thermostat,
      label: label,
      active: weather != null,
    );
  }
}

class _SmallStatusPill extends StatelessWidget {
  const _SmallStatusPill({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.98)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 4),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: active ? const Color(0xFF2B6CB0) : const Color(0xFF64748B),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A202C),
      ),
    );
  }
}

class _InlineMeta extends StatelessWidget {
  const _InlineMeta(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: const Color(0xFF64748B),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _MapToast extends StatelessWidget {
  const _MapToast({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 8),
            color: Color(0x1A000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _EmptyPlaceState extends StatelessWidget {
  const _EmptyPlaceState();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Text('No places returned.'),
    );
  }
}

String _categoryLabel(String category) {
  return switch (category) {
    'restaurant' => '맛집',
    'event' => '행사',
    'culture_venue' => '문화',
    'attraction' => '명소',
    _ => '로컬',
  };
}

LalaPlace? _featuredPlace(List<LalaPlace> places) {
  if (places.isEmpty) {
    return null;
  }

  final suwonPlaces = places.where((place) => place.distanceM <= 5000).toList()
    ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
  for (final place in suwonPlaces) {
    final name = '${place.nameKo ?? ''} ${place.name}';
    if (name.contains('화성행궁') || name.contains('수원화성')) {
      return place;
    }
  }
  if (suwonPlaces.isNotEmpty) {
    return suwonPlaces.first;
  }

  return places.first;
}

String _docentBody({required LalaPlace? place, required String? script}) {
  final trimmed = script?.trim();
  final placeName = place?.nameKo ?? place?.name;
  if (trimmed == null || trimmed.isEmpty) {
    return placeName == null
        ? '지도를 움직이면 가까운 로컬 경험과 도슨트가 준비됩니다.'
        : '$placeName의 문화 맥락과 주변 로컬 경험을 AI 도슨트로 준비하고 있습니다.';
  }

  final lower = trimmed.toLowerCase();
  if (lower.contains('migration skeleton') ||
      lower.contains('azure openai') ||
      lower.startsWith('this is a brief')) {
    return placeName == null
        ? '공식 관광·문화 데이터와 지역 소비 신호를 바탕으로 로컬 이야기를 준비하고 있습니다.'
        : '$placeName은 공식 관광·문화 데이터와 지역 소비 신호를 함께 살펴볼 수 있는 로컬 코스입니다.';
  }

  return trimmed;
}

String? _docentActionLabel({
  required LalaPlace? place,
  required String? action,
}) {
  final trimmed = action?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final placeName = place?.nameKo ?? place?.name ?? '이 장소';
  final looksEnglish = RegExp(r'[A-Za-z]{3,}').hasMatch(trimmed);
  if (looksEnglish) {
    return '$placeName 주변 골목과 지역 상권을 함께 걷는 코스로 이어집니다.';
  }
  return trimmed;
}

class _ExperienceHero extends StatelessWidget {
  const _ExperienceHero({
    required this.place,
    required this.weather,
    required this.intervention,
    required this.source,
  });

  final LalaPlace? place;
  final LalaWeather? weather;
  final LalaIntervention? intervention;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentPlace = place;
    final score = currentPlace?.score;
    final action = intervention?.recommendedAction;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scoreBadge = _ScoreBadge(score: score);
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.near_me_outlined, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('오늘의 로컬 연결', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                currentPlace?.name ?? '추천 후보를 불러오는 중',
                style: theme.textTheme.headlineSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                currentPlace == null
                    ? '위치와 반경을 기준으로 가까운 장소를 계산한다.'
                    : '${currentPlace.address} · ${currentPlace.distanceM}m',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniChip(
                    icon: Icons.storage_outlined,
                    label: _sourceLabel(source ?? currentPlace?.source),
                  ),
                  if (score != null)
                    _MiniChip(
                      icon: Icons.insights_outlined,
                      label: _basisLabel(score.dataBasis),
                    ),
                  if (weather != null)
                    _MiniChip(
                      icon: Icons.wb_cloudy_outlined,
                      label: '${weather!.location ?? 'Suwon'} ${weather!.temp}',
                    ),
                  if (action != null && action.trim().isNotEmpty)
                    _MiniChip(icon: Icons.alt_route_outlined, label: action),
                ],
              ),
            ],
          );

          if (constraints.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: summary),
                const SizedBox(width: 20),
                SizedBox(width: 220, child: scoreBadge),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: scoreBadge),
            ],
          );
        },
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final LalaPlaceScore? score;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentScore = score;
    final percent = currentScore?.percent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 112,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.primary, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                percent == null ? '-' : '$percent',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text('로컬 점수', style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (currentScore == null)
          const _MutedText('점수 계산 대기')
        else
          _ScoreBreakdown(score: currentScore),
      ],
    );
  }
}

class _ScoreBreakdown extends StatelessWidget {
  const _ScoreBreakdown({required this.score});

  final LalaPlaceScore score;

  @override
  Widget build(BuildContext context) {
    final components = score.components;
    return Column(
      children: [
        _ScoreBar(label: '내국인 소비', value: components.localSpendingScore),
        _ScoreBar(label: '수요 분산', value: components.demandDispersionScore),
        _ScoreBar(label: '날씨 적합', value: components.weatherFitScore),
        _ScoreBar(label: '문화 연계', value: components.cultureRelevanceScore),
        _ScoreBar(label: '리뷰 품질', value: components.reviewQualityScore),
      ],
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final bounded = value?.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: bounded ?? 0,
              minHeight: 6,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              value == null ? '대기' : '${(bounded! * 100).round()}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 1.35 : 1.05,
          children: children,
        );
      },
    );
  }
}

class _RuntimePanel extends StatelessWidget {
  const _RuntimePanel({required this.readiness});

  final LalaEnvelope<LalaReadiness>? readiness;

  @override
  Widget build(BuildContext context) {
    final data = readiness?.data;
    final mode = data?.mode;
    return _Panel(
      title: 'Runtime',
      icon: Icons.monitor_heart_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricRow(label: 'Status', value: data?.status ?? '-'),
          _MetricRow(label: 'Overall', value: mode?.overall ?? '-'),
          _MetricRow(label: 'Data', value: mode?.data ?? '-'),
          _MetricRow(label: 'AI', value: mode?.ai ?? '-'),
          _MetricRow(label: 'Speech', value: mode?.speech ?? '-'),
          _MetricRow(label: 'Worker', value: mode?.worker ?? '-'),
          _MetricRow(
            label: 'Client identity',
            value:
                data?.checks['client_identity'] ??
                data?.checks['client_auth'] ??
                '-',
          ),
          _MetricRow(
            label: 'JWT validation',
            value: data?.checks['jwt_validation'] ?? '-',
          ),
        ],
      ),
    );
  }
}

class _WeatherPanel extends StatelessWidget {
  const _WeatherPanel({required this.weather});

  final LalaEnvelope<LalaWeather>? weather;

  @override
  Widget build(BuildContext context) {
    final data = weather?.data;
    return _Panel(
      title: 'Weather',
      icon: Icons.wb_cloudy_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LargeValue(
            value: data?.temp ?? '-',
            label: data?.location ?? 'Suwon',
          ),
          _MetricRow(label: 'Dust', value: data?.dust.gradeKo ?? '-'),
          _MetricRow(label: 'Outdoor', value: data?.outdoorStatus ?? '-'),
          _MetricRow(label: 'Source', value: data?.source ?? '-'),
          if (data?.forecast.isNotEmpty == true)
            _MetricRow(
              label: 'Next',
              value: '${data!.forecast.first.time} ${data.forecast.first.temp}',
            ),
        ],
      ),
    );
  }
}

class _PlacesPanel extends StatelessWidget {
  const _PlacesPanel({required this.places});

  final LalaEnvelope<LalaPlacesResponse>? places;

  @override
  Widget build(BuildContext context) {
    final data = places?.data;
    final items = data?.places.take(3).toList() ?? const <LalaPlace>[];
    return _Panel(
      title: '추천 장소',
      icon: Icons.place_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricRow(label: 'Count', value: data?.count.toString() ?? '-'),
          _MetricRow(label: 'Source', value: _sourceLabel(data?.source)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const _MutedText('No places returned.')
          else
            ...items.map(
              (place) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            place.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (place.score != null) ...[
                          Text('${place.score!.percent}'),
                          const SizedBox(width: 8),
                        ],
                        Text('${place.distanceM}m'),
                      ],
                    ),
                    if (place.score != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${_basisLabel(place.score!.dataBasis)} · ${place.score!.formulaVersion}',
                        style: Theme.of(context).textTheme.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanPanel extends StatelessWidget {
  const _PlanPanel({required this.dailyPlan, required this.intervention});

  final LalaEnvelope<LalaDailyPlan>? dailyPlan;
  final LalaEnvelope<LalaIntervention>? intervention;

  @override
  Widget build(BuildContext context) {
    final plan = dailyPlan?.data;
    final action = intervention?.data;
    return _Panel(
      title: 'Plan',
      icon: Icons.route_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricRow(label: 'Source', value: plan?.source ?? '-'),
          _MetricRow(
            label: 'Radius',
            value: plan == null ? '-' : '${plan.radiusM}m',
          ),
          _MetricRow(label: 'Cache', value: plan?.cacheKey ?? '-'),
          _MetricRow(label: 'Action', value: action?.recommendedAction ?? '-'),
          _MetricRow(label: 'Candidate', value: action?.place?.name ?? '-'),
          const SizedBox(height: 8),
          if (plan == null)
            const _MutedText('Plan waits for authenticated API data.')
          else
            ...plan.slots
                .take(3)
                .map(
                  (slot) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.schedule_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${slot.period}: ${slot.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _DocentPanel extends StatelessWidget {
  const _DocentPanel({
    required this.docentScript,
    required this.docentAudio,
    required this.audioLoading,
    required this.audioError,
    required this.onFetchAudio,
  });

  final LalaEnvelope<LalaDocentScript>? docentScript;
  final LalaAudioResponse? docentAudio;
  final bool audioLoading;
  final String? audioError;
  final VoidCallback onFetchAudio;

  @override
  Widget build(BuildContext context) {
    final script = docentScript?.data;
    final canFetchAudio = script != null && !audioLoading;
    return _Panel(
      title: 'Docent',
      icon: Icons.record_voice_over_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricRow(label: 'Source', value: script?.source ?? '-'),
          _MetricRow(label: 'Cache', value: script?.cacheKey ?? '-'),
          _MetricRow(label: 'Place', value: script?.placeId ?? '-'),
          _MetricRow(
            label: 'Audio',
            value: docentAudio == null
                ? '-'
                : '${docentAudio!.bytes.length} bytes',
          ),
          if (docentAudio?.cacheKey != null)
            _MetricRow(label: 'Audio key', value: docentAudio!.cacheKey!),
          if (audioError != null) _MutedText(audioError!),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: canFetchAudio ? onFetchAudio : null,
              icon: audioLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.volume_up_outlined),
              label: Text(audioLoading ? 'Fetching audio' : 'Fetch audio'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectionArea(
                child: Text(
                  script?.script ?? 'Docent script waits for a place result.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _sourceLabel(String? value) {
  return switch ((value ?? '').trim()) {
    'db' => 'DB 기반',
    'mixed' => '혼합 데이터',
    'public_mvp_snapshot' => '공공 스냅샷',
    'skeleton' => '데모 데이터',
    '' => '-',
    final source => source,
  };
}

String _basisLabel(String value) {
  return switch (value.trim()) {
    'actual_data' => '실데이터',
    'demo_seed' => '시드 데이터',
    'public_mvp_snapshot' => '공개 MVP 스냅샷',
    'demo_fallback' => '데모 기준',
    final basis when basis.isEmpty => '-',
    final basis => basis,
  };
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
    this.fill = true,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (fill) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      backgroundColor: active
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _LargeValue extends StatelessWidget {
  const _LargeValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
