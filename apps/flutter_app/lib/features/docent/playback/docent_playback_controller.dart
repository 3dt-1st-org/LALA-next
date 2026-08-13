// V4-B — Per-surface docent playback controller. Owns the playback decision:
// fed LalaAudioResponse? + the liveSpeechEnabled gate, it exposes a single
// ValueListenable<DocentPlaybackState> + the script line, and togglePlay/stop.
// Keeps the widget presentational (mirrors the V3-D interventionToastLabel
// separation). See docs/planning/v4-rag-docent-speech-qa-contract.md §V4-B.
import 'package:flutter/foundation.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'docent_audio_player.dart';

class DocentPlaybackController {
  DocentPlaybackController(this._player);

  final DocentAudioPlayer _player;
  LalaAudioResponse? _audio;
  bool _liveSpeechEnabled = false;
  String? _scriptText;

  /// Raw player state machine (idle/loading/playing/paused/done/error).
  ValueListenable<DocentPlaybackState> get state => _player.state;

  /// Script line rendered alongside the controls (single-language at call site).
  String? get scriptText => _scriptText;

  bool get liveSpeechEnabled => _liveSpeechEnabled;

  /// Honest availability (B2/B3): speech live AND real non-empty bytes present.
  /// When false the widget shows the unavailable line and hides the play control.
  bool get isAvailable =>
      _liveSpeechEnabled && _audio != null && _audio!.bytes.isNotEmpty;

  /// Feed the latest docent audio response + the speech gate + script text.
  ///
  /// Switching the underlying bytes (new place / re-fetched audio) or losing
  /// availability resets any in-flight session so the widget never offers
  /// resume against stale or gone audio.
  void update({
    LalaAudioResponse? audio,
    required bool liveSpeechEnabled,
    String? scriptText,
  }) {
    final previousBytes = _audio?.bytes;
    _audio = audio;
    _liveSpeechEnabled = liveSpeechEnabled;
    _scriptText = scriptText;
    final bytesChanged = !identical(previousBytes, _audio?.bytes);
    if (!isAvailable || bytesChanged) {
      // No-op when already idle; resets a playing/paused session otherwise.
      _player.stop();
    }
  }

  Uint8List? get _bytes => _audio?.bytes;

  /// Toggle play/pause/resume. Honest no-op when unavailable so the widget can
  /// wire this to the same tap target unconditionally.
  Future<void> togglePlay() async {
    if (!isAvailable) {
      return;
    }
    switch (state.value) {
      case DocentPlaybackState.playing:
        await _player.pause();
      case DocentPlaybackState.paused:
        await _player.resume();
      case DocentPlaybackState.idle:
      case DocentPlaybackState.done:
      case DocentPlaybackState.error:
        await _player.play(_bytes!);
      case DocentPlaybackState.loading:
        // Ignore double-taps mid-transition to avoid interleaved commands.
        break;
    }
  }

  Future<void> stop() => _player.stop();

  void dispose() => _player.dispose();
}
