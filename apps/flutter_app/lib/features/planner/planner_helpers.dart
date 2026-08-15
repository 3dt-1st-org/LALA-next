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
    return lalaCopyMulti(
  language,
  ko: '일정 준비 중',
  en: 'Preparing stop',
  ja: '経由地を準備中',
  zhHans: '正在准备站点',
  zhHant: '正在準備站點',
);
  }
  final localizedTitle = singleLanguageText(title, language);
  if (localizedTitle != null && localizedTitle.isNotEmpty) {
    return localizedTitle;
  }
  // V6: KO 전용 제목은 ko 화면에서만 그대로 쓴다. 방문객/EN 화면은 EN 조합으로.
  if (normalizeLalaLanguage(language) != 'ko' && containsKorean(title)) {
    final placeName = place == null
        ? lalaCopyMulti(
  language,
  ko: '이 장소',
  en: 'this place',
  ja: 'このスポット',
  zhHans: '此地',
  zhHant: '此地',
)
        : placeDisplayName(place, language);
    return '${periodLabel(slot.period, language: language)} at $placeName';
  }
  if (normalizeLalaLanguage(language) == 'ko' &&
      looksEnglishText(title) &&
      !containsKorean(title)) {
    final placeName = place == null
        ? lalaCopyMulti(
  language,
  ko: '이 장소',
  en: 'this place',
  ja: 'このスポット',
  zhHans: '此地',
  zhHant: '此地',
)
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
      title != lalaCopyMulti(
  language,
  ko: '일정 준비 중',
  en: 'Preparing stop',
  ja: '経由地を準備中',
  zhHans: '正在准备站点',
  zhHant: '正在準備站點',
);
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
  return lalaCopyMulti(
      language,
      ko: '도보 $minutes분',
      en: '$minutes min walk',
      ja: '徒歩 $minutes分',
      zhHans: '步行 $minutes 分钟',
      zhHant: '步行 $minutes 分鐘',
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
  return lalaCopyMulti(
      language,
      ko: '영업 $hours (추정)',
      en: 'Open $hours (est.)',
      ja: '営業 $hours（推定）',
      zhHans: '营业 $hours（估计）',
      zhHant: '營業 $hours（估計）',
    );
}

/// D4: 슬롯 운영 상태(open/closed/unknown) KO/EN 라벨.
/// §V3-C: closure_state 는 카테고리 기반 추정 운영시간의 투영이며 authority 가
/// 아니므로 "영업중/Open"은 추정 상태 표시이지 보증이 아니다("확정/Confirmed" 금지).
/// null 은 honest-empty 로 "unknown" 취급한다.
String planSlotClosureStateLabel(LalaPlanSlot slot, String language) {
  final state = (slot.closureState ?? 'unknown').trim().toLowerCase();
  return switch (state) {
    'open' => lalaCopyMulti(
  language,
  ko: '영업중',
  en: 'Open',
  ja: '営業中',
  zhHans: '营业中',
  zhHant: '營業中',
),
    'closed' => lalaCopyMulti(
  language,
  ko: '영업종료',
  en: 'Closed',
  ja: '営業終了',
  zhHans: '已打烊',
  zhHant: '已打烊',
),
    _ => lalaCopyMulti(
  language,
  ko: '미확인',
  en: 'Unknown',
  ja: '未確認',
  zhHans: '未确认',
  zhHant: '未確認',
),
  };
}

/// D2: 슬롯 예보 창(forecast_window) 표시 라벨.
/// §V3-C: time/temp 는 plan-level forecast 에서 nearest-time 매칭한 이미 포맷된
/// 문자열이므로 언어 중립 데이터로 "time · temp" 형태로 합쳐 표시한다.
/// null(예보 미확보)이면 표시하지 않는다(placeholder/spinner 없음).
String? planSlotForecastWindowLabel(LalaPlanSlot slot, String language) {
  final fw = slot.forecastWindow;
  if (fw == null) return null;
  final time = fw.time.trim();
  final temp = fw.temp.trim();
  if (time.isEmpty && temp.isEmpty) return null;
  if (time.isEmpty) return temp;
  if (temp.isEmpty) return time;
  return '$time · $temp';
}

/// D3: 외부 대기질 나쁨 마커 라벨.
/// §V3-C: plan-level 먼지 등급이 outdoor_status 를 나쁘게 뒤집은 경우에만 야외 슬롯에
/// 투영한다. airQualityBad == true 이고 실내(indoor)가 아닐 때만 라벨 반환.
/// null(먼지 미확보)은 결코 "나쁨"으로 조작하지 않는다(honest-empty).
String? planSlotAirQualityBadLabel(LalaPlanSlot slot, String language) {
  if (slot.airQualityBad != true) return null;
  if (slot.indoorOutdoor == 'indoor') return null;
  return lalaCopyMulti(
      language,
      ko: '외부 대기질 나쁨',
      en: 'Outdoor air quality poor',
      ja: '屋外の大気質が悪い',
      zhHans: '室外空气质量差',
      zhHant: '室外空氣品質差',
    );
}

/// 시간대 라벨(C3 추출 — main.dart 의 _periodLabel).
String periodLabel(String period, {String language = 'ko'}) {
  final normalized = period.trim().toLowerCase();
  // V6: ko 이외 로케일은 EN 라벨 체인을 따른다(서버 슬롯 시간대는 EN 토큰).
  if (normalizeLalaLanguage(language) != 'ko') {
    return switch (normalized) {
      'morning' || 'am' || 'mo' || '오전' || '아침' => lalaCopyMulti(
        language,
        ko: '아침',
        en: 'Morning',
        ja: '朝',
        zhHans: '早晨',
        zhHant: '早晨',
      ),
      'lunch' || 'noon' || 'midday' || 'lu' || '점심' => lalaCopyMulti(
        language,
        ko: '점심',
        en: 'Lunch',
        ja: '昼',
        zhHans: '午餐',
        zhHant: '午餐',
      ),
      'afternoon' || 'pm' || 'af' || '오후' => lalaCopyMulti(
        language,
        ko: '오후',
        en: 'Afternoon',
        ja: '午後',
        zhHans: '下午',
        zhHant: '下午',
      ),
      'dinner' || 'evening' || 'night' || 'di' || '저녁' || '밤' => lalaCopyMulti(
        language,
        ko: '저녁',
        en: 'Dinner',
        ja: '夜',
        zhHans: '晚餐',
        zhHant: '晚餐',
      ),
      _ => normalized.isEmpty ? '-' : lalaCopyMulti(
        language,
        ko: '시간대',
        en: 'Period',
        ja: '時間帯',
        zhHans: '时段',
        zhHant: '時段',
      ),
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
