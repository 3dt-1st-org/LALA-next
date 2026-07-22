// 장소/지역/위치/야외 상태 표시 라벨 공용 헬퍼 (C3 추출).
// main.dart 의 _locationLabel / _placeDisplayName / _placeRegionLabel / _outdoorLabel 이
// 여기로 정식화되었다. 의존: lalaCopy, isLalaEnglish, singleLanguageText, containsKorean.
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'lala_copy.dart';
import 'multi_language_text.dart';

String locationLabel(String? value, String language) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return lalaCopy(language, ko: '수원', en: 'Suwon');
  }
  final normalized = trimmed.toLowerCase();
  final localized = singleLanguageText(trimmed, language);
  if (isLalaEnglish(language)) {
    if (localized == null || localized.isEmpty) {
      return switch (trimmed) {
        '수원' || '수원시' => 'Suwon',
        _ => 'Nearby area',
      };
    }
    return switch (localized) {
      '수원' || '수원시' => 'Suwon',
      final location => location,
    };
  }
  if (localized == null || localized.isEmpty) {
    return switch (normalized) {
      'suwon' || 'suwon-si' || 'suwon city' => '수원',
      _ => '주변 지역',
    };
  }
  return switch (normalized) {
    'suwon' || 'suwon-si' || 'suwon city' => '수원',
    _ => localized,
  };
}

String placeDisplayName(LalaPlace place, String language) {
  if (isLalaEnglish(language)) {
    final nameEn = singleLanguageText(place.nameEn, language);
    if (nameEn != null) {
      return nameEn;
    }
    final primaryName = singleLanguageText(place.name, language);
    if (primaryName != null) {
      return primaryName;
    }
    return 'Local place';
  }
  final nameKo = singleLanguageText(place.nameKo, language);
  if (nameKo != null) {
    return nameKo;
  }
  final primaryName = singleLanguageText(place.name, language);
  if (primaryName != null) {
    return primaryName;
  }
  return '이 장소';
}

String placeRegionLabel(LalaPlace place, String language) {
  if (isLalaEnglish(language)) {
    final regionEn = singleLanguageText(place.regionEn, language);
    if (regionEn != null) {
      return regionEn;
    }
    final regionKo = singleLanguageText(place.regionKo, 'ko');
    if (regionKo != null) {
      final localizedRegion = locationLabel(regionKo, language);
      if (!containsKorean(localizedRegion)) {
        return localizedRegion;
      }
    }
    final address = singleLanguageText(place.address, language);
    if (address != null) {
      return address;
    }
    return 'Nearby area';
  }
  final regionKo = singleLanguageText(place.regionKo, language);
  if (regionKo != null) {
    return regionKo;
  }
  final address = singleLanguageText(place.address, language);
  if (address != null) {
    return address;
  }
  return '주변 지역';
}

String outdoorLabel(String status, {String language = 'ko'}) {
  if (isLalaEnglish(language)) {
    return switch (status) {
      'good' => 'Good',
      'normal' => 'Normal',
      'bad' => 'Caution',
      _ => status,
    };
  }
  return switch (status) {
    'good' => '좋음',
    'normal' => '보통',
    'bad' => '주의',
    _ => status,
  };
}
