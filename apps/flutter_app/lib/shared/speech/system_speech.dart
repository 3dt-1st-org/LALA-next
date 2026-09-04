/// CP2: injectable on-device system speech boundary for the restaurant
/// communication card.
///
/// Contract (restaurant pronunciation help):
/// - Only the platform's built-in speech engine may run. No backend call, no
///   paid provider, no network speech, no fabricated audio, no hidden
///   fallback beep/vibration pretending to be speech.
/// - Speech is always user-initiated, cancellable, and must stop when the
///   owning sheet/page is disposed. Nothing auto-plays.
/// - Implementations must be honest: `speakKorean` reports whether speech
///   actually started, and `isKoreanAvailable` reports whether the device can
///   speak Korean at all. A failed or unavailable attempt is surfaced to the
///   caller — a tapped button alone never counts as success.
///
/// Widget and unit tests inject a fake; they must never construct the real
/// platform adapter.
abstract interface class SystemSpeech {
  /// Whether this device exposes a system voice that can speak Korean.
  ///
  /// Implementations cache the answer after the first check. When this is
  /// false the UI shows an honest localized unavailable state instead of a
  /// dead action.
  Future<bool> isKoreanAvailable();

  /// Starts speaking [text] with a Korean locale.
  ///
  /// Returns [SystemSpeechOutcome.started] only when the platform accepted
  /// the utterance. [SystemSpeechOutcome.unavailable] means the device has no
  /// usable Korean voice; [SystemSpeechOutcome.failed] covers engine errors.
  Future<SystemSpeechOutcome> speakKorean(String text);

  /// Cancels any in-flight utterance. Safe to call when nothing is speaking.
  Future<void> stop();

  /// Stops speech and releases handlers. Called from the owner's dispose().
  void dispose();

  /// Notifies the owner that the utterance finished naturally, was cancelled
  /// by [stop], or failed. Used to return the UI to the idle state — never
  /// to claim playback succeeded.
  void setOnUtteranceFinished(void Function() onFinished);
}

enum SystemSpeechOutcome { started, unavailable, failed }
