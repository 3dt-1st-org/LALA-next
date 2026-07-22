import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../shared/l10n/lala_copy.dart';

/// 장소 카테고리 표시 라벨(C3 추출 — main.dart 의 _categoryLabel).
String categoryLabel(String category, {String language = 'ko'}) {
  if (isLalaEnglish(language)) {
    return switch (category) {
      'restaurant' => 'Food',
      'event' => 'Event',
      'culture_venue' => 'Culture',
      'attraction' => 'Attraction',
      _ => 'Local',
    };
  }
  return switch (category) {
    'restaurant' => '맛집',
    'event' => '행사',
    'culture_venue' => '문화',
    'attraction' => '명소',
    _ => '로컬',
  };
}

/// 카테고리 필터 라벨(C3 추출 — main.dart 의 _categoryFilterLabel).
String categoryFilterLabel(String category, String language) {
  if (language == 'en') {
    return switch (category) {
      'all' => 'All',
      'restaurant' => 'Restaurants',
      'event' => 'Events',
      'culture_venue' => 'Culture',
      'attraction' => 'Attractions',
      _ => 'Local',
    };
  }
  return switch (category) {
    'all' => '전체',
    _ => categoryLabel(category, language: language),
  };
}

/// 레일 카드용 카테고리 라벨(행사 상태 병합)(C3 추출 — main.dart 의 _railCategoryLabel).
String railCategoryLabel(LalaPlace place, String language) {
  final category = categoryLabel(place.category, language: language);
  if (place.category != 'event') {
    return category;
  }
  final status = place.isOngoing == false
      ? lalaCopy(language, ko: '종료', en: 'Ended')
      : lalaCopy(language, ko: '진행 중', en: 'Ongoing');
  return '$category · $status';
}

/// 카테고리 색상(C3 추출 — main.dart 의 최상위 _categoryColor).
Color categoryColor(String category) {
  return switch (category) {
    'attraction' => const Color(0xFFC53030),
    'restaurant' => const Color(0xFFF5C842),
    'event' => const Color(0xFF2B6CB0),
    'culture_venue' => const Color(0xFF0F766E),
    _ => const Color(0xFF1A202C),
  };
}

/// 장소 이미지 URI 정규화(C3 추출 — main.dart 의 _normalizedPlaceImageUri).
Uri? normalizedPlaceImageUri(String? rawUrl) {
  final imageUrl = rawUrl?.trim();
  if (imageUrl == null || imageUrl.isEmpty) {
    return null;
  }
  final parsedImageUrl = Uri.tryParse(imageUrl);
  if (parsedImageUrl == null ||
      !parsedImageUrl.hasScheme ||
      parsedImageUrl.host.isEmpty) {
    return null;
  }
  if (parsedImageUrl.scheme == 'http' &&
      parsedImageUrl.host == 'tong.visitkorea.or.kr') {
    return parsedImageUrl.replace(scheme: 'https');
  }
  return parsedImageUrl;
}

/// 공식 장소 이미지 보유 여부(C3 추출 — main.dart 의 _hasOfficialPlaceImage).
bool hasOfficialPlaceImage(LalaPlace place) {
  return normalizedPlaceImageUri(place.imageUrl) != null;
}
