// CP2: 발음 도움(proununciationHelp) 실동작 계약 — 저장된 스위치가 켜져 있을 때만
// 노출, 명시적 탭 후 주입된 시스템 스피치 어댑터만 사용, 사용 불가/실패/취소/
// 폐기 경로는 정직하게 처리한다. 위젯/유닛 테스트는 절대 실 오디오를 호출하지
// 않는다(가짜 어댑터 주입).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/restaurant_communication_sheet.dart';
import 'package:lala_next_app/shared/speech/flutter_tts_system_speech.dart';
import 'package:lala_next_app/shared/speech/system_speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSheet(
    WidgetTester tester, {
    required TravelPreferences preferences,
    required SystemSpeech speech,
    String language = 'ko',
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          home: Scaffold(
            body: RestaurantCommunicationSheet(
              language: language,
              preferences: preferences,
              speech: speech,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pronunciationHelp=false shows no speech action', (tester) async {
    final speech = _FakeSystemSpeech();
    await pumpSheet(
      tester,
      preferences: const TravelPreferences(
        allergens: {Allergen.nuts},
      ),
      speech: speech,
    );

    expect(
      find.byKey(const ValueKey('restaurant-pronunciation-listen')),
      findsNothing,
    );
    expect(speech.speakCalls, isEmpty);
    // Copy and large text remain available.
    expect(
      find.byKey(const ValueKey('restaurant-large-text-mode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('copy-korean-restaurant-card')),
      findsOneWidget,
    );
  });

  testWidgets('explicit tap speaks the Korean card through the adapter', (
    tester,
  ) async {
    final speech = _FakeSystemSpeech();
    const preferences = TravelPreferences(
      pronunciationHelp: true,
      spiceLevel: SpicePreference.mild,
    );
    await pumpSheet(tester, preferences: preferences, speech: speech);

    final listen = find.byKey(const ValueKey('restaurant-pronunciation-listen'));
    expect(listen, findsOneWidget);

    await tester.tap(listen);
    await tester.pumpAndSettle();

    expect(speech.speakCalls, hasLength(1));
    expect(speech.speakCalls.single, buildKoreanRestaurantRequestCard(preferences));
    // The control flips to an explicit cancellable stop state.
    expect(
      find.byKey(const ValueKey('restaurant-pronunciation-stop')),
      findsOneWidget,
    );
  });

  testWidgets('tap while speaking cancels the utterance', (tester) async {
    final speech = _FakeSystemSpeech();
    await pumpSheet(
      tester,
      preferences: const TravelPreferences(pronunciationHelp: true),
      speech: speech,
    );

    await tester.tap(find.byKey(const ValueKey('restaurant-pronunciation-listen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restaurant-pronunciation-stop')));
    await tester.pumpAndSettle();

    expect(speech.stopCalls, greaterThanOrEqualTo(1));
    expect(
      find.byKey(const ValueKey('restaurant-pronunciation-listen')),
      findsOneWidget,
    );
  });

  testWidgets('natural completion returns to idle without a success claim', (
    tester,
  ) async {
    final speech = _FakeSystemSpeech();
    await pumpSheet(
      tester,
      preferences: const TravelPreferences(pronunciationHelp: true),
      speech: speech,
    );

    await tester.tap(find.byKey(const ValueKey('restaurant-pronunciation-listen')));
    await tester.pumpAndSettle();
    speech.finishUtterance();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('restaurant-pronunciation-listen')),
      findsOneWidget,
    );
  });

  testWidgets('unavailable device shows an honest notice, copy still works', (
    tester,
  ) async {
    final speech = _FakeSystemSpeech(koreanAvailable: false);
    await pumpSheet(
      tester,
      preferences: const TravelPreferences(pronunciationHelp: true),
      speech: speech,
    );

    expect(
      find.byKey(const ValueKey('restaurant-pronunciation-unavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('이 기기에서는 한국어 발음 재생을 지원하지 않아요'), findsOneWidget);
    expect(speech.speakCalls, isEmpty);
    // Copy and large text remain usable.
    expect(
      find.byKey(const ValueKey('restaurant-large-text-mode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('copy-korean-restaurant-card')),
      findsOneWidget,
    );
  });

  testWidgets('failed start surfaces a retry notice, never a success state', (
    tester,
  ) async {
    final speech = _FakeSystemSpeech(startOutcome: SystemSpeechOutcome.failed);
    await pumpSheet(
      tester,
      preferences: const TravelPreferences(pronunciationHelp: true),
      speech: speech,
    );

    await tester.tap(find.byKey(const ValueKey('restaurant-pronunciation-listen')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('restaurant-pronunciation-problem')),
      findsOneWidget,
    );
    expect(find.textContaining('발음을 재생하지 못했어요'), findsOneWidget);
    // Still idle — the tap alone did not count as success.
    expect(
      find.byKey(const ValueKey('restaurant-pronunciation-listen')),
      findsOneWidget,
    );
  });

  testWidgets('disposing the sheet stops and releases speech', (tester) async {
    final speech = _FakeSystemSpeech();
    await pumpSheet(
      tester,
      preferences: const TravelPreferences(pronunciationHelp: true),
      speech: speech,
    );

    await tester.tap(find.byKey(const ValueKey('restaurant-pronunciation-listen')));
    await tester.pumpAndSettle();

    // Replace the sheet (its State disposes).
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();

    expect(speech.disposeCalls, 1);
    expect(speech.stopCalls, greaterThanOrEqualTo(1));
  });

  for (final scale in <double>[1, 2]) {
    testWidgets('pronunciation control renders at ${scale * 100}% text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSheet(
        tester,
        preferences: const TravelPreferences(
          pronunciationHelp: true,
          spiceLevel: SpicePreference.medium,
          orderRequests: {RestaurantOrderRequest.quietTable},
        ),
        speech: _FakeSystemSpeech(),
        language: 'en',
        scale: scale,
      );

      expect(tester.takeException(), isNull);
      // The control may sit below the lazy viewport fold at 200%; scrolling
      // to it proves it renders rather than being clipped away.
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('restaurant-communication-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('restaurant-pronunciation-listen')),
        160,
        scrollable: scrollable,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('restaurant-pronunciation-listen')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('restaurant-visitor-request-card')),
        160,
        scrollable: scrollable,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('restaurant-visitor-request-card')),
        findsOneWidget,
      );
    });
  }

  group('FlutterTtsSystemSpeech (mocked platform channel, no real audio)', () {
    const channel = MethodChannel('flutter_tts');

    tearDown(() {
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> mockChannel(
      List<MethodCall> calls, {
      Object? Function(String method)? results,
    }) async {
      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return results?.call(call.method) ?? 1;
          });
    }

    test('speaks with the Korean locale before uttering the text', () async {
      final calls = <MethodCall>[];
      await mockChannel(calls);

      final speech = FlutterTtsSystemSpeech();
      addTearDown(speech.dispose);
      final outcome = await speech.speakKorean('안녕하세요');

      expect(outcome, SystemSpeechOutcome.started);
      final methods = calls.map((call) => call.method).toList();
      // Locale first, then the availability guard, then the utterance.
      expect(methods.indexOf('setLanguage'), lessThan(methods.indexOf('speak')));
      expect(
        calls.where((call) => call.method == 'setLanguage').single.arguments,
        'ko-KR',
      );
      expect(calls.where((call) => call.method == 'speak').single.arguments,
          '안녕하세요');
    });

    test('reports unavailable when the device has no Korean voice', () async {
      final calls = <MethodCall>[];
      await mockChannel(
        calls,
        results: (method) => method == 'isLanguageAvailable' ? 0 : 1,
      );

      final speech = FlutterTtsSystemSpeech();
      addTearDown(speech.dispose);
      expect(await speech.isKoreanAvailable(), isFalse);
      expect(
        await speech.speakKorean('안녕하세요'),
        SystemSpeechOutcome.unavailable,
      );
      expect(calls.where((call) => call.method == 'speak'), isEmpty);
    });

    test('a missing plugin degrades honestly instead of crashing', () async {
      // No mock handler registered: every channel call throws
      // MissingPluginException, like a test host without the engine plugin.
      final speech = FlutterTtsSystemSpeech();
      addTearDown(speech.dispose);

      expect(await speech.isKoreanAvailable(), isFalse);
      expect(
        await speech.speakKorean('안녕하세요'),
        anyOf(SystemSpeechOutcome.unavailable, SystemSpeechOutcome.failed),
      );
      await speech.stop();
      speech.dispose();
    });
  });
}

class _FakeSystemSpeech implements SystemSpeech {
  _FakeSystemSpeech({
    this.koreanAvailable = true,
    this.startOutcome = SystemSpeechOutcome.started,
  });

  final bool koreanAvailable;
  final SystemSpeechOutcome startOutcome;

  final List<String> speakCalls = [];
  int stopCalls = 0;
  int disposeCalls = 0;
  void Function()? _onFinished;

  @override
  Future<bool> isKoreanAvailable() async => koreanAvailable;

  @override
  Future<SystemSpeechOutcome> speakKorean(String text) async {
    speakCalls.add(text);
    return startOutcome;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  void dispose() {
    disposeCalls += 1;
    _onFinished = null;
    stopCalls += 1;
  }

  @override
  void setOnUtteranceFinished(void Function() onFinished) {
    _onFinished = onFinished;
  }

  void finishUtterance() {
    final callback = _onFinished;
    if (callback != null) callback();
  }
}
