// V4-B — Docent narration playback tests. Uses a FAKE player: no real audio
// device, no network, no live provider call (B9). Covers controller state +
// honest gating + the widget render decision + KO/EN single-language +
// backward-compat for the two existing callers.
// See docs/planning/v4-rag-docent-speech-qa-contract.md §V4-B.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/docent/playback/docent_audio_player.dart';
import 'package:lala_next_app/features/docent/playback/docent_playback_controller.dart';
import 'package:lala_next_app/features/docent/widgets/docent_subtitle.dart';
import 'package:lala_next_app/features/docent/widgets/tour_audio_bar.dart';

/// Offline stand-in for [DocentAudioPlayer]. Records every command and lets the
/// test drive the exposed state to emulate the platform stream — never touches a
/// real audio device or the network.
class _FakeDocentAudioPlayer implements DocentAudioPlayer {
  _FakeDocentAudioPlayer();

  final ValueNotifier<DocentPlaybackState> _state = ValueNotifier(
    DocentPlaybackState.idle,
  );
  final List<Uint8List> playedBytes = [];
  int pauseCount = 0;
  int resumeCount = 0;
  int stopCount = 0;
  bool disposed = false;

  /// Test hook: emulate a platform-driven state change (playing/paused/done).
  void emit(DocentPlaybackState next) => _state.value = next;

  @override
  ValueListenable<DocentPlaybackState> get state => _state;

  @override
  Future<void> play(Uint8List bytes) async {
    playedBytes.add(Uint8List.fromList(bytes));
    _state.value = DocentPlaybackState.loading;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _state.value = DocentPlaybackState.paused;
  }

  @override
  Future<void> resume() async {
    resumeCount++;
    _state.value = DocentPlaybackState.playing;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _state.value = DocentPlaybackState.idle;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _state.dispose();
  }
}

LalaAudioResponse _audio(Uint8List bytes) => LalaAudioResponse(
  bytes: bytes,
  requestId: null,
  contentType: 'audio/mpeg',
  requestHash: null,
  cacheKey: null,
);

Uint8List _sampleBytes() => Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 1, 0]);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('DocentPlaybackController availability (B2/B3)', () {
    test('isAvailable only when speech live AND bytes non-empty', () {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);

      controller.update(audio: null, liveSpeechEnabled: true);
      expect(controller.isAvailable, isFalse, reason: 'audio null → unavailable');

      controller.update(
        audio: _audio(Uint8List(0)),
        liveSpeechEnabled: true,
      );
      expect(controller.isAvailable, isFalse, reason: 'empty bytes → unavailable');

      controller.update(
        audio: _audio(_sampleBytes()),
        liveSpeechEnabled: false,
      );
      expect(
        controller.isAvailable,
        isFalse,
        reason: 'speech off → unavailable even with bytes',
      );

      controller.update(
        audio: _audio(_sampleBytes()),
        liveSpeechEnabled: true,
      );
      expect(controller.isAvailable, isTrue);
    });

    test('togglePlay is a no-op when unavailable (never plays fabricated audio)', () async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);

      controller.update(audio: null, liveSpeechEnabled: true);
      await controller.togglePlay();
      controller.update(audio: _audio(Uint8List(0)), liveSpeechEnabled: true);
      await controller.togglePlay();
      controller.update(audio: _audio(_sampleBytes()), liveSpeechEnabled: false);
      await controller.togglePlay();

      expect(fake.playedBytes, isEmpty);
      expect(fake.pauseCount, 0);
      expect(fake.resumeCount, 0);
    });
  });

  group('DocentPlaybackController state machine (B4)', () {
    test('idle→loading→playing↔paused→done replays', () async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      final bytes = _sampleBytes();
      controller.update(audio: _audio(bytes), liveSpeechEnabled: true);

      // idle → play() drives loading.
      expect(controller.state.value, DocentPlaybackState.idle);
      await controller.togglePlay();
      expect(fake.playedBytes.last, bytes);
      expect(controller.state.value, DocentPlaybackState.loading);

      // platform confirms playing.
      fake.emit(DocentPlaybackState.playing);
      expect(controller.state.value, DocentPlaybackState.playing);

      // playing → pause.
      await controller.togglePlay();
      expect(fake.pauseCount, 1);
      expect(controller.state.value, DocentPlaybackState.paused);

      // paused → resume.
      await controller.togglePlay();
      expect(fake.resumeCount, 1);
      expect(controller.state.value, DocentPlaybackState.playing);

      // done → next toggle replays from idle-equivalent (done branch).
      fake.emit(DocentPlaybackState.done);
      expect(controller.state.value, DocentPlaybackState.done);
      await controller.togglePlay();
      expect(fake.playedBytes.length, 2);
      expect(fake.playedBytes.last, bytes);

      // loading toggles are ignored (no interleaved commands).
      fake.emit(DocentPlaybackState.loading);
      await controller.togglePlay();
      expect(fake.playedBytes.length, 2, reason: 'no new play while loading');
    });

    test('error state is reachable and replayable', () async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(audio: _audio(_sampleBytes()), liveSpeechEnabled: true);

      fake.emit(DocentPlaybackState.error);
      expect(controller.state.value, DocentPlaybackState.error);
      // From error a toggle replays (error is a terminal-ish reset branch).
      await controller.togglePlay();
      expect(fake.playedBytes.length, 1);
    });

    test('update with changed bytes stops any in-flight session', () async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(audio: _audio(_sampleBytes()), liveSpeechEnabled: true);
      await controller.togglePlay();
      fake.emit(DocentPlaybackState.playing);

      controller.update(
        audio: _audio(Uint8List.fromList([9, 9, 9])),
        liveSpeechEnabled: true,
      );
      expect(fake.stopCount, greaterThanOrEqualTo(1));
      expect(controller.state.value, DocentPlaybackState.idle);

      controller.update(audio: null, liveSpeechEnabled: true);
      expect(controller.isAvailable, isFalse);
    });

    test('stop() forwards to the player', () async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(audio: _audio(_sampleBytes()), liveSpeechEnabled: true);
      // update() may stop on a bytes change; assert the forward delta, not the
      // absolute count.
      final before = fake.stopCount;
      await controller.stop();
      expect(fake.stopCount, before + 1);
    });
  });

  group('DocentSubtitle playback wiring', () {
    testWidgets('available + playing → pause control (KO)', (tester) async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(
        audio: _audio(_sampleBytes()),
        liveSpeechEnabled: true,
        scriptText: '행궁동 로컬 도슨트 스크립트',
      );
      await tester.pumpWidget(
        _wrap(
          DocentSubtitle(
            place: null,
            language: 'ko',
            script: '행궁동 로컬 도슨트 스크립트',
            action: null,
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            playbackController: controller,
          ),
        ),
      );
      // idle initially → shows the ready caption + play affordance.
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('재생 가능'), findsOneWidget);

      fake.emit(DocentPlaybackState.playing);
      await tester.pump();
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byTooltip('일시정지'), findsOneWidget);
      expect(find.text('재생 중'), findsOneWidget);
    });

    testWidgets('available + playing → pause control (EN single-language)', (
      tester,
    ) async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(
        audio: _audio(_sampleBytes()),
        liveSpeechEnabled: true,
        scriptText: 'Local docent script',
      );
      await tester.pumpWidget(
        _wrap(
          DocentSubtitle(
            place: null,
            language: 'en',
            script: 'Local docent script',
            action: null,
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            playbackController: controller,
          ),
        ),
      );
      fake.emit(DocentPlaybackState.playing);
      await tester.pump();
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.text('Playing'), findsOneWidget);
      // EN only — no KO copy leaks.
      expect(find.text('재생 중'), findsNothing);
    });

    testWidgets('!liveSpeechEnabled → honest unavailable KO, no play control', (
      tester,
    ) async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(
        audio: _audio(_sampleBytes()),
        liveSpeechEnabled: false,
      );
      await tester.pumpWidget(
        _wrap(
          DocentSubtitle(
            place: null,
            language: 'ko',
            script: '스크립트',
            action: null,
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            playbackController: controller,
          ),
        ),
      );
      expect(find.text('음성을 사용할 수 없어요'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('bytes null after fetch → honest unavailable EN', (tester) async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(audio: null, liveSpeechEnabled: true);
      await tester.pumpWidget(
        _wrap(
          DocentSubtitle(
            place: null,
            language: 'en',
            script: 'script',
            action: null,
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            playbackController: controller,
          ),
        ),
      );
      expect(find.text('Voice guide unavailable'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('empty bytes → honest unavailable (no fabricated audio)', (
      tester,
    ) async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(
        audio: _audio(Uint8List(0)),
        liveSpeechEnabled: true,
      );
      await tester.pumpWidget(
        _wrap(
          DocentSubtitle(
            place: null,
            language: 'ko',
            script: 's',
            action: null,
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            playbackController: controller,
          ),
        ),
      );
      expect(find.text('음성을 사용할 수 없어요'), findsOneWidget);
      expect(fake.playedBytes, isEmpty);
    });

    testWidgets('tapping play drives the controller (real bytes)', (tester) async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      final bytes = _sampleBytes();
      controller.update(audio: _audio(bytes), liveSpeechEnabled: true);
      await tester.pumpWidget(
        _wrap(
          DocentSubtitle(
            place: null,
            language: 'ko',
            script: 's',
            action: null,
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            playbackController: controller,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(fake.playedBytes.last, bytes);
    });

    testWidgets(
      'backward-compat: no controller → fetch-only, no playback row (B5)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            DocentSubtitle(
              place: null,
              language: 'ko',
              script: '스크립트',
              action: null,
              audioLoading: false,
              audioError: null,
              docentAudio: null,
              canFetchAudio: true,
              onFetchAudio: () {},
            ),
          ),
        );
        // Existing fetch affordance present, playback row absent.
        expect(find.text('정보 더 듣기'), findsOneWidget);
        expect(find.text('음성을 사용할 수 없어요'), findsNothing);
        expect(find.byType(IconButton), findsNothing);
      },
    );
  });

  group('TourAudioBar playback wiring', () {
    testWidgets('available + playing → pause toggle (KO)', (tester) async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(
        audio: _audio(_sampleBytes()),
        liveSpeechEnabled: true,
      );
      await tester.pumpWidget(
        _wrap(
          TourAudioBar(
            language: 'ko',
            audio: null,
            loading: false,
            error: null,
            onFetchAudio: () {},
            playbackController: controller,
          ),
        ),
      );
      fake.emit(DocentPlaybackState.playing);
      await tester.pump();
      expect(find.byTooltip('일시정지'), findsOneWidget);
      // No fabricated fetch button once playback is the active control.
      expect(find.text('오디오 준비'), findsNothing);
    });

    testWidgets(
      '!liveSpeechEnabled → honest unavailable, fetch control hidden (B2)',
      (tester) async {
        final fake = _FakeDocentAudioPlayer();
        final controller = DocentPlaybackController(fake);
        controller.update(
          audio: _audio(_sampleBytes()),
          liveSpeechEnabled: false,
        );
        await tester.pumpWidget(
          _wrap(
            TourAudioBar(
              language: 'ko',
              audio: null,
              loading: false,
              error: null,
              onFetchAudio: () {},
              playbackController: controller,
            ),
          ),
        );
        expect(find.text('음성을 사용할 수 없어요'), findsWidgets);
        expect(find.byType(IconButton), findsNothing);
        expect(find.text('오디오 준비'), findsNothing);
      },
    );

    testWidgets('speech on + no bytes → fetch control retained', (tester) async {
      final fake = _FakeDocentAudioPlayer();
      final controller = DocentPlaybackController(fake);
      controller.update(audio: null, liveSpeechEnabled: true);
      await tester.pumpWidget(
        _wrap(
          TourAudioBar(
            language: 'en',
            audio: null,
            loading: false,
            error: null,
            onFetchAudio: () {},
            playbackController: controller,
          ),
        ),
      );
      expect(find.text('Prepare audio'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets(
      'backward-compat: no controller → existing bar unchanged (B5)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            TourAudioBar(
              language: 'ko',
              audio: null,
              loading: false,
              error: null,
              onFetchAudio: () {},
            ),
          ),
        );
        expect(find.text('오디오 준비'), findsOneWidget);
        expect(find.text('음성을 사용할 수 없어요'), findsNothing);
        expect(find.byType(IconButton), findsNothing);
      },
    );
  });
}
