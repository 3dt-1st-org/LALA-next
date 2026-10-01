part of 'home_screen.dart';

class _LalaGuide extends StatelessWidget {
  const _LalaGuide({
    required this.language,
    this.sheet = false,
    this.scrollController,
    this.onHandleDrag,
    this.onHandleEnd,
  });
  final ScrollController? scrollController;
  final GestureDragUpdateCallback? onHandleDrag;
  final GestureDragEndCallback? onHandleEnd;
  final String language;
  final bool sheet;
  String t(String ko, String en) => language == 'ko' ? ko : en;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _homeJade,
        primary: _homeJade,
        surface: Colors.white,
      ),
    ),
    child: Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          key: const ValueKey('lala-guide'),
          children: [
            if (sheet)
              GestureDetector(
                key: const ValueKey('guide-drag-handle'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: onHandleDrag,
                onVerticalDragEnd: onHandleEnd,
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 0),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD5E1DB),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 12, 4),
              child: Row(
                children: [
                  const Text(
                    'LALA',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _homeJade,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t('처음 만나는 LALA', 'Welcome to LALA'),
                      style: const TextStyle(
                        color: Color(0xFF707A75),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('guide-close'),
                    tooltip: t('닫기', 'Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('guide-scroll'),
                controller: scrollController,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final wide = box.maxWidth >= 620;
                    final pad = wide ? 36.0 : 24.0;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(pad, 8, pad, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Stack(
                              children: [
                                SizedBox(
                                  height: wide ? 190 : 150,
                                  width: double.infinity,
                                  child: Image.asset(
                                    'assets/images/onboarding/lala-guide-travel-v2.png',
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  bottom: 14,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xF2FFFFFF),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'LOCAL AREA, LOCAL ANSWER',
                                      style: const TextStyle(
                                        color: _homeJade,
                                        fontSize: 10,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            t(
                              '낯선 풍경이,\n나의 이야기가 되는 여행.',
                              'Make an unfamiliar place\npart of your own story.',
                            ),
                            style: TextStyle(
                              fontSize: wide ? 30 : 25,
                              height: 1.3,
                              color: _homeInk,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t(
                              '궁궐의 기와 너머, 골목의 모퉁이에도 이야기가 있어요.\nLALA와 함께 장소에 담긴 이야기를 만나고, 마음이 가는 곳으로 한국 여행을 이어가 보세요.',
                              'There are stories beyond palace rooftops and around every corner. Discover the places that speak to you, and explore Korea with LALA.',
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.7,
                              color: Color(0xFF68736D),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Row(
                            children: [
                              Container(width: 24, height: 2, color: _homeJade),
                              const SizedBox(width: 10),
                              Text(
                                t('이렇게 여행해 보세요', 'YOUR JOURNEY WITH LALA'),
                                style: const TextStyle(
                                  color: _homeJade,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, grid) {
                              final width = wide
                                  ? (grid.maxWidth - 14) / 2
                                  : grid.maxWidth;
                              final steps = [
                                (
                                  '01',
                                  Icons.location_on_outlined,
                                  t('어디서 시작할까요?', 'Where shall we begin?'),
                                  t(
                                    '지금 여행 중이라면 ‘내 주변’을, 떠날 곳이 정해졌다면 ‘지역 변경’을 눌러보세요.',
                                    'Choose “Near me” while travelling, or select a destination with “Change area”.',
                                  ),
                                  t(
                                    '위치를 허용하지 않아도 지역을 직접 고를 수 있어요.',
                                    'You can choose an area without sharing your location.',
                                  ),
                                ),
                                (
                                  '02',
                                  Icons.explore_outlined,
                                  t('마음에 드는 곳을 발견해요', 'Find a place you love'),
                                  t(
                                    '가까운 지역과 명소·음식·문화 분류를 둘러보세요. 검색창으로 현재 목록의 장소를 찾을 수도 있어요.',
                                    'Browse nearby areas, sights, food and culture. Search to find places in the current list.',
                                  ),
                                  t(
                                    '하트를 누르면 다시 보고 싶은 장소를 저장해요.',
                                    'Tap the heart to save a place for later.',
                                  ),
                                ),
                                (
                                  '03',
                                  Icons.headphones_outlined,
                                  t(
                                    '장소에 담긴 이야기를 만나요',
                                    'Meet the story behind the place',
                                  ),
                                  t(
                                    '장소 카드의 ‘이야기 듣기’를 누르면 상세 화면이 열려요. 장소 정보와 도슨트 안내를 함께 살펴보세요.',
                                    'Open a place card to discover its details and audio-guide information.',
                                  ),
                                  t(
                                    '지도에서 위치를 확인하면 다음 발걸음을 정하기 쉬워요.',
                                    'Check the map to decide where to head next.',
                                  ),
                                ),
                                (
                                  '04',
                                  Icons.route_outlined,
                                  t(
                                    '나만의 하루를 그려보세요',
                                    'Plan a day that feels like you',
                                  ),
                                  t(
                                    '‘여행 계획’이나 ‘내 여행’에서 탐색 중인 지역을 바탕으로 하루의 코스를 살펴보세요.',
                                    'Open “Plan a trip” or “My trip” to explore a day plan for your chosen area.',
                                  ),
                                  t(
                                    'MY에서 여행 취향과 안내 설정을 언제든 바꿀 수 있어요.',
                                    'Update your interests and guide preferences in MY.',
                                  ),
                                ),
                              ];
                              return Wrap(
                                spacing: 14,
                                runSpacing: 14,
                                children: steps
                                    .map(
                                      (step) => SizedBox(
                                        width: width,
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF4F8F6),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      step.$2,
                                                      color: _homeJade,
                                                      size: 24,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    step.$1,
                                                    style: const TextStyle(
                                                      fontSize: 24,
                                                      fontWeight:
                                                          FontWeight.w300,
                                                      color: Color(0xFF9FBDB0),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                step.$3,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  height: 1.4,
                                                  fontWeight: FontWeight.w700,
                                                  color: _homeInk,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                step.$4,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  height: 1.65,
                                                  color: Color(0xFF58665E),
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              Container(
                                                width: double.infinity,
                                                height: 1,
                                                color: const Color(0xFFDCE8E1),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                step.$5,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  height: 1.6,
                                                  color: _homeJade,
                                                ),
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
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE0E9E4),
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.waving_hand_outlined,
                                  color: _homeJade,
                                  size: 24,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t(
                                          '가볍게 시작해도 괜찮아요',
                                          'Start with a little curiosity',
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        t(
                                          '회원가입 없이 둘러볼 수 있어요. 처음부터 모든 계획을 세우지 않아도 괜찮아요. 궁금한 장소 하나부터 만나보세요.',
                                          'You can explore without an account. You don’t need a perfect itinerary—start with one place that makes you curious.',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.6,
                                          color: Color(0xFF68736D),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              key: const ValueKey('guide-actions'),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEDF1EE))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 'region'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _homeJade,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(t('지역 고르기', 'Choose an area')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('guide-start'),
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: _homeJade,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(t('여행지 둘러보기', 'Let’s explore')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ExpandableGuide extends StatefulWidget {
  const _ExpandableGuide({required this.language});
  final String language;
  @override
  State<_ExpandableGuide> createState() => _ExpandableGuideState();
}

class _ExpandableGuideState extends State<_ExpandableGuide> {
  final _controller = DraggableScrollableController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return DraggableScrollableSheet(
        key: const ValueKey('guide-expandable-sheet'),
        controller: _controller,
        initialChildSize: .72,
        minChildSize: .45,
        maxChildSize: 1,
        expand: false,
        snap: true,
        snapSizes: const [.72],
        builder: (context, scrollController) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(
                _controller.isAttached && _controller.size >= .99 ? 0 : 28,
              ),
            ),
            child: _LalaGuide(
              language: widget.language,
              sheet: true,
              scrollController: scrollController,
              onHandleDrag: (details) {
                if (_controller.isAttached) {
                  _controller.jumpTo(
                    (_controller.size -
                            details.delta.dy / constraints.maxHeight)
                        .clamp(.45, 1),
                  );
                }
              },
              onHandleEnd: (details) {
                if (!_controller.isAttached ||
                    ModalRoute.of(context)?.isCurrent != true) {
                  return;
                }
                final size = _controller.size;
                if (size <= .5) {
                  Navigator.pop(context);
                  return;
                }
                final velocity = details.primaryVelocity ?? 0;
                final target = velocity < -300
                    ? 1.0
                    : velocity > 300
                    ? .72
                    : size > .86
                    ? 1.0
                    : .72;
                _controller.animateTo(
                  target,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
