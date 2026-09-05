import 'package:flutter_tts/flutter_tts.dart';

import 'package:lala_next_app/shared/speech/system_speech.dart';

/// [SystemSpeech] backed by flutter_tts — the on-device system speech engine
/// (AVSpeechSynthesizer on iOS/macOS, Android TextToSpeech, the browser
/// speechSynthesis API on web). No network speech service is involved.
///
/// Errors from the platform channel (including the missing-plugin case) are
/// captured and reported honestly as [SystemSpeechOutcome.failed] /
/// `isKoreanAvailable() == false`; they never crash the sheet.
class FlutterTtsSystemSpeech implements SystemSpeech {
  FlutterTtsSystemSpeech() {
    _tts = FlutterTts();
    _tts.setCompletionHandler(_notifyFinished);
    _tts.setCancelHandler(_notifyFinished);
    _tts.setErrorHandler((_) => _notifyFinished());
  }

  static const String _koreanLocale = 'ko-KR';

  late final FlutterTts _tts;
  bool? _koreanAvailable;
  void Function()? _onFinished;

  /// flutter_tts returns dynamic booleans per platform (iOS: 1/0 int,
  /// Android: bool, web: 1/'1'). Normalize without inventing success.
  static bool _platformTrue(Object? value) =>
      value == true || value == 1 || value == '1';

  @override
  Future<bool> isKoreanAvailable() async {
    final cached = _koreanAvailable;
    if (cached != null) return cached;
    try {
      final available = await _tts.isLanguageAvailable(_koreanLocale);
      return _koreanAvailable = _platformTrue(available);
    } on Object {
      return _koreanAvailable = false;
    }
  }

  @override
  Future<SystemSpeechOutcome> speakKorean(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return SystemSpeechOutcome.failed;
    try {
      final languageSet = await _tts.setLanguage(_koreanLocale);
      if (!_platformTrue(languageSet)) return SystemSpeechOutcome.unavailable;
      // Speak the Korean text with a Korean voice — never another locale's
      // voice approximating Korean.
      if (!await isKoreanAvailable()) return SystemSpeechOutcome.unavailable;
      final spoken = await _tts.speak(trimmed);
      return _platformTrue(spoken)
          ? SystemSpeechOutcome.started
          : SystemSpeechOutcome.failed;
    } on Object {
      return SystemSpeechOutcome.failed;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Stopping a dead engine is a no-op; the sheet is closing anyway.
    }
  }

  @override
  void dispose() {
    _onFinished = null;
    // Fire-and-forget: dispose() must not block the element tree teardown,
    // but the utterance must be cancelled immediately.
    _tts.stop().catchError((_) {});
  }

  @override
  void setOnUtteranceFinished(void Function() onFinished) {
    _onFinished = onFinished;
  }

  void _notifyFinished() {
    final callback = _onFinished;
    if (callback != null) callback();
  }
}
