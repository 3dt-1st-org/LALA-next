import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../shared/l10n/lala_copy.dart';
import '../../shared/l10n/multi_language_text.dart';
import '../../shared/l10n/place_labels.dart';

/// 일정 슬롯 제목(C3 추출 — main.dart 의 _planSlotTitle).
/// 빈 제목/다국어 혼용 시 period + 장소명으로 대체 표현을 만든다.
String planSlotTitle(LalaPlanSlot slot, String language) {
  final title = slot.title.trim();
  final place = slot.place;
  if (title.isEmpty) {
    return lalaCopy(language, ko: '일정 준비 중', en: 'Preparing stop');
  }
  final localizedTitle = singleLanguageText(title, language);
  if (localizedTitle != null && localizedTitle.isNotEmpty) {
    return localizedTitle;
  }
  if (isLalaEnglish(language) && containsKorean(title)) {
    final placeName = place == null
        ? lalaCopy(language, ko: '이 장소', en: 'this place')
        : placeDisplayName(place, language);
    return '${periodLabel(slot.period, language: language)} at $placeName';
  }
  if (!isLalaEnglish(language) &&
      looksEnglishText(title) &&
      !containsKorean(title)) {
    final placeName = place == null
        ? lalaCopy(language, ko: '이 장소', en: 'this place')
        : placeDisplayName(place, language);
    return '${periodLabel(slot.period, language: language)} $placeName';
  }
  return title;
}

/// 표시 가능한 일정 슬롯인지 여부(C3 추출 — main.dart 의 _hasVisiblePlanSlot).
bool hasVisiblePlanSlot(LalaPlanSlot slot, String language) {
  if (slot.place != null) {
    return true;
  }
  final title = planSlotTitle(slot, language).trim();
  if (title.isEmpty) {
    return false;
  }
  final lowerTitle = title.toLowerCase();
  return !title.contains('이 장소') &&
      !lowerTitle.contains('this place') &&
      title != lalaCopy(language, ko: '일정 준비 중', en: 'Preparing stop');
}

/// 일정 슬롯 부가 설명(C3 추출 — main.dart 의 _planSlotDetail).
/// 제목이 장소명/period+장소명과 같으면 중복으로 간주해 null 반환.
String? planSlotDetail(LalaPlanSlot slot, String language) {
  final place = slot.place;
  if (place == null) {
    return null;
  }
  final detail = planSlotTitle(slot, language).trim();
  if (detail.isEmpty) {
    return null;
  }
  final placeName = placeDisplayName(place, language).trim();
  final period = periodLabel(slot.period, language: language).trim();
  final normalizedDetail = detail.replaceAll(RegExp(r'\s+'), ' ');
  final normalizedPlace = placeName.replaceAll(RegExp(r'\s+'), ' ');
  final periodPlace = '$period $normalizedPlace'.trim();
  if (normalizedDetail == normalizedPlace || normalizedDetail == periodPlace) {
    return null;
  }
  if (period.isNotEmpty && normalizedDetail.startsWith('$period ')) {
    final afterPeriod = normalizedDetail.substring(period.length).trim();
    if (afterPeriod == normalizedPlace ||
        afterPeriod.startsWith(normalizedPlace)) {
      return null;
    }
  }
  return detail;
}

/// 이전 슬롯으로부터의 도보 이동 시간(분) 라인.
/// §12.3: travel_time_from_previous_minutes 는 null(첫 슬롯/장소 없음)이면 표시하지
/// 않는다. Haversine 기반 추정값이므로 별도의 "추정" 마커 없이 도보 N분 / N min walk.
String? planSlotTravelTimeLabel(LalaPlanSlot slot, String language) {
  final minutes = slot.travelTimeFromPreviousMinutes;
  if (minutes == null || minutes < 0) {
    return null;
  }
  return lalaCopy(
    language,
    ko: '도보 $minutes분',
    en: '$minutes min walk',
  );
}

/// 카테고리 기반 추정 운영시간 라인.
/// §12.3: estimated_opening_hours 는 authority 가 아닌 추정값이므로 항상 (추정)/(est.)
/// 마커를 붙인다. null(장소 없음)이면 표시하지 않는다. opening_hours_valid 는 authority
/// 부재 시 null 이므로 authoritative 하게 표시하지 않는다.
String? planSlotEstimatedHoursLabel(LalaPlanSlot slot, String language) {
  final hours = slot.estimatedOpeningHours;
  if (hours == null || hours.trim().isEmpty) {
    return null;
  }
  return lalaCopy(
    language,
    ko: '영업 $hours (추정)',
    en: 'Open $hours (est.)',
  );
}

/// 시간대 라벨(C3 추출 — main.dart 의 _periodLabel).
String periodLabel(String period, {String language = 'ko'}) {
  final normalized = period.trim().toLowerCase();
  if (isLalaEnglish(language)) {
    return switch (normalized) {
      'morning' || 'am' || 'mo' || '오전' || '아침' => 'Morning',
      'lunch' || 'noon' || 'midday' || 'lu' || '점심' => 'Lunch',
      'afternoon' || 'pm' || 'af' || '오후' => 'Afternoon',
      'dinner' || 'evening' || 'night' || 'di' || '저녁' || '밤' => 'Dinner',
      _ => normalized.isEmpty ? '-' : 'Period',
    };
  }
  return switch (normalized) {
    'morning' || 'am' || 'mo' || '오전' || '아침' => '아침',
    'lunch' || 'noon' || 'midday' || 'lu' || '점심' => '점심',
    'afternoon' || 'pm' || 'af' || '오후' => '오후',
    'dinner' || 'evening' || 'night' || 'di' || '저녁' || '밤' => '저녁',
    _ => normalized.isEmpty ? '-' : '시간대',
  };
}

/// 시간대 아이콘(C3 추출 — main.dart 의 _periodIcon).
IconData periodIcon(String period) {
  return switch (period.trim().toLowerCase()) {
    'morning' || 'am' || 'mo' || '오전' || '아침' => Icons.wb_twilight_outlined,
    'lunch' ||
    'noon' ||
    'midday' ||
    'lu' ||
    '점심' => Icons.lunch_dining_outlined,
    'afternoon' || 'pm' || 'af' || '오후' => Icons.wb_sunny_outlined,
    'dinner' ||
    'evening' ||
    'night' ||
    'di' ||
    '저녁' ||
    '밤' => Icons.dinner_dining_outlined,
    _ => Icons.place_outlined,
  };
}
