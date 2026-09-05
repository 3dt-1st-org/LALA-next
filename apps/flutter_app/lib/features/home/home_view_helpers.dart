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
    add(
      lalaCopyMulti(
        language,
        ko: '카드 소비',
        en: 'Card spending',
        ja: 'カード消費',
        zhHans: '刷卡消费',
        zhHant: '刷卡消費',
      ),
    );
  }
  if (inputSources.contains('culture.events') ||
      asFeatureInt(features['culture_event_count']) > 0) {
    add(
      lalaCopyMulti(
        language,
        ko: '문화행사 데이터',
        en: 'Culture events',
        ja: '文化イベントデータ',
        zhHans: '文化活动数据',
        zhHant: '文化活動數據',
      ),
    );
  }
  if (inputSources.contains('travel.weather_observations') ||
      score?.components.weatherFitScore != null ||
      weather != null) {
    add(
      weather == null
          ? lalaCopyMulti(
              language,
              ko: '날씨 관측',
              en: 'Weather observations',
              ja: '気象観測',
              zhHans: '气象观测',
              zhHant: '氣象觀測',
            )
          : lalaCopyMulti(
              language,
              ko: '날씨 ${dustSituationLabel(weather.dust, language)}',
              en: 'Weather ${dustSituationLabel(weather.dust, language, includePrefix: false)}',
              ja: '気象 ${dustSituationLabel(weather.dust, language, includePrefix: false)}',
              zhHans: '天气 ${dustSituationLabel(weather.dust, language, includePrefix: false)}',
              zhHant: '天氣 ${dustSituationLabel(weather.dust, language, includePrefix: false)}',
            ),
    );
  }
  if (inputSources.contains('travel.places')) {
    add(
      lalaCopyMulti(
        language,
        ko: '공식 장소 DB',
        en: 'Official place DB',
        ja: '公式スポットDB',
        zhHans: '官方地点数据库',
        zhHant: '官方地點資料庫',
      ),
    );
  }
  if (stringList(features['dynamic_source_types']).isNotEmpty ||
      stringList(features['rag_source_types']).isNotEmpty) {
    add(
      lalaCopyMulti(
        language,
        ko: '검색 컨텍스트',
        en: 'RAG context',
        ja: '検索コンテキスト',
        zhHans: '检索上下文',
        zhHant: '檢索上下文',
      ),
    );
  }
  return labels.take(8).toList(growable: false);
}

String recommendationStatusMessage(
  String language, {
  required bool recoveryPending,
}) {
  if (recoveryPending) {
    return lalaCopyMulti(
      language,
      ko: '추천 연결이 잠시 지연되고 있어요. 자동으로 다시 불러오는 중입니다.',
      en: 'Recommendations are taking longer than expected. Retrying automatically.',
      ja: 'おすすめの取得に時間がかかっています。自動で再試行しています。',
      zhHans: '推荐加载稍有延迟，正在自动重试。',
      zhHant: '推薦載入稍有延遲，正在自動重試。',
    );
  }
  return lalaCopyMulti(
    language,
    ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not load recommendations. Please try again shortly.',
    ja: 'おすすめスポットを読み込めませんでした。しばらくしてからもう一度お試しください。',
    zhHans: '无法加载推荐地点，请稍后重试。',
    zhHant: '無法載入推薦地點，請稍後重試。',
  );
}

/// 지도/추천 로드 실패의 두 가지 honest 종류(playbook §2/§13.5).
/// unavailable = 서비스에 도달하지 못함(네트워크/타임아웃); error = 서비스가 오류로 응답.
/// 두 종류는 빈 상태(no-data) 카피와 절대 겹치지 않는다.
enum RecommendationFailureKind { unavailable, error }

/// 캡처된 예외를 도달 실패(unavailable) / 오류 응답(error)으로 분류한다.
/// LalaApiException 의 code/statusCode 가 없으면 서비스 도달과 무관하므로 error.
RecommendationFailureKind recommendationFailureKind(Object? failure) {
  if (failure is LalaApiException) {
    final code = failure.code;
    final networkUnreachable =
        code == 'NETWORK_ERROR' ||
        code == 'REQUEST_TIMEOUT' ||
        failure.statusCode == 0;
    return networkUnreachable
        ? RecommendationFailureKind.unavailable
        : RecommendationFailureKind.error;
  }
  return RecommendationFailureKind.error;
}

/// 실패 종류에 따른 distinct 안내문. 빈 상태(no-data) 카피와 구분된다.
String recommendationFailureMessage(
  String language,
  RecommendationFailureKind kind,
) {
  switch (kind) {
    case RecommendationFailureKind.unavailable:
      return lalaCopyMulti(
        language,
        ko: '일시적으로 서버에 연결할 수 없어요. 네트워크를 확인 후 다시 시도해 주세요.',
        en: 'Could not reach the service. Check your connection and try again.',
        ja: 'サーバーに一時的に接続できません。ネットワークを確認してもう一度お試しください。',
        zhHans: '暂时无法连接服务器，请检查网络后重试。',
        zhHant: '暫時無法連線伺服器，請檢查網路後重試。',
      );
    case RecommendationFailureKind.error:
      return lalaCopyMulti(
        language,
        ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
        en: 'Could not load recommendations. Please try again shortly.',
        ja: 'おすすめスポットを読み込めませんでした。しばらくしてからもう一度お試しください。',
        zhHans: '无法加载推荐地点，请稍后重试。',
        zhHant: '無法載入推薦地點，請稍後重試。',
      );
  }
}

/// 실패 종류에 따른 시맨틱/아이콘 라벨(화면 읽기 + 색상 단독 신호 회피용).
String recommendationFailureSemanticsLabel(
  String language,
  RecommendationFailureKind kind,
  String message,
) {
  return lalaCopyMulti(
    language,
    ko: kind == RecommendationFailureKind.unavailable
        ? '서버 연결 불가. $message'
        : '추천 불러오기 실패. $message',
    en: kind == RecommendationFailureKind.unavailable
        ? 'Service unreachable. $message'
        : 'Failed to load recommendations. $message',
    ja: kind == RecommendationFailureKind.unavailable
        ? 'サーバーに接続できません。$message'
        : 'おすすめの読み込みに失敗しました。$message',
    zhHans: kind == RecommendationFailureKind.unavailable
        ? '无法连接服务器。$message'
        : '加载推荐失败。$message',
    zhHant: kind == RecommendationFailureKind.unavailable
        ? '無法連線伺服器。$message'
        : '載入推薦失敗。$message',
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
  return lalaCopyMulti(
    language,
    ko: '지금 정보를 불러오지 못했어요.',
    en: 'Could not load the information right now.',
    ja: '現在情報を読み込めません。',
    zhHans: '暂时无法加载信息。',
    zhHant: '暫時無法載入資訊。',
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
  return lalaCopyMulti(
    language,
    ko: '추천 장소를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
    en: 'Could not load recommendations. Please try again shortly.',
    ja: 'おすすめスポットを読み込めませんでした。しばらくしてからもう一度お試しください。',
    zhHans: '无法加载推荐地点，请稍后重试。',
    zhHant: '無法載入推薦地點，請稍後重試。',
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

  // API 가 reason/recommendedAction 을 항상 채워 보내므로, 우선 순위는 기존과
  // 동일하게 reason/action 카피를 그대로 쓴다. 아래쪽 trigger-aware fallback 은
  // API 가 빈 카피를 보낸 honest-empty 경우에만 발동한다.

  // V6: ko 이외 로케일은 EN 카피 체인을 따른다(확장 로케일 폴백).
  if (normalizeLalaLanguage(language) != 'ko') {
    if (localizedReason != null && localizedAction != null) {
      return '$localizedReason · $localizedAction';
    }
    if (localizedReason != null) {
      return localizedReason;
    }
    if (localizedAction != null) {
      return localizedAction;
    }
    return _interventionFallbackCopy(intervention.triggerType, place, language);
  }

  if (localizedReason != null) {
    return localizedReason;
  }
  if (localizedAction != null) {
    return localizedAction;
  }
  return _interventionFallbackCopy(intervention.triggerType, place, language);
}

/// triggerType 에 따른 한 줄 배지 라벨(5개 로케일 단일 언어). null/알 수 없음은
/// 배지 없음(null). P4: 미세먼지(AQ) 트리거는 날씨 배지 라벨을 재사용하지 않는다 —
/// 나쁜 대기질이 '날씨 변화'(또는 그 번역)로만 표시되는 일이 없어야 한다.
String? interventionTriggerBadgeLabel(String? trigger, String language) {
  switch (trigger) {
    case 'closure_detected':
      return lalaCopyMulti(
        language,
        ko: '폐업 의심',
        en: 'Possible closure',
        ja: '休業の可能性',
        zhHans: '疑似停业',
        zhHant: '疑似停業',
      );
    case 'bad_air_quality':
      return lalaCopyMulti(
        language,
        ko: '미세먼지 나쁨',
        en: 'Poor air quality',
        ja: '大気が悪い',
        zhHans: '空气质量差',
        zhHant: '空氣品質差',
      );
    case 'bad_weather_and_air_quality':
      return lalaCopyMulti(
        language,
        ko: '날씨 + 미세먼지',
        en: 'Weather + air quality',
        ja: '気象 + 大気',
        zhHans: '天气 + 空气质量',
        zhHant: '天氣 + 空氣品質',
      );
    case 'bad_air_quality_and_closure':
      return lalaCopyMulti(
        language,
        ko: '미세먼지 + 폐업',
        en: 'Air quality + closure',
        ja: '大気 + 休業',
        zhHans: '空气质量 + 停业',
        zhHant: '空氣品質 + 停業',
      );
    case 'bad_weather_and_air_quality_and_closure':
      return lalaCopyMulti(
        language,
        ko: '날씨 + 미세먼지 + 폐업',
        en: 'Weather + air + closure',
        ja: '気象 + 大気 + 休業',
        zhHans: '天气 + 空气质量 + 停业',
        zhHant: '天氣 + 空氣品質 + 停業',
      );
    case 'bad_weather_and_closure':
      return lalaCopyMulti(
        language,
        ko: '날씨 + 폐업',
        en: 'Weather + closure',
        ja: '気象 + 休業',
        zhHans: '天气 + 停业',
        zhHant: '天氣 + 停業',
      );
    case 'bad_weather':
      return lalaCopyMulti(
        language,
        ko: '날씨 변화',
        en: 'Weather change',
        ja: '気象の変化',
        zhHans: '天气变化',
        zhHant: '天氣變化',
      );
    default:
      return null;
  }
}

/// triggerType 에 따른 honest fallback 카피(KO/EN 배타). API 카피가 비었을 때만
/// 쓰인다. bad_weather/null 은 기존 weather 카피와 동일(역호환), closure_detected
/// 와 bad_weather_and_closure 는 새 카피. P4: bad_air_quality 및 조합은 원인에 맞는
/// 카피를 쓴다(미세먼지 원인을 날씨로 위조하지 않는다). 대체 장소가 없어도 위조하지 않는다.
String _interventionFallbackCopy(String? trigger, String? place, String language) {
  switch (trigger) {
    case 'closure_detected':
      return place != null
          ? lalaCopyMulti(
                language,
                ko: '선택한 장소가 영업 중이 아닐 수 있어요. $place 근처 다른 옵션을 확인해 보세요.',
                en: 'The chosen place may be closed. Check other options near $place.',
                ja: '選択したスポットは営業していない可能性があります。$place 付近の他の選択肢をご確認ください。',
                zhHans: '所选地点可能已打烊。请查看 $place 附近的其他选择。',
                zhHant: '所選地點可能已打烊。請查看 $place 附近的其他選擇。',
              )
          : lalaCopyMulti(
                language,
                ko: '선택한 장소가 영업 중이 아닐 수 있어요. 동선을 다시 확인해 보세요.',
                en: 'The chosen place may be closed. Review the route.',
                ja: '選択したスポットは営業していない可能性があります。ルートをご確認ください。',
                zhHans: '所选地点可能已打烊。请重新查看路线。',
                zhHant: '所選地點可能已打烊。請重新查看路線。',
              );
    case 'bad_air_quality':
      return place != null
          ? lalaCopyMulti(
                language,
                ko: '미세먼지가 나빠요. $place 중심으로 실내 동선을 확인해보세요.',
                en: 'Air quality is poor. Check indoor routes near $place.',
                ja: '大気が悪いです。$place を中心に屋内ルートをご確認ください。',
                zhHans: '空气质量差。请查看 $place 附近的室内路线。',
                zhHant: '空氣品質差。請查看 $place 附近的室內路線。',
              )
          : lalaCopyMulti(
              language,
              ko: '미세먼지가 나빠요. 실내 동선을 확인해보세요.',
              en: 'Air quality is poor. Check indoor routes.',
              ja: '大気が悪いです。屋内ルートをご確認ください。',
              zhHans: '空气质量差。请查看室内路线。',
              zhHant: '空氣品質差。請查看室內路線。',
            );
    case 'bad_weather_and_air_quality':
      return place != null
          ? lalaCopyMulti(
                language,
                ko: '날씨와 미세먼지가 모두 좋지 않아요. $place 근처 실내 대안을 확인해 보세요.',
                en: 'Weather and air quality are both poor. Check indoor alternatives near $place.',
                ja: '天気も大気も悪いです。$place 付近の屋内の代替をご確認ください。',
                zhHans: '天气和空气质量都不佳。请查看 $place 附近的室内替代方案。',
                zhHant: '天氣和空氣品質都不佳。請查看 $place 附近的室內替代方案。',
              )
          : lalaCopyMulti(
              language,
              ko: '날씨와 미세먼지가 모두 좋지 않아요. 실내 대안을 확인해 보세요.',
              en: 'Weather and air quality are both poor. Check indoor alternatives.',
              ja: '天気も大気も悪いです。屋内の代替をご確認ください。',
              zhHans: '天气和空气质量都不佳。请查看室内替代方案。',
              zhHant: '天氣和空氣品質都不佳。請查看室內替代方案。',
            );
    case 'bad_air_quality_and_closure':
      return place != null
          ? lalaCopyMulti(
                language,
                ko: '미세먼지가 나쁘고 $place 도 영업 중이 아닐 수 있어요. 실내 대안을 확인해 보세요.',
                en: 'Air quality is poor and $place may be closed. Check indoor alternatives.',
                ja: '大気が悪く、$place も営業していない可能性があります。屋内の代替をご確認ください。',
                zhHans: '空气质量差，$place 也可能已打烊。请查看室内替代方案。',
                zhHant: '空氣品質差，$place 也可能已打烊。請查看室內替代方案。',
              )
          : lalaCopyMulti(
              language,
              ko: '미세먼지가 나쁘고 일부 장소가 영업 중이 아닐 수 있어요. 실내 대안을 확인해 보세요.',
              en: 'Air quality is poor and some places may be closed. Check indoor alternatives.',
              ja: '大気が悪く、一部のスポットは営業していない可能性があります。屋内の代替をご確認ください。',
              zhHans: '空气质量差，部分地点可能已打烊。请查看室内替代方案。',
              zhHant: '空氣品質差，部分地點可能已打烊。請查看室內替代方案。',
            );
    case 'bad_weather_and_air_quality_and_closure':
      return place != null
          ? lalaCopyMulti(
                language,
                ko: '날씨와 미세먼지가 좋지 않고 $place 도 영업 중이 아닐 수 있어요. 실내 대안을 확인해 보세요.',
                en: 'Weather and air quality are poor and $place may be closed. Check indoor alternatives.',
                ja: '天気と大気が悪く、$place も営業していない可能性があります。屋内の代替をご確認ください。',
                zhHans: '天气和空气质量不佳，$place 也可能已打烊。请查看室内替代方案。',
                zhHant: '天氣和空氣品質不佳，$place 也可能已打烊。請查看室內替代方案。',
              )
          : lalaCopyMulti(
              language,
              ko: '날씨와 미세먼지가 좋지 않고 일부 장소가 영업 중이 아닐 수 있어요. 실내 대안을 확인해 보세요.',
              en: 'Weather and air quality are poor and some places may be closed. Check indoor alternatives.',
              ja: '天気と大気が悪く、一部のスポットは営業していない可能性があります。屋内の代替をご確認ください。',
              zhHans: '天气和空气质量不佳，部分地点可能已打烊。请查看室内替代方案。',
              zhHant: '天氣和空氣品質不佳，部分地點可能已打烊。請查看室內替代方案。',
            );
    case 'bad_weather_and_closure':
      return place != null
          ? lalaCopyMulti(
                language,
                ko: '날씨가 좋지 않고 $place 도 영업 중이 아닐 수 있어요. 실내 대안을 확인해 보세요.',
                en: 'Weather is poor and $place may be closed. Check indoor alternatives.',
                ja: '天気が悪く、$place も営業していない可能性があります。屋内の代替をご確認ください。',
                zhHans: '天气不佳，$place 也可能已打烊。请查看室内替代方案。',
                zhHant: '天氣不佳，$place 也可能已打烊。請查看室內替代方案。',
              )
          : lalaCopyMulti(
                language,
                ko: '날씨가 좋지 않고 일부 장소가 영업 중이 아닐 수 있어요. 실내 대안을 확인해 보세요.',
                en: 'Weather is poor and some places may be closed. Check indoor alternatives.',
                ja: '天気が悪く、一部のスポットは営業していない可能性があります。屋内の代替をご確認ください。',
                zhHans: '天气不佳，部分地点可能已打烊。请查看室内替代方案。',
                zhHant: '天氣不佳，部分地點可能已打烊。請查看室內替代方案。',
              );
    case 'bad_weather':
    default:
      // null / 알 수 없는 트리거도 기존 weather 카피와 동일(역호환) — V3 이전
      // triggerType 은 항상 null/bad_weather 이었고 기존 토스트는 weather 카피를
      // 썼으므로, dashboard 경로(widget_test)의 기대 문구를 보존한다.
      return place != null
          ? lalaCopyMulti(
                language,
                ko: '날씨가 바뀌었어요. $place 중심으로 동선을 다시 확인해보세요.',
                en: 'Weather changed. Adjust the route near $place.',
                ja: '天気が変わりました。$place を中心にルートをご確認ください。',
                zhHans: '天气有变化。请围绕 $place 重新查看路线。',
                zhHant: '天氣有變化。請圍繞 $place 重新查看路線。',
              )
          : lalaCopyMulti(
              language,
              ko: '날씨가 바뀌었어요. 하루 일정을 다시 확인해보세요.',
              en: 'Weather changed. Review today\'s route.',
              ja: '天気が変わりました。今日のプランをご確認ください。',
              zhHans: '天气有变化。请查看今日计划。',
              zhHant: '天氣有變化。請查看今日計畫。',
            );
  }
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
    'event' => lalaCopyMulti(
      language,
      ko: '행사 맥락',
      en: 'Event context',
      ja: 'イベント文脈',
      zhHans: '活动背景',
      zhHant: '活動背景',
    ),
    'restaurant' => lalaCopyMulti(
      language,
      ko: '맛집 로컬 맥락',
      en: 'Food local context',
      ja: 'グルメのローカル文脈',
      zhHans: '美食本地背景',
      zhHant: '美食在地背景',
    ),
    'culture_venue' => lalaCopyMulti(
      language,
      ko: '문화 연계 맥락',
      en: 'Culture context',
      ja: '文化連携文脈',
      zhHans: '文化关联背景',
      zhHant: '文化關聯背景',
    ),
    _ => lalaCopyMulti(
      language,
      ko: '로컬 맥락',
      en: 'Local context',
      ja: 'ローカル文脈',
      zhHans: '本地背景',
      zhHant: '在地背景',
    ),
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
  required String? source,
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
      lalaCopyMulti(
          language,
          ko: '장소 연계 행사 ${commaInt(placeEventCount)}건',
          en: '${commaInt(placeEventCount)} linked events',
          ja: 'スポット関連イベント ${commaInt(placeEventCount)}件',
          zhHans: '${commaInt(placeEventCount)} 场关联活动',
          zhHant: '${commaInt(placeEventCount)} 場關聯活動',
        ),
    );
  } else if (cultureEventCount > 0) {
    add(
      Icons.festival_outlined,
      lalaCopyMulti(
          language,
          ko: '지역 문화행사 ${commaInt(cultureEventCount)}건',
          en: '${commaInt(cultureEventCount)} nearby culture events',
          ja: '地域の文化イベント ${commaInt(cultureEventCount)}件',
          zhHans: '${commaInt(cultureEventCount)} 场附近文化活动',
          zhHant: '${commaInt(cultureEventCount)} 場附近文化活動',
        ),
    );
  }

  final spendAmount = asFeatureDouble(features['region_spend_amount']);
  if (includeEvidence && spendAmount > 0) {
    add(
      Icons.payments_outlined,
      lalaCopyMulti(
          language,
          ko: '카드 소비 ${formatWonCompact(spendAmount, language)}',
          en: 'Card spend ${formatWonCompact(spendAmount, language)}',
          ja: 'カード消費 ${formatWonCompact(spendAmount, language)}',
          zhHans: '刷卡消费 ${formatWonCompact(spendAmount, language)}',
          zhHant: '刷卡消費 ${formatWonCompact(spendAmount, language)}',
        ),
    );
  }

  final transactionCount = asFeatureInt(features['region_transaction_count']);
  if (includeEvidence && transactionCount > 0) {
    add(
      Icons.receipt_long_outlined,
      lalaCopyMulti(
          language,
          ko: '거래 ${commaInt(transactionCount)}건',
          en: '${commaInt(transactionCount)} transactions',
          ja: '取引 ${commaInt(transactionCount)}件',
          zhHans: '${commaInt(transactionCount)} 笔交易',
          zhHant: '${commaInt(transactionCount)} 筆交易',
        ),
    );
  }

  // RC3: 날씨 요약·귀속은 독과 같은 SSOT(publicWeatherSummary)에서 한 쌍.
  // placeholder/fallback 이면 둘 다 null → 날씨 칩과 날씨소스 칩이 함께 생략된다.
  final weatherSummary = publicWeatherSummary(weather, language);
  if (weatherSummary.summary != null) {
    add(Icons.wb_cloudy_outlined, weatherSummary.summary);
    add(Icons.cloud_outlined, weatherSummary.source);
  }

  // RC3: 추천 소스는 showEvidence 와 무관한 일반 경로 정직 정보('-' 면 add 가 생략).
  // 출처 provenance(externalSourceLabel)는 PublicDataProofRow 가 증거 경로에서 동일 SSOT 으로
  // 더 자세히 보여주므로 카드에서는 위임(중복 제거) — §1a deep-proof 분리, D-Cap 노출로 드러난 중복.
  add(Icons.bolt_outlined, sourceLabel(source, language: language));

  return facts.take(8).toList(growable: false);
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
  // V6: ko 만 KO 출처명. 그 외 로케일(en/ja/zh)은 EN 출처명 — KO 명칭이 방문객
  // 화면에 노출되지 않도록 한다(계약 I1).
  if (normalizeLalaLanguage(language) != 'ko') {
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
  switch (normalizeLalaLanguage(language)) {
    case 'ko':
      final rounded = value.round();
      if (rounded >= 10000) {
        return '${commaInt(rounded / 10000)}만원';
      }
      return '${commaInt(rounded)}원';
    case 'ja':
      // 만원 단위는 일본어 권(万円) 관습을 따른다.
      final rounded = value.round();
      if (rounded >= 10000) {
        return '${commaInt(rounded / 10000)}万円';
      }
      return '₩${commaInt(rounded)}';
    case 'zh-Hans':
    case 'zh-Hant':
      final rounded = value.round();
      if (rounded >= 10000) {
        final wan = commaInt(rounded / 10000);
        return normalizeLalaLanguage(language) == 'zh-Hant' ? '$wan萬韓元' : '$wan万韩元';
      }
      return normalizeLalaLanguage(language) == 'zh-Hant'
          ? '₩${commaInt(rounded)}'
          : '₩${commaInt(rounded)}';
    case 'en':
      return 'KRW ${commaInt(value)}';
  }
  return 'KRW ${commaInt(value)}';
}
