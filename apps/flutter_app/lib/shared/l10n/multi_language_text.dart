// 다국어(ko/en 혼합) 문자열에서 한쪽 언어 텍스트를 추출하는 공용 헬퍼 (C3 추출).
// main.dart 의 _singleLanguageText 및 관련 유틸들이 여기로 정식화되었다.
// 의존: isLalaEnglish (shared/l10n/lala_copy.dart).
import 'lala_copy.dart';

bool containsKorean(String value) => RegExp(r'[가-힣]').hasMatch(value);

bool looksEnglishText(String value) => RegExp(r'[A-Za-z]{3,}').hasMatch(value);

bool hasMixedKoreanEnglish(String value) {
  return containsKorean(value) && looksEnglishText(value);
}

String? singleLanguageText(String? value, String language) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  if (isLalaEnglish(language)) {
    if (containsKorean(trimmed)) {
      return extractEnglishText(trimmed);
    }
    return trimmed;
  }
  if (!containsKorean(trimmed) && looksEnglishText(trimmed)) {
    return null;
  }
  if (hasMixedKoreanEnglish(trimmed)) {
    return extractKoreanText(trimmed);
  }
  return trimmed;
}

String? extractEnglishText(String value) {
  final withoutKorean = value.replaceAll(RegExp(r'[가-힣]+'), ' ');
  final cleaned = cleanLocalizedFragment(withoutKorean);
  return looksEnglishText(cleaned) ? cleaned : null;
}

String? extractKoreanText(String value) {
  final withoutEnglish = value.replaceAll(
    RegExp(r"[A-Za-z][A-Za-z0-9&'.,()/-]*(?:\s+[A-Za-z][A-Za-z0-9&'.,()/-]*)*"),
    ' ',
  );
  final cleaned = cleanLocalizedFragment(withoutEnglish);
  return containsKorean(cleaned) ? cleaned : null;
}

String cleanLocalizedFragment(String value) {
  return value
      .replaceAll(RegExp(r'[\[\]{}()|/·]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[,.:;~-]+|[,.:;~-]+$'), '')
      .trim();
}
