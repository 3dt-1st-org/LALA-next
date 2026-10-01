import 'dart:async';
import 'dart:math' as math;
import 'onboarding_translations.dart';
import 'manual_location_options.dart';
import 'settings_confirmation_dialog.dart';

import 'package:flutter/material.dart';

enum OnboardingLocationStatus { granted, denied, unavailable }

class OnboardingResult {
  const OnboardingResult({
    required this.isGuest,
    required this.country,
    required this.language,
    required this.travelStyles,
    required this.travelMode,
    required this.autoDocent,
    required this.playbackSpeed,
    required this.requestLocation,
    this.destination,
  });

  final bool isGuest;
  final String country;
  final String language;
  final List<String> travelStyles;
  final String travelMode;
  final bool autoDocent;
  final double playbackSpeed;
  final bool requestLocation;
  final ManualLocationOption? destination;

  // Preserve the chosen locale while using available main/API translations.
  String get contentLanguage => language == 'ko' ? 'ko' : 'en';
}

/// Five light-mode pages. Artwork and controls have independent layouts:
/// the art is clipped above a white fade, and all controls remain scrollable.
class OnboardingScreen extends StatefulWidget {
  static const lightLoginArtwork =
      'assets/images/onboarding/login-light-refined.png';
  // Selected companion artwork for the future dark theme.
  static const darkLoginArtwork =
      'assets/images/onboarding/login-dark-refined.png';

  const OnboardingScreen({
    required this.onComplete,
    this.initialLanguage = 'en',
    this.onRequestLocation,
    this.onSignIn,
    this.onSelectDestination,
    super.key,
  });

  final FutureOr<void> Function(OnboardingResult) onComplete;
  final Future<bool> Function()? onSignIn;
  final String initialLanguage;
  final Future<OnboardingLocationStatus> Function()? onRequestLocation;
  final Future<ManualLocationOption?> Function(String language)?
  onSelectDestination;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _jade = Color(0xFF31786C);
  static const _ink = Color(0xFF292725);
  static const _muted = Color(0xFF70736F);
  static const _line = Color(0xFFDCE9E4);
  static const _countries = [
    ('KR', 'ko', 'Korea', '한국 · 한국어'),
    ('US', 'en', 'United States', '미국 · English'),
    ('JP', 'ja', 'Japan', '일본 · 日本語'),
    ('CN', 'zh-CN', 'China', '중국 · 简体中文'),
    ('TW', 'zh-TW', 'Taiwan', '台灣 · 繁體中文'),
    ('HK', 'zh-TW', 'Hong Kong', '香港 · 繁體中文'),
    ('OTHER', 'en', 'Other countries', '기타 국가 · English'),
  ];
  static const _styles = [
    ('history', '🏯', 'History & Palaces', '역사 · 고궁 · 유적지'),
    ('food', '🍲', 'Food & Cafés', '로컬 맛집 · 골목 카페'),
    ('nature', '🌳', 'Nature & Walking', '자연 · 공원 · 골목 산책'),
    ('kculture', '🛍️', 'K-Culture & Shopping', 'K-컬처 · 쇼핑 · 전시'),
    ('market', '🏮', 'Traditions & Markets', '전통시장 · 로컬 축제'),
  ];

  final _scroll = ScrollController();
  int _step = 0;
  late String _language;
  late String _country;
  final Set<String> _selectedStyles = {'history'};
  String _mode = 'explore_now';
  bool _autoDocent = false;
  bool _busy = false;
  bool _locationGranted = false;
  bool _locationDialogDismissed = false;
  ManualLocationOption? _destination;
  double _speed = 1;
  bool _finished = false;
  bool _signedIn = false;

  String _label(String en, String ko) =>
      _language == 'ko' ? ko : onboardingTranslations[_language]?[en] ?? en;

  @override
  void initState() {
    super.initState();
    _language =
        _countries.any((country) => country.$2 == widget.initialLanguage)
        ? widget.initialLanguage
        : 'en';
    _country = _countries.firstWhere((country) => country.$2 == _language).$1;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _finish(bool location) async {
    if (_finished || _busy) return;
    _finished = true;
    setState(() => _busy = true);
    try {
      await widget.onComplete(
        OnboardingResult(
          isGuest: !_signedIn,
          country: _country,
          language: _language,
          travelStyles: _selectedStyles.toList(),
          travelMode: _mode,
          autoDocent: _autoDocent,
          playbackSpeed: _speed,
          requestLocation: _locationGranted,
          destination: _destination,
        ),
      );
    } on Object {
      _finished = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _label(
                'Could not save your choices. Please try again.',
                '설정을 저장하지 못했어요. 다시 시도해 주세요.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (_busy || widget.onSignIn == null) return;
    setState(() => _busy = true);
    try {
      final signedIn = await widget.onSignIn!();
      if (!mounted) return;
      if (signedIn) {
        _signedIn = true;
        _go(1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _label(
                'Sign-in was not completed. Try again or continue as a guest.',
                '로그인을 완료하지 못했어요. 다시 시도하거나 비회원으로 시작해 주세요.',
              ),
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _label(
                'Sign-in is temporarily unavailable.',
                '잠시 로그인을 사용할 수 없어요.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _askLocation() async {
    _locationDialogDismissed = false;
    if (_locationGranted) return true;
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => _IllustratedLocationDialog(
        sectionLabel: _label('Location access', '위치 사용 안내'),
        title: _label('Find places near you', '가까운 여행지를\n찾아드릴게요'),
        description: _label(
          'Use your location to find nearby places and stories. You can also choose a region.',
          '현재 위치로 가까운 장소와 이야기를 찾아요.\n위치를 사용하지 않아도 지역을 직접 선택할 수 있어요.',
        ),
        allowLabel: _label('Use my location', '현재 위치 사용하기'),
        declineLabel: _label('Not now', '지금은 사용하지 않을게요'),
        closeLabel: _label('Close', '닫기'),
      ),
    );
    if (!mounted) return false;
    if (allow == null) {
      _locationDialogDismissed = true;
      return false;
    }
    OnboardingLocationStatus status = OnboardingLocationStatus.denied;
    if (allow == true) {
      try {
        status =
            await widget.onRequestLocation?.call() ??
            OnboardingLocationStatus.unavailable;
      } catch (_) {
        status = OnboardingLocationStatus.unavailable;
      }
    }
    if (!mounted) return false;
    if (status == OnboardingLocationStatus.granted) {
      setState(() => _locationGranted = true);
      return true;
    }
    final chooseRegion = await showDialog<bool>(
      context: context,
      builder: (ctx) => SettingsConfirmationDialog(
        dialogKey: const ValueKey('location-fallback'),
        docent: false,
        showIllustration: false,
        sectionLabel: _label('Choose a destination', '여행지 선택'),
        title: _label('Explore a region instead?', '지역을 선택해서 둘러볼까요?'),
        message: [
          status == OnboardingLocationStatus.unavailable
              ? _label(
                  'Your location could not be retrieved.',
                  '현재 위치를 가져오지 못했어요.',
                )
              : _label(
                  'Without location access, we cannot automatically find nearby places.',
                  '위치 없이는 주변을 찾기 어려워요.',
                ),
          _label(
            'Choose a destination to explore places and listen to stories.',
            MediaQuery.sizeOf(ctx).width < 900
                ? '지역을 직접 골라 여행지를 둘러보고,\n장소의 이야기를 들어보세요.'
                : '\n지역을 직접 골라 여행지를 둘러보고, 장소의 이야기를 들어보세요.',
          ),
        ].join(MediaQuery.sizeOf(ctx).width < 900 ? '\n' : ' '),
        confirmLabel: _label('Choose a destination', '여행지 선택하기'),
        cancelLabel: _label('Later', '나중에'),
        closeLabel: _label('Close', '닫기'),
      ),
    );
    if (mounted && chooseRegion == true) await _chooseDestination();
    return false;
  }

  Future<bool> _chooseDestination() async {
    final selected = await widget.onSelectDestination?.call(_language);
    if (!mounted || selected == null) return false;
    setState(() {
      _destination = selected;
      _mode = 'plan_trip';
    });
    return true;
  }

  Future<void> _nextMode() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_mode == 'plan_trip') {
        if (!await _chooseDestination()) return;
      } else if (_mode == 'explore_now') {
        final granted = await _askLocation();
        if (!mounted || _locationDialogDismissed) return;
        if (!granted && _destination == null) {
          setState(() => _mode = 'undecided');
        }
      }
      if (mounted) _go(4);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleDocent(bool value) async {
    if (_busy) return;
    if (!value) {
      setState(() => _autoDocent = false);
      return;
    }
    setState(() => _busy = true);
    try {
      final allowed = await _askLocation();
      if (mounted) setState(() => _autoDocent = allowed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localTheme = Theme.of(context).copyWith(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _jade,
        brightness: Brightness.light,
      ),
      textTheme: Theme.of(context).textTheme.apply(
        fontFamily: 'Pretendard',
        fontFamilyFallback: const ['NotoSansCJK'],
        bodyColor: _ink,
        displayColor: _ink,
      ),
    );
    return Theme(
      data: localTheme,
      child: PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _step > 0) _go(_step - 1);
        },
        child: Scaffold(
          backgroundColor: Colors.white,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final inset = MediaQuery.paddingOf(context);
              // Tall tablet viewports should not stretch the form down to the
              // bottom of a full portrait canvas.
              final availableHeight = constraints.maxHeight - inset.vertical;
              final panelHeight =
                  _step > 0 &&
                      wide &&
                      constraints.maxHeight > constraints.maxWidth
                  ? availableHeight.clamp(0.0, 820.0)
                  : availableHeight;
              Widget panel() => Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: panelHeight,
                  child: _widePanel(panelHeight),
                ),
              );
              const art = OnboardingScreen.lightLoginArtwork;
              if (_step > 0) {
                return ColoredBox(
                  color: const Color(0xFFFFFFFF),
                  child: SafeArea(child: panel()),
                );
              }
              if (wide) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Row(
                      key: const ValueKey('onboarding-wide'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Stack(
                            children: [
                              _Scenery(
                                asset: art,
                                height: constraints.maxHeight,
                                welcome: _step == 0,
                                fadeRight: true,
                              ),
                            ],
                          ),
                        ),
                        Expanded(flex: 5, child: SafeArea(child: panel())),
                      ],
                    ),
                    // Cover both sides of the fractional column boundary in
                    // the parent layer, beyond the artwork's opaque fade.
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: constraints.maxWidth * 6 / 11 - 3,
                      width: 6,
                      child: const IgnorePointer(
                        child: ColoredBox(
                          key: ValueKey('onboarding-seam-cover'),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                );
              }
              final heroHeight = _step == 0
                  ? (constraints.maxHeight * .64).clamp(370.0, 590.0)
                  : (constraints.maxHeight * .32).clamp(170.0, 310.0);
              return SingleChildScrollView(
                controller: _scroll,
                key: const ValueKey('onboarding-scroll'),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        _Scenery(asset: art, height: heroHeight, welcome: true),
                        Positioned(
                          top: inset.top + 48,
                          left: 24,
                          right: 24,
                          child: _welcomeTitle(),
                        ),
                      ],
                    ),
                    _welcomeFooter(
                      constraints.maxHeight,
                      inset.bottom,
                      anchored: false,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // Compact layouts scroll the artwork and actions together. Desktop keeps
  // its bottom anchor and independently scrollable actions for short windows.
  Widget _welcomeFooter(
    double height,
    double bottomInset, {
    bool anchored = true,
  }) {
    final content = ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 50, 24, 24 + bottomInset),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              key: const ValueKey('onboarding-welcome-footer'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _content(),
            ),
          ),
        ),
      ),
    );
    if (!anchored) return content;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * .65),
      child: ColoredBox(
        color: Colors.white,
        child: SingleChildScrollView(
          key: const ValueKey('onboarding-welcome-footer-scroll'),
          child: content,
        ),
      ),
    );
  }

  Widget _toolbar() => Stack(
    key: const ValueKey('onboarding-toolbar'),
    alignment: Alignment.center,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '0$_step',
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
            const TextSpan(
              text: ' / 04',
              style: TextStyle(color: _muted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        key: const ValueKey('onboarding-step-label'),
        textScaler: TextScaler.noScaling,
        style: const TextStyle(fontSize: 11, letterSpacing: 1.6),
      ),
      Row(
        children: [
          IconButton(
            key: const ValueKey('onboarding-back'),
            onPressed: () => _go(_step - 1),
            tooltip: _label('Back', '이전'),
            icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          ),
          const Spacer(),
          TextButton(
            key: const ValueKey('onboarding-skip'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: _busy
                ? null
                : () {
                    if (_step == 4) {
                      _finish(false);
                    } else if (_step == 3) {
                      setState(() {
                        _mode = 'undecided';
                        _destination = null;
                      });
                      _go(4);
                    } else {
                      if (_step == 2) _selectedStyles.clear();
                      _go(_step + 1);
                    }
                  },
            child: Text(
              _label('Later', '나중에'),
              textScaler: TextScaler.noScaling,
              style: const TextStyle(color: _ink),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _widePanel(double height) {
    if (_step == 0) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              key: const ValueKey('onboarding-scroll'),
              child: Padding(
                // Keep the original welcome-copy position independent of the footer.
                padding: EdgeInsets.fromLTRB(
                  32,
                  math.max(32, height / 2 - 192),
                  32,
                  32,
                ),
                child: _welcomeTitle(),
              ),
            ),
          ),
          _welcomeFooter(height, 0),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 900 ? 24 : 32,
        16,
        MediaQuery.sizeOf(context).width < 900 ? 24 : 32,
        20,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(),
              const SizedBox(height: 12),
              const ExcludeSemantics(child: _TraditionalRule()),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  key: const ValueKey('onboarding-scroll'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _pageBody(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ..._actions(wide: true),
              if (_step != 4) const SizedBox(height: 54),
              ..._progress(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content() => [
    ..._pageBody(),
    if (_step > 0) ...[const SizedBox(height: 20), ..._actions()],
    ..._progress(),
  ];

  List<Widget> _pageBody() => [
    if (_step == 0) ..._welcome(),
    if (_step == 1) ..._countryPage(),
    if (_step == 2) ..._stylePage(),
    if (_step == 3) ..._modePage(),
    if (_step == 4) ..._audioPage(),
  ];

  List<Widget> _progress() => [
    const SizedBox(height: 22),
    Semantics(
      label: '${_step + 1} / 5',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          5,
          (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: i == _step ? 20 : 5,
            height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i == _step ? _jade : _line,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    ),
  ];

  // Restore the original title overlay; the scenery supplies a sky-colour wash.
  Widget _welcomeTitle() => Column(
    key: const ValueKey('onboarding-welcome-copy'),
    children: [
      const Text(
        'LALA',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: _ink,
          fontSize: 46,
          height: 1.1,
          fontWeight: FontWeight.w900,
          letterSpacing: -2,
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Local Area, Local Answer',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _label(
          'Discover the stories of Korea.\nFind more joy in every journey.',
          '한국의 이야기를 따라,\n여행을 더 즐겁게.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: _ink, fontSize: 14, height: 1.7),
      ),
    ],
  );

  List<Widget> _welcome() => [
    _primary(
      _label('Continue as Guest', '로그인 없이 시작하기'),
      () => _go(1),
      subtitle: _label('로그인 없이 시작하기', 'Continue as Guest'),
    ),
    const SizedBox(height: 12),
    OutlinedButton(
      onPressed: widget.onSignIn == null || _busy ? null : _signIn,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        side: const BorderSide(color: _line),
        disabledForegroundColor: _muted,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_circle_outlined, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.onSignIn == null
                  ? _label(
                      'Sign-in unavailable in this environment',
                      '현재 환경에서 로그인 미설정',
                    )
                  : _label('Sign in', '로그인하기'),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    ),
    const SizedBox(height: 22),
    Text(
      _label(
        'Start exploring without an account.\nMake your first discovery with LALA.',
        '회원가입 없이 가볍게 시작해 보세요.\nLALA와 첫 번째 이야기를 만나보세요.',
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, height: 1.7, color: _muted),
    ),
  ];

  List<Widget> _heading(String en, String ko, [String? helper]) => [
    Text(
      _step > 1 ? _label(en, ko) : en,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: -.5,
      ),
    ),
    if (_step == 1) ...[
      const SizedBox(height: 6),
      Text(
        ko,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ],
    if (helper != null) ...[
      const SizedBox(height: 8),
      Text(
        helper,
        style: const TextStyle(fontSize: 12, height: 1.5, color: _muted),
      ),
    ],
    const SizedBox(height: 20),
  ];

  List<Widget> _countryPage() => [
    ..._heading('Where are you from?', '어디에서 오셨나요?'),
    _grid(
      _countries
          .map(
            (item) => _tile(
              id: 'country-${item.$1}',
              leading: _CountrySymbol(code: item.$1),
              title: item.$3,
              subtitle: item.$4,
              selected: _country == item.$1,
              onTap: () => setState(() {
                _country = item.$1;
                _language = item.$2;
              }),
            ),
          )
          .toList(),
    ),
    const SizedBox(height: 16),
    Text(
      _label(
        'Language is set automatically. Other countries use English.',
        '선택한 국가에 맞춰 언어가 설정됩니다. 기타 국가는 영어로 안내해요.',
      ),
      style: const TextStyle(fontSize: 11, height: 1.5, color: _muted),
    ),
  ];

  List<Widget> _stylePage() => [
    ..._heading(
      'What do you love about travel?',
      '어떤 여행을 좋아하세요?',
      _label('Pick 1 to 3 things you enjoy.', '좋아하는 여행을 1~3개 골라주세요.'),
    ),
    _grid(
      _styles
          .map(
            (item) => _tile(
              id: 'style-${item.$1}',
              leading: Icon(
                switch (item.$1) {
                  'history' => Icons.account_balance_rounded,
                  'food' => Icons.ramen_dining_rounded,
                  'nature' => Icons.park_rounded,
                  'kculture' => Icons.shopping_bag_rounded,
                  _ => Icons.storefront_rounded,
                },
                size: 30,
                color: _jade,
              ),
              title: _label(item.$3, item.$4),
              subtitle: '',
              selected: _selectedStyles.contains(item.$1),
              onTap: () {
                if (!_selectedStyles.contains(item.$1) &&
                    _selectedStyles.length == 3) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _label(
                          'Choose up to 3 travel styles.',
                          '여행 취향은 최대 3개까지 선택할 수 있어요.',
                        ),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                setState(() {
                  if (_selectedStyles.contains(item.$1)) {
                    if (_selectedStyles.length > 1) {
                      _selectedStyles.remove(item.$1);
                    }
                  } else {
                    _selectedStyles.add(item.$1);
                  }
                });
              },
            ),
          )
          .toList(),
    ),
  ];

  List<Widget> _modePage() => [
    ..._heading('How would you like to explore?', '어떤 여행을 시작해볼까요?'),
    _modeCard(
      'explore_now',
      Icons.location_on_outlined,
      'Explore nearby',
      '가까운 곳부터 둘러볼까요?',
      _label('Find places to explore near you.', '지금 내 주변의 여행지를 찾아봐요.'),
    ),
    const SizedBox(height: 14),
    _modeCard(
      'plan_trip',
      Icons.map_outlined,
      'Plan a trip',
      '여행을 미리 준비할래요',
      _label('Discover places for your next trip.', '가고 싶은 곳과 이야기를 미리 찾아봐요.'),
    ),
    const SizedBox(height: 20),
    TextButton(
      key: const ValueKey('mode-undecided'),
      onPressed: _busy
          ? null
          : () {
              setState(() {
                _mode = 'undecided';
                _destination = null;
              });
              _go(4);
            },
      child: Text(
        _label('I have not decided yet', '아직 정하지 않았어요'),
        style: const TextStyle(color: _jade),
      ),
    ),
    if (_busy) const Center(child: Icon(Icons.more_horiz, color: _jade)),
  ];

  List<Widget> _audioPage() => [
    ..._heading(
      'Listen as you explore',
      '걸으며 이야기를 들어보세요',
      _label(
        'Discover the stories around you, one place at a time.',
        '명소 가까이에서 역사와 골목 이야기를 만나보세요.',
      ),
    ),
    LayoutBuilder(
      builder: (context, constraints) {
        final artHeight = (constraints.maxWidth * .56).clamp(166.0, 240.0);
        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ExcludeSemantics(
                child: SizedBox(
                  height: artHeight,
                  child: ClipRect(
                    child: OverflowBox(
                      maxWidth: 440,
                      minWidth: 0,
                      child: Image.asset(
                        'assets/images/onboarding/docent-listening.png',
                        key: const ValueKey('onboarding-docent-illustration'),
                        width: constraints.maxWidth.clamp(0.0, 440.0),
                        height: artHeight,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: artHeight - 24),
              child: _audioSettings(),
            ),
          ],
        );
      },
    ),
  ];

  Widget _audioSettings() => Container(
    key: const ValueKey('onboarding-audio-settings'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label('Nearby story alerts', '주변 이야기를 알려드릴까요?'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _label(
                      'Find stories near you. Select a place to listen anytime.',
                      '가까운 장소의 이야기를 찾아드려요. 직접 선택해서 들을 수도 있어요.',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _autoDocent,
              activeTrackColor: _jade,
              onChanged: _busy ? null : _toggleDocent,
            ),
          ],
        ),
        const Divider(height: 26, color: _line),
        Text(
          _label('Playback speed', '음성 속도'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _segment(
              _label('Slow\n0.8x', '느리게\n0.8x'),
              _speed == .8,
              () => setState(() => _speed = .8),
            ),
            const SizedBox(width: 8),
            _segment(
              _label('Normal\n1.0x', '보통\n1.0x'),
              _speed == 1,
              () => setState(() => _speed = 1),
            ),
            const SizedBox(width: 8),
            _segment(
              _label('Fast\n1.2x', '빠르게\n1.2x'),
              _speed == 1.2,
              () => setState(() => _speed = 1.2),
            ),
          ],
        ),
      ],
    ),
  );

  List<Widget> _actions({bool wide = false}) => [
    SizedBox(
      // Reserve two text lines on desktop, including the longer final label.
      height: wide ? _fixedActionHeight() : null,
      child: _step != 4
          ? _primary(_label('Next', '다음'), () {
              if (_busy) return;
              if (_step == 3) {
                _nextMode();
              } else {
                _go(_step + 1);
              }
            })
          : _primary(_label('Start exploring', '여행 시작하기'), () {
              if (!_busy) _finish(false);
            }),
    ),
    if (_step == 4) ...[
      const SizedBox(height: 6),
      SizedBox(
        height: 48,
        child: TextButton(
          onPressed: () => _finish(false),
          child: Text(
            _label('Start without Location', '나중에 할게요'),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
      ),
    ],
  ];

  double _fixedActionHeight() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = screenWidth >= 900
        ? (screenWidth - 64).clamp(0.0, 680.0)
        : (screenWidth - 48).clamp(0.0, 680.0);
    var height = 68.0;
    for (final label in [
      _label('Start with my location', '내 위치로 여행 시작하기'),
      _label('Next', '다음'),
    ]) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: (panelWidth - 60).clamp(1.0, double.infinity));
      height = (painter.height + 32).clamp(height, double.infinity);
      painter.dispose();
    }
    return height;
  }

  Widget _grid(List<Widget> tiles) => Column(
    children: [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _tile({
    required String id,
    required Widget leading,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0xFFEAF5F0) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? _jade : _line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey(id),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 13,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 34, child: Center(child: leading)),
                      const SizedBox(height: 7),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      if (subtitle.isNotEmpty) const SizedBox(height: 4),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            color: _muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (selected)
                const Positioned(
                  top: 7,
                  right: 7,
                  child: Icon(Icons.check_circle, size: 15, color: _jade),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard(
    String id,
    IconData icon,
    String en,
    String ko,
    String description,
  ) {
    final selected = _mode == id;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0xFFF0F7F4) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? _jade : _line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('mode-$id'),
          onTap: _busy
              ? null
              : () => setState(() {
                  _mode = id;
                  _destination = null;
                }),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: _jade,
                  radius: 23,
                  child: Icon(icon, color: Colors.white, size: 27),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label(en, ko),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _muted,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  selected ? Icons.check_circle_outline : Icons.chevron_right,
                  size: 18,
                  color: _jade,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _segment(String text, bool selected, VoidCallback onTap) => Expanded(
    child: Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? _jade : const Color(0xFFF5F9F7),
          foregroundColor: selected ? Colors.white : _muted,
          side: BorderSide(color: selected ? _jade : _line),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
      ),
    ),
  );

  Widget _primary(
    String label,
    VoidCallback onTap, {
    String? subtitle,
    IconData? icon,
  }) => FilledButton(
    key: const ValueKey('onboarding-primary'),
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: _jade,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: const StadiumBorder(),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _CountrySymbol extends StatelessWidget {
  const _CountrySymbol({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    if (code == 'OTHER') {
      return const Icon(
        Icons.language_rounded,
        size: 30,
        color: Color(0xFF31786C),
      );
    }
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(size: const Size(40, 28), painter: _FlagPainter(code)),
        ],
      ),
    );
  }
}

/// Vector flags avoid platform-dependent regional-indicator emoji rendering.
class _FlagPainter extends CustomPainter {
  const _FlagPainter(this.code);
  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 32);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 48, 32));
    final paint = Paint();
    void rect(double x, double y, double w, double h, Color color) {
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint..color = color);
    }

    void circle(double x, double y, double r, Color color) {
      canvas.drawCircle(Offset(x, y), r, paint..color = color);
    }

    void star(double x, double y, double radius, Color color) {
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final a = -math.pi / 2 + i * math.pi / 5;
        final r = i.isEven ? radius : radius * .4;
        final px = x + math.cos(a) * r;
        final py = y + math.sin(a) * r;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(path..close(), paint..color = color);
    }

    const red = Color(0xFFDF3C50);
    const blue = Color(0xFF235494);
    rect(0, 0, 48, 32, Colors.white);
    switch (code) {
      case 'US':
        for (var i = 0; i < 13; i += 2) {
          rect(0, i * 32 / 13, 48, 32 / 13, red);
        }
        rect(0, 0, 17, 18, blue);
        for (var y = 3; y < 18; y += 4) {
          for (var x = 2; x < 17; x += 4) {
            star(x.toDouble(), y.toDouble(), 1, Colors.white);
          }
        }
      case 'JP':
        circle(24, 16, 8, red);
      case 'CN':
        rect(0, 0, 48, 32, red);
        star(10, 12, 5, const Color(0xFFFFD762));
        for (final point in [
          const Offset(18, 6),
          const Offset(22, 10),
          const Offset(22, 15),
          const Offset(18, 19),
        ]) {
          star(point.dx, point.dy, 1.6, const Color(0xFFFFD762));
        }
      case 'TW':
        rect(0, 0, 48, 32, red);
        rect(0, 0, 18, 18, blue);
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          circle(10 + math.cos(a) * 5, 9 + math.sin(a) * 5, 1, Colors.white);
        }
        circle(10, 9, 3.5, Colors.white);
      case 'HK':
        rect(0, 0, 48, 32, red);
        for (var i = 0; i < 5; i++) {
          canvas.save();
          canvas.translate(24, 16);
          canvas.rotate(i * 2 * math.pi / 5);
          canvas.drawOval(
            const Rect.fromLTWH(-3, -11, 6, 11),
            paint..color = Colors.white,
          );
          canvas.restore();
        }
      case 'KR':
        canvas.save();
        canvas.translate(24, 16);
        canvas.rotate(math.pi / 6);
        canvas.drawArc(
          const Rect.fromLTWH(-7, -7, 14, 14),
          math.pi,
          math.pi,
          true,
          paint..color = red,
        );
        canvas.drawArc(
          const Rect.fromLTWH(-7, -7, 14, 14),
          0,
          math.pi,
          true,
          paint..color = blue,
        );
        circle(-3.5, 0, 3.5, red);
        circle(3.5, 0, 3.5, blue);
        canvas.restore();
        for (var corner = 0; corner < 4; corner++) {
          canvas.save();
          canvas.translate(corner.isEven ? 10 : 38, corner < 2 ? 7 : 25);
          canvas.rotate(corner.isEven ? -math.pi / 4 : math.pi / 4);
          for (var bar = 0; bar < 3; bar++) {
            rect(-3.5, -3 + bar * 2.3, 7, 1.3, const Color(0xFF28364A));
            if ((corner + bar) % 3 == 0 && corner != 0) {
              rect(-.7, -3 + bar * 2.3, 1.4, 1.3, Colors.white);
            }
          }
          canvas.restore();
        }
    }
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTWH(.5, .5, size.width - 1, size.height - 1),
      Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_FlagPainter oldDelegate) => code != oldDelegate.code;
}

class _Scenery extends StatelessWidget {
  const _Scenery({
    required this.asset,
    required this.height,
    required this.welcome,
    this.fadeRight = false,
  });
  final String asset;
  final double height;
  final bool welcome;
  final bool fadeRight;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('onboarding-art'),
    height: height,
    width: double.infinity,
    child: ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: fadeRight ? Alignment.center : Alignment.topCenter,
            gaplessPlayback: true,
          ),
          if (!fadeRight)
            const Positioned(
              key: ValueKey('onboarding-bottom-fade'),
              left: 0,
              right: 0,
              bottom: 0,
              height: 90,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00FFFFFF), Colors.white],
                  ),
                ),
              ),
            ),
          if (fadeRight)
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: ValueKey('onboarding-side-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      // Reach opaque white before the fractional column edge;
                      // a solid white tail prevents a one-pixel image seam.
                      stops: [.64, .84, .96, 1],
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x99FFFFFF),
                        Colors.white,
                        Colors.white,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Crop the supplied transparent asset in layout; tint it and the lines together.
class _TraditionalRule extends StatelessWidget {
  const _TraditionalRule();
  static const _color = Color(0xFF78998C);
  static const _scale = 72.0 / 676.0;
  // 문양만 이동: 음수는 위로, 양수는 아래로 (논리 픽셀).
  static const double _patternOffsetY = -3.35;
  // 양옆 선만 함께 이동: 위와 동일.
  static const double _lineOffsetY = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 20,
    child: Row(
      children: [
        Expanded(
          child: Transform.translate(
            offset: const Offset(0, _lineOffsetY),
            child: const Divider(color: _color, thickness: .7),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Transform.translate(
            offset: const Offset(0, _patternOffsetY),
            child: SizedBox(
              width: 72,
              height: 187 * _scale,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: -748 * _scale,
                      top: -230 * _scale,
                      width: 2172 * _scale,
                      height: 724 * _scale,
                      child: Image.asset(
                        'assets/images/onboarding/traditional-pattern.png',
                        color: _color,
                        colorBlendMode: BlendMode.srcIn,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Transform.translate(
            offset: const Offset(0, _lineOffsetY),
            child: const Divider(color: _color, thickness: .7),
          ),
        ),
      ],
    ),
  );
}

class _IllustratedLocationDialog extends StatelessWidget {
  const _IllustratedLocationDialog({
    required this.sectionLabel,
    required this.title,
    required this.description,
    required this.allowLabel,
    required this.declineLabel,
    required this.closeLabel,
  });
  final String sectionLabel,
      title,
      description,
      allowLabel,
      declineLabel,
      closeLabel;
  static const jade = Color(0xFF31786C);
  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final alignment = mobile ? TextAlign.center : TextAlign.start;
    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: mobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          sectionLabel,
          style: const TextStyle(
            color: jade,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: alignment,
          style: TextStyle(
            fontSize: mobile ? 25 : 30,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF292725),
          ),
        ),
      ],
    );
    Widget art(double height) => ExcludeSemantics(
      child: Image.asset(
        'assets/images/onboarding/location-soft-route.png',
        key: const ValueKey('location-permission-art'),
        height: height,
        fit: BoxFit.contain,
      ),
    );
    final body = Text(
      description,
      textAlign: alignment,
      style: const TextStyle(
        fontSize: 13,
        height: 1.85,
        color: Color(0xFF70736F),
      ),
    );
    final allow = FilledButton(
      key: const ValueKey('location-allow'),
      style: FilledButton.styleFrom(
        backgroundColor: jade,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      onPressed: () => Navigator.pop(context, true),
      child: Text(
        allowLabel,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    final decline = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: jade,
        minimumSize: const Size(48, 54),
        shape: StadiumBorder(
          side: mobile
              ? BorderSide.none
              : const BorderSide(color: Color(0xFFA8C3BB)),
        ),
      ),
      onPressed: () => Navigator.pop(context, false),
      child: Text(declineLabel, textAlign: TextAlign.center),
    );
    return Dialog(
      key: const ValueKey('location-explanation'),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.symmetric(
        horizontal: mobile ? 20 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: mobile ? 420 : 760),
        child: SingleChildScrollView(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  mobile ? 22 : 36,
                  mobile ? 30 : 36,
                  mobile ? 22 : 36,
                  mobile ? 16 : 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (mobile) ...[
                      copy,
                      const SizedBox(height: 18),
                      art(140),
                      const SizedBox(height: 18),
                      body,
                    ] else
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                copy,
                                const SizedBox(height: 18),
                                body,
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(flex: 2, child: art(230)),
                        ],
                      ),
                    SizedBox(height: mobile ? 18 : 32),
                    if (mobile) ...[
                      allow,
                      const SizedBox(height: 4),
                      decline,
                    ] else
                      Row(
                        children: [
                          Expanded(child: decline),
                          const SizedBox(width: 16),
                          Expanded(child: allow),
                        ],
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  key: const ValueKey('location-close'),
                  tooltip: closeLabel,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF70736F),
                    size: 22,
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
