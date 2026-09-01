// 위젯/라우터 테스트용 불활성 도슨트 오디오 플레이어.
// 실 오디오 기기·플랫폼 채널·네트워크에 닿지 않는다(이슈 #120 §4 주입 계약).
import 'package:flutter/foundation.dart';

import 'package:lala_next_app/features/docent/playback/docent_audio_player.dart';

/// 재생 상태는 영구 idle — 재생을 구동하는 테스트는 자체 fake 를 쓰고,
/// 쉘/라우터처럼 idle 세션만 다루는 테스트가 안전하게 주입한다.
class InertDocentAudioPlayer implements DocentAudioPlayer {
  final ValueNotifier<DocentPlaybackState> _state = ValueNotifier(
    DocentPlaybackState.idle,
  );

  @override
  ValueListenable<DocentPlaybackState> get state => _state;

  @override
  Future<void> play(Uint8List bytes) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    _state.dispose();
  }
}
