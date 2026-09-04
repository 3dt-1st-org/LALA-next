// 이슈 #120 §6/§9: 지도 레일/검색/일정 도슨트 진입점 위젯 계약.
// - 모든 진입은 같은 app-root 컨트롤러의 playPlace/playQueue 로만 연결된다.
// - 진입 버튼 탭은 카드/타일 선택·탭 전환과 독립이다(선택 스토어 게시 금지).
// - 일정 전체 듣기 = 보이는 슬롯 순서 큐; 같은 큐 재생 중에는 정지로 전환.
// - readiness 불가/스크립트 실패는 honest unavailable/failed 상태로 끝난다.
// 가짜 백엔드/플레이어만 사용 — 네트워크·실 오디오 없음.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/state/selected_place_store.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_state.dart';
import 'package:lala_next_app/features/place/widgets/map_rail_place_card.dart';
import 'package:lala_next_app/features/plan/presentation/pages/plan_page.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';

import 'inert_docent_audio_player.dart';

LalaEnvelope<T> _envelope<T>(T data) => LalaEnvelope<T>(
  ok: true,
  data: data,
  meta: const <String, dynamic>{'request_id': 'entry-points-test'},
  error: null,
  statusCode: 200,
  requestId: 'entry-points-test',
);

/// 컨트롤러용 즉시 성공 백엔드(readiness/스크립트/오디오).
class _DocentReadyBackend implements LalaBackend {
  @override
  Future<LalaAudioResponse> createDocentAudio({required String script}) async {
    return LalaAudioResponse(
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      requestId: 'entry-points-test',
      contentType: 'audio/mpeg',
      requestHash: null,
      cacheKey: null,
    );
  }

  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) async {
    return _envelope(
      LalaDocentScript(
        placeId: place.placeId,
        category: place.category,
        language: 'ko',
        mode: mode,
        script: '행궁동 로컬 도슨트 스크립트입니다.',
        source: 'rule_based_curation',
        requestHash: 'a' * 64,
        cacheKey: 'docent_script:entry-points',
      ),
    );
  }

  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async {
    return _envelope(
      LalaReadiness(
        status: 'ok',
        checks: const <String, String>{'live_speech': 'enabled'},
        mode: LalaRuntimeMode(
          overall: 'ok',
          data: 'db-backed',
          ai: 'disabled',
          speech: 'live-azure',
          worker: 'dry-run',
        ),
      ),
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'unused docent endpoint: ${invocation.memberName}',
  );
}

/// readiness 자체가 도달 불가 — 진입 탭 후 honest unavailable.
class _DocentReadinessUnavailableBackend extends _DocentReadyBackend {
  @override
  Future<LalaEnvelope<LalaReadiness>> getReadiness() async {
    throw Exception('readiness unreachable');
  }
}

/// 스크립트 생성 실패(data 없음) — 진입 탭 후 honest failed.
class _DocentScriptFailureBackend extends _DocentReadyBackend {
  @override
  Future<LalaEnvelope<LalaDocentScript>> createDocentScript({
    required LalaPlace place,
    LalaWeather? weather,
    String mode = 'brief',
  }) async {
    return LalaEnvelope<LalaDocentScript>(
      ok: false,
      data: null,
      meta: const <String, dynamic>{'request_id': 'entry-points-test'},
      error: null,
      statusCode: 500,
      requestId: 'entry-points-test',
    );
  }
}

class _ImmediateLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() => Future.value(
    const LalaLocationResult.found(LalaLocation(lat: 37.2636, lng: 127.0286)),
  );
}

/// 검색 탭용: 장소 1개 응답.
class _SearchPlacesBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async {
    return _envelope(
      LalaPlacesResponse(
        count: 1,
        places: <LalaPlace>[_railPlace()],
        query: const LalaPlacesQuery(
          lat: 37.2636,
          lng: 127.0286,
          radiusM: 2000,
          limit: 60,
          category: 'all',
          language: 'ko',
        ),
        source: 'db',
        locationEngine: 'postgis',
      ),
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'unused search endpoint: ${invocation.memberName}',
  );
}

/// 일정 탭용: 장소 있는 슬롯 2개 + 장소 없는 슬롯 1개(가운데) — 큐는 [p1, p2].
class _PlanSlotsBackend implements LalaBackend {
  const _PlanSlotsBackend({this.duplicateMorningPlace = false});

  final bool duplicateMorningPlace;

  @override
  Future<LalaEnvelope<LalaDailyPlan>> createDailyPlan({String? selectedPlaceId}) async {
    return _envelope(
      LalaDailyPlan(
        language: 'ko',
        center: const LalaCoordinate(lat: 37.2636, lng: 127.0286),
        radiusM: 3000,
        weather: LalaWeather(
          lat: 37.2636,
          lng: 127.0286,
          temp: '14°C',
          icon: 'partly-cloudy',
          dust: const LalaDust(
            pm10: '31',
            pm25: '14',
            grade: 'normal',
            gradeKo: '보통',
            pm10Grade: 'normal',
            pm10GradeKo: '보통',
            pm25Grade: 'good',
            pm25GradeKo: '좋음',
          ),
          forecast: const <LalaForecastItem>[],
          outdoorStatus: 'good',
          force: false,
          source: 'db',
        ),
        slots: <LalaPlanSlot>[
          const LalaPlanSlot(
            period: 'morning',
            title: '화성행궁 산책',
            place: LalaPlace(
              placeId: 'rail-p1',
              name: '행궁동 카페거리',
              nameKo: '행궁동 카페거리',
              category: 'culture',
              lat: 37.2636,
              lng: 127.0286,
              address: '경기도 수원시 팔달구',
              regionKo: '수원',
              regionEn: 'Suwon',
              distanceM: 120,
              source: 'db',
            ),
          ),
          if (duplicateMorningPlace)
            const LalaPlanSlot(
              period: 'late-morning',
              title: '행궁동 카페거리 다시 보기',
              place: LalaPlace(
                placeId: 'rail-p1',
                name: '행궁동 카페거리',
                nameKo: '행궁동 카페거리',
                category: 'culture',
                lat: 37.2636,
                lng: 127.0286,
                address: '경기도 수원시 팔달구',
                regionKo: '수원',
                regionEn: 'Suwon',
                distanceM: 120,
                source: 'db',
              ),
            ),
          const LalaPlanSlot(period: 'lunch', title: '행궁동 점심 골목'),
          const LalaPlanSlot(
            period: 'afternoon',
            title: '카페 거리',
            place: LalaPlace(
              placeId: 'rail-p2',
              name: '수원박물관',
              nameKo: '수원박물관',
              category: 'culture',
              lat: 37.2637,
              lng: 127.0287,
              address: '경기도 수원시 영통구',
              regionKo: '수원',
              regionEn: 'Suwon',
              distanceM: 480,
              source: 'db',
            ),
          ),
        ],
        source: 'db',
        // 저엔트로피 테스트 값(detect-secrets 허위 양성 회피; 실제 키/해시 아님).
        requestHash: 'test-entry-points-hash',
        cacheKey: 'daily_plan:entry-points',
      ),
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'unused plan endpoint: ${invocation.memberName}',
  );
}

LalaPlace _railPlace() {
  return const LalaPlace(
    placeId: 'rail-p1',
    name: '행궁동 카페거리',
    nameKo: '행궁동 카페거리',
    category: 'culture',
    lat: 37.2636,
    lng: 127.0286,
    address: '경기도 수원시 팔달구',
    regionKo: '수원',
    regionEn: 'Suwon',
    distanceM: 120,
    source: 'db',
  );
}

DocentExperienceController _controller(LalaBackend docentBackend) {
  final controller = DocentExperienceController(
    backendFactory: (_) => docentBackend,
    baseConfig: const LalaAppConfig(baseUri: 'http://test'),
    player: InertDocentAudioPlayer(),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    RegionContextStore.clear();
    SelectedPlaceStore.clear();
    OnboardingState.selectLanguage('ko');
  });

  tearDown(() {
    RegionContextStore.clear();
    SelectedPlaceStore.clear();
    OnboardingState.reset();
  });

  testWidgets('지도 레일 카드 재생 버튼은 선택 없이 컨트롤러 재생만 시작한다', (tester) async {
    final controller = _controller(_DocentReadyBackend());
    var selectionTaps = 0;
    var docentTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapRailPlaceCard(
              place: _railPlace(),
              language: 'ko',
              selected: false,
              compact: false,
              onTap: () => selectionTaps++,
              onPlayDocent: () {
                docentTaps++;
                controller.playPlace(_railPlace());
              },
            ),
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('map-rail-docent-play-rail-p1'));
    expect(button, findsOneWidget);
    // 44dp 터치 타겟(§13.5).
    expect(tester.getRect(button).size, const Size(44, 44));
    // 지역화 시맨틱 라벨이 버튼에 붙는다(§7).
    expect(find.bySemanticsLabel('도슨트 재생'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(docentTaps, 1);
    // 버튼 탭이 카드 선택(onTap)으로 새지 않는다.
    expect(selectionTaps, 0);
    // 컨트롤러는 이 장소를 대상으로 준비를 마쳤다.
    expect(controller.currentState.phase, DocentExperiencePhase.ready);
    expect(controller.currentState.place?.placeId, 'rail-p1');
    expect(controller.currentState.queueActive, isFalse);
  });

  testWidgets('지도 레일 카드는 onPlayDocent 가 없으면 재생 버튼을 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapRailPlaceCard(
              place: _railPlace(),
              language: 'ko',
              selected: false,
              compact: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('도슨트 재생'), findsNothing);
  });

  testWidgets('readiness 도달 불가 시 진입 탭은 honest unavailable 로 끝난다', (
    tester,
  ) async {
    final controller = _controller(_DocentReadinessUnavailableBackend());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapRailPlaceCard(
              place: _railPlace(),
              language: 'ko',
              selected: false,
              compact: false,
              onTap: () {},
              onPlayDocent: () => controller.playPlace(_railPlace()),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('map-rail-docent-play-rail-p1')),
    );
    await tester.pumpAndSettle();

    expect(controller.currentState.phase, DocentExperiencePhase.unavailable);
  });

  testWidgets('스크립트 생성 실패 시 진입 탭은 honest failed 로 끝난다', (tester) async {
    final controller = _controller(_DocentScriptFailureBackend());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapRailPlaceCard(
              place: _railPlace(),
              language: 'ko',
              selected: false,
              compact: false,
              onTap: () {},
              onPlayDocent: () => controller.playPlace(_railPlace()),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('map-rail-docent-play-rail-p1')),
    );
    await tester.pumpAndSettle();

    expect(controller.currentState.phase, DocentExperiencePhase.failed);
  });

  testWidgets('검색 타일 재생은 선택 게시/탭 전환 없이 재생만 시작한다', (tester) async {
    final controller = _controller(_DocentReadyBackend());
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          locationProvider: _ImmediateLocationProvider(),
          backendFactory: (config) => _SearchPlacesBackend(),
          docentExperienceController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 결과 타일이 로드되었고 아직 아무것도 선택되지 않았다.
    expect(
      find.byKey(const ValueKey('search-place-tile-rail-p1')),
      findsOneWidget,
    );
    expect(SelectedPlaceStore.current, isNull);

    await tester.tap(find.byKey(const ValueKey('search-docent-play-rail-p1')));
    await tester.pumpAndSettle();

    // 재생은 시작되었지만 공유 선택 스토어는 여전히 비었다(지도 전환 없음).
    expect(SelectedPlaceStore.current, isNull);
    expect(controller.currentState.phase, DocentExperiencePhase.ready);
    expect(controller.currentState.place?.placeId, 'rail-p1');
  });

  testWidgets('검색 타일은 컨트롤러 미주입 시 재생 버튼을 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          locationProvider: _ImmediateLocationProvider(),
          backendFactory: (config) => _SearchPlacesBackend(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('search-docent-play-rail-p1')),
      findsNothing,
    );
  });

  testWidgets('일정 전체 듣기: 보이는 슬롯 순서 큐 재생 후 같은 큐면 정지로 전환', (tester) async {
    final controller = _controller(_DocentReadyBackend());
    await tester.pumpWidget(
      MaterialApp(
        home: PlanPage(
          locationProvider: _ImmediateLocationProvider(),
          backendFactory: (config) => _PlanSlotsBackend(),
          docentExperienceController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final playAll = find.byKey(const ValueKey('plan-docent-play-all'));
    expect(playAll, findsOneWidget);
    expect(find.text('전체 도슨트 듣기'), findsOneWidget);

    await tester.tap(playAll);
    await tester.pumpAndSettle();

    // 큐 = 보이는 슬롯 순서 그대로, 장소 없는 슬롯(lunch)은 건너뛴다.
    expect(controller.currentState.queueActive, isTrue);
    expect(
      controller.currentState.queue.map((p) => p.placeId).toList(),
      const <String>['rail-p1', 'rail-p2'],
    );
    // 같은 큐가 재생 중이면 버튼은 정지로 전환한다.
    expect(find.text('도슨트 정지'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-docent-play-all')));
    await tester.pumpAndSettle();

    expect(controller.currentState.phase, DocentExperiencePhase.idle);
    expect(controller.currentState.queueActive, isFalse);
    expect(find.text('전체 도슨트 듣기'), findsOneWidget);
  });

  testWidgets('일정 전체 듣기는 인접 중복 장소를 제거한 큐와 정지 상태를 공유한다', (tester) async {
    final controller = _controller(_DocentReadyBackend());
    await tester.pumpWidget(
      MaterialApp(
        home: PlanPage(
          locationProvider: _ImmediateLocationProvider(),
          backendFactory: (config) =>
              const _PlanSlotsBackend(duplicateMorningPlace: true),
          docentExperienceController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final playAll = find.byKey(const ValueKey('plan-docent-play-all'));
    await tester.tap(playAll);
    await tester.pumpAndSettle();

    expect(
      controller.currentState.queue.map((p) => p.placeId).toList(),
      const <String>['rail-p1', 'rail-p2'],
    );
    expect(find.text('도슨트 정지'), findsOneWidget);

    await tester.tap(playAll);
    await tester.pumpAndSettle();

    expect(controller.currentState.queueActive, isFalse);
    expect(find.text('전체 도슨트 듣기'), findsOneWidget);
  });

  testWidgets('일정 슬롯 개별 재생 버튼은 해당 장소만 playPlace 한다', (tester) async {
    final controller = _controller(_DocentReadyBackend());
    await tester.pumpWidget(
      MaterialApp(
        home: PlanPage(
          locationProvider: _ImmediateLocationProvider(),
          backendFactory: (config) => _PlanSlotsBackend(),
          docentExperienceController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 일정 탭은 리스트 하단까지 스크롤해야 오후 슬롯이 빌드된다(지연 빌드).
    final slotButton = find.byKey(
      const ValueKey('plan-slot-docent-play-rail-p2'),
    );
    await tester.scrollUntilVisible(slotButton, 200);
    await tester.ensureVisible(slotButton);
    await tester.pumpAndSettle();
    await tester.tap(slotButton);
    await tester.pumpAndSettle();

    expect(controller.currentState.place?.placeId, 'rail-p2');
    expect(controller.currentState.queueActive, isFalse);
    expect(controller.currentState.phase, DocentExperiencePhase.ready);
  });

  testWidgets('320dp 폭 + 200% 텍스트 스케일에서 진입 버튼들이 오버플로우 없이 렌더된다', (tester) async {
    final controller = _controller(_DocentReadyBackend());
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: MaterialApp(
          home: SearchPage(
            locationProvider: _ImmediateLocationProvider(),
            backendFactory: (config) => _SearchPlacesBackend(),
            docentExperienceController: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 좁은 화면(320×640)에서는 결과 타일이 첫 화면 아래에 있다 — 결과 리스트를
    // 직접 드래그해 노출시킨다(지연 빌드; 드래그 중에는 프레임별 복제가 있을 수
    // 있으니 pumpAndSettle 후 프레임에서만 판정).
    final button = find.byKey(const ValueKey('search-docent-play-rail-p1'));
    final results = find.byKey(const ValueKey('search-results-view'));
    for (var i = 0; i < 8 && button.evaluate().isEmpty; i++) {
      await tester.drag(results, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    expect(button, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
