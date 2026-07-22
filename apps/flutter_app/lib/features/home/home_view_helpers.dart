// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
// 홈/대시보드 화면에서 공유하는 순수 헬퍼(fallbacker 들은 shared/* 의 본래 함수로 직접 호출).
import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/place/widgets/context_fact.dart';
import 'package:lala_next_app/features/weather/weather_helpers.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';
import 'package:lala_next_app/shared/l10n/multi_language_text.dart';
import 'package:lala_next_app/shared/l10n/place_labels.dart';
import 'package:lala_next_app/shared/labels/basis_label.dart';
import 'package:lala_next_app/shared/labels/dust_label.dart';
import 'package:lala_next_app/shared/labels/source_label.dart';

bool hasFallbackProofSource({
  required LalaPlace place,
  required String? source,
  required LalaWeather? weather,
  required LalaPlaceScore? score,
}) {
  final features = score?.features ?? const <String, dynamic>{};
  final inputSources = stringList(features['input_sources']);
  return isFallbackSourceCode(source) ||
      isFallbackSourceCode(place.source) ||
      isFallbackSourceCode(place.upstreamSource) ||
      isFallbackSourceCode(weather?.source) ||
      isFallbackSourceCode(score?.dataBasis) ||
      isFallbackSourceCode(features['primary_source']?.toString()) ||
      inputSources.any(isFallbackSourceCode);
}

List<String> proofSourceLabels({
  required LalaPlace place,
  required String language,
  required String? source,
  required LalaWeather? weather,
  required LalaPlaceScore? score,
}) {
  final labels = <String>[];
  void add(String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '-') {
      return;
    }
    if (!labels.contains(trimmed)) {
      labels.add(trimmed);
    }
  }

  final features = score?.features ?? const <String, dynamic>{};
  add(sourceLabel(source, language: language));
  add(
    externalSourceLabel(
      place.upstreamSource ?? features['primary_source'],
      language: language,
    ),
  );
  if (score != null) {
    add(basisLabel(score.dataBasis, language: language));
  }

  final inputSources = stringList(features['input_sources']);
  if (inputSources.any((source) => source.startsWith('economy.'))) {
    add(lalaCopy(language, ko: '카드 소비', en: 'Card spending'));
  }
  if (inputSources.contains('culture.events') ||
      asFeatureInt(features['culture_event_count']) > 0) {
    add(lalaCopy(language, ko: '문화행사 데이터', en: 'Culture events'));
  }
  if (inputSources.contains('travel.weather_observations') ||
      score?.components.weatherFitScore != null ||
      weather != null) {
    add(
      weather == null
          ? lalaCopy(language, ko: '날씨 관측', en: 'Weather observations')
          : lalaCopy(
              language,
              ko: '날씨 ${dustSituationLabel(weather.dust, language)}',
              en: 'Weather ${dustSituationLabel(weather.dust, language, includePrefix: false)}',
            ),
    );
  }
  if (inputSources.contains('travel.places')) {
    add(lalaCopy(language, ko: '공식 장소 DB', en: 'Official place DB'));
  }
  if (stringList(features['dynamic_source_types']).isNotEmpty ||
      stringList(features['rag_source_types']).isNotEmpty) {
    add(lalaCopy(language, ko: '검색 컨텍스트', en: 'RAG context'));
  }
  return labels.take(8).toList(growable: false);
}

String recommendationStatusMessage(
  String language, {
  required bool recoveryPending,
}) {
  if (recoveryPending) {
    return lalaCopy(
      language,
      ko: '추천 연결이 잠시 지연되고 있어요. 자동으로 다시 불러오는 중입니다.',
      en: 'Recommendations are taking longer than expected. Retrying automatically.',
    );
  }
  return lalaCopy(
    language,
    ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not load recommendations. Please try again shortly.',
  );
}

String? localizedUiMessage(String? value, String language) {
  final localized = singleLanguageText(value, language);
  if (localized != null && localized.isNotEmpty) {
    return localized;
  }
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return lalaCopy(
    language,
    ko: '지금 정보를 불러오지 못했어요.',
    en: 'Could not load the information right now.',
  );
}

String safeUiErrorMessage(String? value, {String? fallbackMessage}) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return fallbackMessage ?? requestFailureMessage();
  }
  if (containsKorean(trimmed)) {
    return trimmed;
  }
  return fallbackMessage ?? requestFailureMessage();
}

String recommendationLoadFailureMessage(String language) {
  return lalaCopy(
    language,
    ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not load recommendations. Please try again shortly.',
  );
}

String docentAudioFailureMessage() {
  return '도슨트 음성을 준비하지 못했어요. 스크립트는 계속 볼 수 있습니다. Could not prepare docent audio. The script is still available.';
}

String tourAudioFailureMessage() {
  return '투어 음성을 준비하지 못했어요. 추천 코스는 계속 볼 수 있습니다. Could not prepare tour audio. The route is still available.';
}

String requestFailureMessage() {
  return '지금 정보를 불러오지 못했어요.';
}

String interventionToastLabel(LalaIntervention intervention, String language) {
  final place = intervention.place == null
      ? null
      : placeDisplayName(intervention.place!, language);
  final reason = intervention.reason.trim();
  final action = intervention.recommendedAction.trim();
  final localizedReason = singleLanguageText(reason, language);
  final localizedAction = singleLanguageText(action, language);

  if (isLalaEnglish(language)) {
    if (localizedReason != null && localizedAction != null) {
      return '$localizedReason · $localizedAction';
    }
    if (localizedReason != null) {
      return localizedReason;
    }
    if (localizedAction != null) {
      return localizedAction;
    }
    if (place != null) {
      return 'Weather changed. Adjust the route near $place.';
    }
    return 'Weather changed. Review today\'s route.';
  }

  if (localizedReason != null) {
    return localizedReason;
  }
  if (localizedAction != null) {
    return localizedAction;
  }
  if (place != null) {
    return '날씨가 바뀌었어요. $place 중심으로 동선을 다시 확인해보세요.';
  }
  return '날씨가 바뀌었어요. 하루 일정을 다시 확인해보세요.';
}

List<LalaPlace> filterPlaces(List<LalaPlace> places, String category) {
  if (category == 'all') {
    return places;
  }
  return places.where((place) => place.category == category).toList();
}

List<LalaPlace> prioritizeClusterMembers(
  List<LalaPlace> places,
  List<String> focusedClusterMemberIds,
) {
  if (places.isEmpty || focusedClusterMemberIds.isEmpty) {
    return places;
  }
  final memberOrder = <String, int>{
    for (final entry in focusedClusterMemberIds.indexed) entry.$2: entry.$1,
  };
  final clusterPlaces =
      places
          .where((place) => memberOrder.containsKey(place.placeId))
          .toList(growable: false)
        ..sort(
          (a, b) => memberOrder[a.placeId]!.compareTo(memberOrder[b.placeId]!),
        );
  if (clusterPlaces.isEmpty) {
    return places;
  }
  final clusterPlaceIds = clusterPlaces.map((place) => place.placeId).toSet();
  return [
    ...clusterPlaces,
    ...places.where((place) => !clusterPlaceIds.contains(place.placeId)),
  ];
}

List<LalaPlace> restaurantTourPlaces(List<LalaPlace> places) {
  final restaurants = places
      .where((place) => place.category == 'restaurant')
      .toList(growable: false);
  if (restaurants.isEmpty) {
    return const <LalaPlace>[];
  }
  final sorted = [...restaurants]
    ..sort((a, b) {
      final scoreCompare = (b.score?.components.localSpendingScore ?? 0)
          .compareTo(a.score?.components.localSpendingScore ?? 0);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.distanceM.compareTo(b.distanceM);
    });
  return sorted.take(6).toList(growable: false);
}

LalaPlace? placeById(List<LalaPlace> places, String? placeId) {
  if (placeId == null) {
    return null;
  }
  for (final place in places) {
    if (place.placeId == placeId) {
      return place;
    }
  }
  return null;
}

String placeContextTitle(String category, String language) {
  return switch (category) {
    'event' => lalaCopy(language, ko: '행사 맥락', en: 'Event context'),
    'restaurant' => lalaCopy(language, ko: '맛집 로컬 맥락', en: 'Food local context'),
    'culture_venue' => lalaCopy(language, ko: '문화 연계 맥락', en: 'Culture context'),
    _ => lalaCopy(language, ko: '로컬 맥락', en: 'Local context'),
  };
}

IconData placeContextIcon(String category) {
  return switch (category) {
    'event' => Icons.event_available_outlined,
    'restaurant' => Icons.restaurant_menu,
    'culture_venue' => Icons.account_balance_outlined,
    _ => Icons.travel_explore_outlined,
  };
}

List<ContextFact> placeContextFacts({
  required LalaPlace place,
  required String language,
  required LalaWeather? weather,
  required bool includeEvidence,
}) {
  final score = place.score;
  final features = score?.features ?? const <String, dynamic>{};
  final facts = <ContextFact>[];

  void add(IconData icon, String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '-') {
      return;
    }
    if (facts.any((fact) => fact.label == trimmed)) {
      return;
    }
    facts.add(ContextFact(icon: icon, label: trimmed));
  }

  add(Icons.place_outlined, placeRegionLabel(place, language));

  final placeEventCount = asFeatureInt(features['place_event_count']);
  final cultureEventCount = asFeatureInt(features['culture_event_count']);
  if (placeEventCount > 0) {
    add(
      Icons.event_note_outlined,
      lalaCopy(
        language,
        ko: '장소 연계 행사 ${commaInt(placeEventCount)}건',
        en: '${commaInt(placeEventCount)} linked events',
      ),
    );
  } else if (cultureEventCount > 0) {
    add(
      Icons.festival_outlined,
      lalaCopy(
        language,
        ko: '지역 문화행사 ${commaInt(cultureEventCount)}건',
        en: '${commaInt(cultureEventCount)} nearby culture events',
      ),
    );
  }

  final spendAmount = asFeatureDouble(features['region_spend_amount']);
  if (includeEvidence && spendAmount > 0) {
    add(
      Icons.payments_outlined,
      lalaCopy(
        language,
        ko: '카드 소비 ${formatWonCompact(spendAmount, language)}',
        en: 'Card spend ${formatWonCompact(spendAmount, language)}',
      ),
    );
  }

  final transactionCount = asFeatureInt(features['region_transaction_count']);
  if (includeEvidence && transactionCount > 0) {
    add(
      Icons.receipt_long_outlined,
      lalaCopy(
        language,
        ko: '거래 ${commaInt(transactionCount)}건',
        en: '${commaInt(transactionCount)} transactions',
      ),
    );
  }

  if (weather != null) {
    add(
      Icons.wb_cloudy_outlined,
      '${outdoorLabel(weather.outdoorStatus, language: language)} · ${temperatureLabel(weather.temp)}',
    );
  }

  if (includeEvidence) {
    add(
      Icons.verified_outlined,
      externalSourceLabel(
            place.upstreamSource ?? features['primary_source'],
            language: language,
          ) ??
          sourceLabel(place.source, language: language),
    );
  }

  return facts.take(5).toList(growable: false);
}

bool isLiveSpeechEnabled(LalaReadiness? readiness) {
  return readiness?.mode.speech == 'live-azure' ||
      readiness?.checks['live_speech'] == 'enabled';
}

String? externalSourceLabel(Object? value, {String language = 'ko'}) {
  final normalized = (value?.toString() ?? '').trim();
  if (isFallbackSourceCode(normalized)) {
    return sourceLabel(normalized, language: language);
  }
  if (isLalaEnglish(language)) {
    return switch (normalized) {
      'tour_api' => 'Korea Tourism data',
      'kcisa' => 'Culture information data',
      'kopis' => 'Performing arts data',
      'dev_seed' => 'LALA curation',
      'local_fixture' => 'LALA local data',
      'canonical' => 'Official places',
      '' => null,
      final source => source,
    };
  }
  return switch (normalized) {
    'tour_api' => '한국관광공사',
    'kcisa' => '문화정보원',
    'kopis' => '공연예술통합전산망',
    'dev_seed' => '로컬 큐레이션',
    'local_fixture' => '로컬 데이터',
    'canonical' => '공식 장소',
    '' => null,
    final source => source,
  };
}

List<String> stringList(Object? value) {
  if (value is Iterable) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? const <String>[] : <String>[text];
}

int asFeatureInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double asFeatureDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String commaInt(num value) {
  final text = value.round().abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index += 1) {
    if (index > 0 && (text.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(text[index]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

String formatWonCompact(num value, String language) {
  if (isLalaEnglish(language)) {
    return 'KRW ${commaInt(value)}';
  }
  final rounded = value.round();
  if (rounded >= 10000) {
    return '${commaInt(rounded / 10000)}만원';
  }
  return '${commaInt(rounded)}원';
}
