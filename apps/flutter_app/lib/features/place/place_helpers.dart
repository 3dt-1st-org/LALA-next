import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../shared/l10n/lala_copy.dart';
import '../../shared/l10n/multi_language_text.dart';

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

/// 행사 정보 노출 대상 여부(C3 추출 — main.dart 의 _shouldShowEventInfo).
bool shouldShowEventInfo(LalaPlace place) {
  return place.category == 'event' ||
      place.eventStartDate?.trim().isNotEmpty == true ||
      place.eventEndDate?.trim().isNotEmpty == true ||
      place.eventUrl?.trim().isNotEmpty == true ||
      place.isOngoing != null ||
      place.isApproximateLocation == true;
}

/// 행사 URL 검증(C3 추출 — main.dart 의 _validEventUri). http/https 만 허용.
Uri? validEventUri(String? rawUrl) {
  final trimmed = rawUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    return null;
  }
  return uri;
}

/// 행사 날짜 표시 포맷(C3 추출 — main.dart 의 _formatEventDate).
String? formatEventDate(String? rawDate, String language) {
  final trimmed = rawDate?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
  if (match == null) {
    return singleLanguageText(trimmed, language) ?? trimmed;
  }
  final year = match.group(1)!;
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (isLalaEnglish(language)) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[month - 1]} $day, $year';
  }
  return '$year년 ${month.toString().padLeft(2, '0')}월 ${day.toString().padLeft(2, '0')}일';
}

/// 행사 날짜 구간 텍스트(C3 추출 — main.dart 의 _eventDateRangeText).
String? eventDateRangeText(LalaPlace place, String language) {
  final start = formatEventDate(place.eventStartDate, language);
  final end = formatEventDate(place.eventEndDate, language);
  if (start == null && end == null) {
    return null;
  }
  if (start != null && end != null) {
    return '$start ~ $end';
  }
  if (start != null) {
    return lalaCopy(language, ko: '$start부터', en: 'From $start');
  }
  return lalaCopy(language, ko: '~$end까지', en: 'Until $end');
}
