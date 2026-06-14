import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

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
          seedColor: const Color(0xFF1E6B5F),
          brightness: Brightness.light,
        ).copyWith(
          secondary: const Color(0xFFB54D3D),
          tertiary: const Color(0xFF6D5A23),
          surface: const Color(0xFFF8FAF8),
        );

    return MaterialApp(
      title: 'LALA Next',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        useMaterial3: true,
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
      lat = 37.2636,
      lng = 127.0286,
      radiusM = 50000;

  final String baseUri;
  final String bearerToken;
  final String apiKey;
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
    double? lat,
    double? lng,
    int? radiusM,
  }) {
    return LalaAppConfig(
      baseUri: baseUri ?? this.baseUri,
      bearerToken: bearerToken ?? this.bearerToken,
      apiKey: apiKey ?? this.apiKey,
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
        final firstPlace = placeItems.isEmpty ? null : placeItems.first;
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
    return Scaffold(
      appBar: AppBar(title: const Text('LALA Next')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final config = _currentConfig();
            final configPanel = _ConfigPanel(
              baseUrlController: _baseUrlController,
              bearerTokenController: _bearerTokenController,
              apiKeyController: _apiKeyController,
              latController: _latController,
              lngController: _lngController,
              radiusController: _radiusController,
              loading: _loading,
              onRefresh: _refresh,
            );
            final dashboard = _Dashboard(
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
              onFetchAudio: _fetchAudio,
            );

            if (constraints.maxWidth >= 920) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: dashboard,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 340,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: configPanel,
                    ),
                  ),
                ],
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [dashboard, const SizedBox(height: 16), configPanel],
              ),
            );
          },
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
    required this.latController,
    required this.lngController,
    required this.radiusController,
    required this.loading,
    required this.onRefresh,
  });

  final TextEditingController baseUrlController;
  final TextEditingController bearerTokenController;
  final TextEditingController apiKeyController;
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
    required this.onFetchAudio,
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
  final VoidCallback onFetchAudio;

  bool get hasAuth => authMode.hasClientAuth;

  @override
  Widget build(BuildContext context) {
    final runtimeMode = readiness?.data?.mode.overall;
    final topPlaces = places?.data?.places ?? const <LalaPlace>[];
    final topPlace = topPlaces.isEmpty ? null : topPlaces.first;
    final requestIds = _RequestCorrelation(
      readiness: readiness?.requestId,
      places: places?.requestId,
      weather: weather?.requestId,
      dailyPlan: dailyPlan?.requestId,
      docentScript: docentScript?.requestId,
      docentAudio: docentAudio?.requestId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          _Banner(
            icon: Icons.error_outline,
            label: error!,
            color: Theme.of(context).colorScheme.errorContainer,
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              icon: Icons.favorite_border,
              label: health?.data?['status']?.toString() ?? 'health pending',
              active: health?.data?['status'] == 'ok',
            ),
            _StatusChip(
              icon: Icons.hub_outlined,
              label: runtimeMode ?? 'runtime pending',
              active: runtimeMode != null && runtimeMode != 'degraded',
            ),
            _StatusChip(
              icon: Icons.lock_outline,
              label: authMode.label,
              active: hasAuth,
            ),
          ],
        ),
        if (requestIds.hasAny) ...[
          const SizedBox(height: 12),
          _RequestCorrelationStrip(requestIds: requestIds),
        ],
        const SizedBox(height: 16),
        if (loading)
          const LinearProgressIndicator(minHeight: 3)
        else
          const SizedBox(height: 3),
        const SizedBox(height: 16),
        _ExperienceHero(
          place: topPlace,
          weather: weather?.data,
          intervention: intervention?.data,
          source: places?.data?.source,
        ),
        const SizedBox(height: 16),
        _ResponsiveGrid(
          children: [
            _PlacesPanel(places: places),
            _PlanPanel(dailyPlan: dailyPlan, intervention: intervention),
            _DocentPanel(
              docentScript: docentScript,
              docentAudio: docentAudio,
              audioLoading: audioLoading,
              audioError: audioError,
              onFetchAudio: onFetchAudio,
            ),
            _WeatherPanel(weather: weather),
            _RuntimePanel(readiness: readiness),
          ],
        ),
      ],
    );
  }
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

class _RequestCorrelation {
  const _RequestCorrelation({
    this.readiness,
    this.places,
    this.weather,
    this.dailyPlan,
    this.docentScript,
    this.docentAudio,
  });

  final String? readiness;
  final String? places;
  final String? weather;
  final String? dailyPlan;
  final String? docentScript;
  final String? docentAudio;

  bool get hasAny => entries.isNotEmpty;

  List<MapEntry<String, String>> get entries {
    return <MapEntry<String, String>>[
      if (_isPresent(readiness)) MapEntry('ready', readiness!.trim()),
      if (_isPresent(places)) MapEntry('places', places!.trim()),
      if (_isPresent(weather)) MapEntry('weather', weather!.trim()),
      if (_isPresent(dailyPlan)) MapEntry('plan', dailyPlan!.trim()),
      if (_isPresent(docentScript)) MapEntry('docent', docentScript!.trim()),
      if (_isPresent(docentAudio)) MapEntry('audio', docentAudio!.trim()),
    ];
  }

  static bool _isPresent(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class _RequestCorrelationStrip extends StatelessWidget {
  const _RequestCorrelationStrip({required this.requestIds});

  final _RequestCorrelation requestIds;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: requestIds.entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: const Icon(Icons.tag_outlined, size: 16),
                  label: Text('${entry.key} ${_shortId(entry.value)}'),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  static String _shortId(String value) {
    if (value.length <= 18) {
      return value;
    }
    return '${value.substring(0, 8)}...${value.substring(value.length - 6)}';
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
