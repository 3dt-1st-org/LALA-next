import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lala_next_app/features/docent/playback/docent_audio_player.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';

class RecordingPlayer extends Fake implements AudioPlayer {
  final calls = <String>[];
  @override
  Stream<PlayerState> get onPlayerStateChanged => const Stream.empty();
  @override
  Stream<void> get onPlayerComplete => const Stream.empty();
  @override
  Stream<String> get onLog => const Stream.empty();
  @override
  Future<void> setSource(Source source) async {
    calls.add('source');
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    calls.add('rate:$rate');
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('saved narration speed is applied before play and on resume', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TravelPreferencesStore();
    await store.ensureLoaded();
    await store.save(store.value.copyWith(narrationSpeed: 1.2));
    final platform = RecordingPlayer();
    final player = AudioplayersDocentAudioPlayer(
      audioPlayer: platform,
      preferencesStore: store,
    );
    await player.play(Uint8List.fromList([1, 2]));
    expect(platform.calls, ['source', 'rate:1.2', 'resume']);
    await store.save(store.value.copyWith(narrationSpeed: 0.8));
    await player.resume();
    expect(platform.calls.sublist(3), ['rate:0.8', 'resume']);
    await player.dispose();
    store.dispose();
  });
}
