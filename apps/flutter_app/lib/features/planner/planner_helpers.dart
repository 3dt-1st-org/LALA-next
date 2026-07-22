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

/// 시간대 라벨(C3 추출 — main.dart 의 _periodLabel).
String periodLabel(String period, {String language = 'ko'}) {
  if (isLalaEnglish(language)) {
    return switch (period) {
      'morning' => 'Morning',
      'afternoon' => 'Afternoon',
      'evening' => 'Evening',
      _ => period.isEmpty
          ? '-'
          : period.length <= 3
          ? period
          : period.substring(0, 3),
    };
  }
  return switch (period) {
    'morning' => '오전',
    'afternoon' => '오후',
    'evening' => '저녁',
    _ => period.isEmpty
        ? '-'
        : period.length <= 2
        ? period
        : period.substring(0, 2),
  };
}

/// 시간대 아이콘(C3 추출 — main.dart 의 _periodIcon).
IconData periodIcon(String period) {
  return switch (period) {
    'morning' || '오전' => Icons.wb_twilight_outlined,
    'lunch' || '점심' => Icons.restaurant_outlined,
    'afternoon' || '오후' => Icons.wb_sunny_outlined,
    'evening' || '저녁' || 'night' => Icons.nights_stay_outlined,
    _ => Icons.place_outlined,
  };
}
