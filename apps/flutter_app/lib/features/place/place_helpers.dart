import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../app/lala_visual_tokens.dart';
import '../../shared/l10n/lala_copy.dart';
import '../../shared/l10n/multi_language_text.dart';
import '../../shared/l10n/place_labels.dart';

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

/// 카테고리 색상(P6A §2.3 단일 SSOT — 칩·카드·마커가 동일 토큰 사용).
/// 기존 Color(0xFF...) 리터럴을 LalaVisualColors 토큰으로 일원화; 값은 동일.
Color categoryColor(String category) {
  return switch (category) {
    'attraction' => LalaVisualColors.attraction,
    'restaurant' => LalaVisualColors.restaurant,
    'event' => LalaVisualColors.event,
    'culture_venue' => LalaVisualColors.culture,
    _ => LalaVisualColors.ink,
  };
}

/// 카테고리 칩/배지/마커 위 텍스트 색(P6A §2.3 — restaurant 만 restaurantInk, 나머지 흰색).
Color categoryOnTextColor(String category) {
  return category == 'restaurant'
      ? LalaVisualColors.restaurantInk
      : const Color(0xFFFFFFFF);
}

/// 카테고리 색의 #RRGGBB 문자열(Kakao Web JS 마커 경로 SSOT — 토큰에서 파생, 중복 리터럴 금지).
String categoryColorHex(String category) =>
    _hexFromColor(categoryColor(category));

String categoryOnTextColorHex(String category) =>
    _hexFromColor(categoryOnTextColor(category));

String _hexFromColor(Color color) {
  String two(double channel) =>
      (channel * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${two(color.r)}${two(color.g)}${two(color.b)}'.toUpperCase();
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

/// 추천 reason 원문. null/빈이면 null(미출력). 모든 표면이 동일 텍스트를 그리도록
/// 게이트/원문의 SSOT 로 사용한다(위젯별 재계산/재문구 금지).
String? placeReasonText(LalaPlace place) {
  final reason = place.reason;
  if (reason == null || reason.isEmpty) {
    return null;
  }
  return reason;
}

/// 장소 데이터 신선도 원문. reason 과 동일한 SSOT 규칙(null/빈 → null).
String? placeFreshnessText(LalaPlace place) {
  final freshness = place.freshness;
  if (freshness == null || freshness.isEmpty) {
    return null;
  }
  return freshness;
}

/// 장소 카드/타일/시트 공용 시맨틱 라벨(§13.5). 장소명/카테고리/거리/지역/reason을
/// 하나의 라벨로 합쳐 모든 표면이 동일 문구를 전달한다(SSOT). freshness 는 검색
/// 타일 RC1 패턴을 따라 시각 전용이므로 라벨에서 제외.
String placeCardSemanticsLabel(LalaPlace place, String language) {
  final name = placeDisplayName(place, language);
  final region = placeRegionLabel(place, language);
  final distance = place.distanceM > 0 ? '${place.distanceM}m' : null;
  return [
    name,
    categoryFilterLabel(place.category, language),
    ?distance,
    if (region.isNotEmpty) region,
    if (placeReasonText(place) case final String reason) reason,
  ].join(', ');
}
