// V4-B — Docent narration playback. Provider-agnostic: plays whatever real
// bytes the backend returns in LalaAudioResponse.bytes. Never fabricates audio;
// empty bytes surface as an honest error state. See
// docs/planning/v4-rag-docent-speech-qa-contract.md §V4-B.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Docent narration playback state machine (§V4-B B4).
enum DocentPlaybackState { idle, loading, playing, paused, done, error }

/// Provider-agnostic audio sink for [LalaAudioResponse.bytes].
///
/// Why abstract: tests inject a fake so they never touch a real audio device
/// or the network, and the production impl can swap underneath. Mirrors the
/// V3-D interventionToastLabel separation — keep widgets presentational and
/// sink all I/O behind this seam.
abstract class DocentAudioPlayer {
  Future<void> play(Uint8List bytes);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
  ValueListenable<DocentPlaybackState> get state;
}

/// Production impl backed by `package:audioplayers` ([AudioPlayer] + [BytesSource]).
class AudioplayersDocentAudioPlayer implements DocentAudioPlayer {
  AudioplayersDocentAudioPlayer({AudioPlayer? audioPlayer})
    : _audioPlayer = audioPlayer ?? AudioPlayer() {
    _subscriptions = [
      _audioPlayer.onPlayerStateChanged.listen(_applyPlayerState),
      // The dedicated complete event is authoritative for short clips whose
      // state stream may race; pin `done` here regardless.
      _audioPlayer.onPlayerComplete.listen((_) {
        _state.value = DocentPlaybackState.done;
      }),
      // audioplayers surfaces decode/format failures through onLog rather than
      // throwing; map any reported failure to the honest error state so the UI
      // never hangs on `loading`.
      _audioPlayer.onLog.listen(_applyLog),
    ];
  }

  final AudioPlayer _audioPlayer;
  late final List<StreamSubscription<dynamic>> _subscriptions;
  final ValueNotifier<DocentPlaybackState> _state = ValueNotifier(
    DocentPlaybackState.idle,
  );

  @override
  ValueListenable<DocentPlaybackState> get state => _state;

  @override
  Future<void> play(Uint8List bytes) async {
    if (bytes.isEmpty) {
      // Honesty guard (B3): empty bytes = nothing real to play; never fabricate.
      _state.value = DocentPlaybackState.error;
      return;
    }
    _state.value = DocentPlaybackState.loading;
    try {
      await _audioPlayer.play(BytesSource(bytes));
      // The state stream drives playing/paused; loading stays until the platform
      // emits `playing` (or an error/onLog supersedes it).
    } on Object catch (_) {
      _state.value = DocentPlaybackState.error;
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } on Object catch (_) {
      _state.value = DocentPlaybackState.error;
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _audioPlayer.resume();
    } on Object catch (_) {
      _state.value = DocentPlaybackState.error;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _state.value = DocentPlaybackState.idle;
    } on Object catch (_) {
      _state.value = DocentPlaybackState.error;
    }
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _audioPlayer.dispose();
    _state.dispose();
  }

  void _applyPlayerState(PlayerState playerState) {
    switch (playerState) {
      case PlayerState.playing:
        _state.value = DocentPlaybackState.playing;
      case PlayerState.paused:
        _state.value = DocentPlaybackState.paused;
      case PlayerState.completed:
        _state.value = DocentPlaybackState.done;
      case PlayerState.stopped:
        // An explicit stop() already moved us to idle; only collapse a stray
        // `loading` that the platform never confirmed into idle.
        if (_state.value == DocentPlaybackState.loading) {
          _state.value = DocentPlaybackState.idle;
        }
      case PlayerState.disposed:
        // Player is gone (dispose() path); leave the (likely disposed)
        // notifier untouched rather than writing to it.
        break;
    }
  }

  void _applyLog(String log) {
    final lower = log.toLowerCase();
    if (lower.contains('error') || lower.contains('failed')) {
      _state.value = DocentPlaybackState.error;
    }
  }
}
