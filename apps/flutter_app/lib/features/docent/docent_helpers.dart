import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../shared/l10n/lala_copy.dart';
import '../../shared/l10n/multi_language_text.dart';
import '../../shared/l10n/place_labels.dart';

/// 도슨트 스크립트 본문(C3 추출 — main.dart 의 _docentBody).
String docentBody({
  required LalaPlace? place,
  required String? script,
  required String language,
}) {
  final localized = usableDocentScript(script, language);
  if (localized != null) {
    return localized;
  }
  return unavailableDocentBody(place: place, language: language);
}

/// 표시 가능한 도슨트 스크립트 여부(C3 추출 — main.dart 의 _hasUsableDocentScript).
bool hasUsableDocentScript(String? script, String language) {
  return usableDocentScript(script, language) != null;
}

/// 단일어 도슨트 스크립트 추출(C3 추출 — main.dart 의 _usableDocentScript).
/// null/빈/placeholder 이면 null.
String? usableDocentScript(String? script, String language) {
  final trimmed = script?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  if (isPlaceholderDocentScript(trimmed)) {
    return null;
  }
  return singleLanguageText(trimmed, language);
}

/// 마이그레이션 skeleton/placeholder 스크립트 판별(C3 추출 — main.dart 의 _isPlaceholderDocentScript).
bool isPlaceholderDocentScript(String value) {
  final lower = value.toLowerCase().trim();
  return lower.contains('migration skeleton') ||
      lower.contains('azure openai') ||
      RegExp(r'^this is a .+ docent script\.?$').hasMatch(lower);
}

/// 도슨트 미구비 상태 안내 문구(C3 추출 — main.dart 의 _unavailableDocentBody).
String unavailableDocentBody({
  required LalaPlace? place,
  required String language,
}) {
  if (isLalaEnglish(language)) {
    return place == null
        ? 'Select a place to load a docent script.'
        : 'Loading the docent script. Please check again shortly.';
  }
  return place == null
      ? '추천 장소가 선택되면 도슨트 스크립트를 불러옵니다.'
      : '도슨트 스크립트를 불러오는 중입니다. 잠시 뒤 다시 확인해 주세요.';
}

/// 도슨트 한 줄 요약(C3 추출 — main.dart 의 _docentSummary).
String docentSummary({
  required LalaPlace? place,
  required String language,
  required String? script,
  required String? action,
}) {
  final body = docentBody(
    place: place,
    script: script,
    language: language,
  ).trim();
  if (body.isNotEmpty) {
    return compactDocentSummary(body);
  }

  final trimmedAction = action?.trim();
  if (trimmedAction != null && trimmedAction.isNotEmpty) {
    return docentActionLabel(
          place: place,
          action: trimmedAction,
          language: language,
        ) ??
        trimmedAction;
  }

  final placeName = place == null ? null : placeDisplayName(place, language);
  if (isLalaEnglish(language)) {
    return placeName == null
        ? 'Preparing local experiences around your current location.'
        : 'Preparing the cultural context and route around $placeName.';
  }
  return placeName == null
      ? '현재 위치 주변의 로컬 경험을 준비하고 있습니다.'
      : '$placeName 주변의 문화 맥락과 동선을 준비하고 있습니다.';
}

/// 도슨트 본문을 한 문장으로 압축(C3 추출 — main.dart 의 _compactDocentSummary).
String compactDocentSummary(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
  final sentence = RegExp(
    r'^(.{18,80}?[.!?。]|.{18,80}?다[. ]?)',
  ).firstMatch(normalized)?.group(1)?.trim();
  if (sentence != null && sentence.isNotEmpty) {
    return sentence;
  }
  return normalized.length > 56
      ? '${normalized.substring(0, 56)}...'
      : normalized;
}

/// 도슨트 동선 액션 라벨(C3 추출 — main.dart 의 _docentActionLabel).
String? docentActionLabel({
  required LalaPlace? place,
  required String? action,
  String language = 'ko',
}) {
  final trimmed = action?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final placeName = place == null
      ? lalaCopy(language, ko: '이 장소', en: 'this place')
      : placeDisplayName(place, language);
  final localizedAction = singleLanguageText(trimmed, language);
  if (localizedAction != null && localizedAction.isNotEmpty) {
    return localizedAction;
  }
  final looksEnglish = looksEnglishText(trimmed);
  if (looksEnglish) {
    if (isLalaEnglish(language)) {
      return trimmed;
    }
    return '$placeName 주변 골목과 지역 상권을 함께 걷는 코스로 이어집니다.';
  }
  if (isLalaEnglish(language)) {
    return place == null
        ? 'This route continues through nearby local streets and businesses.'
        : 'This route continues through local streets and businesses around $placeName.';
  }
  return trimmed;
}

/// 도슨트 음성 바이트 수 라벨(C3 추출 — main.dart 의 _audioBytesLabel).
String audioBytesLabel(int bytes, String language) {
  return isLalaEnglish(language) ? '$bytes bytes' : '$bytes바이트';
}
