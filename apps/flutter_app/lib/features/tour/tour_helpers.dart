import 'dart:math' as math;

import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../shared/l10n/lala_copy.dart';
import '../../shared/l10n/place_labels.dart';

/// 맛집 투어 로컬 가이드 스크립트 생성(C3 추출 — main.dart 의 _tourGuideScript).
/// 후보 맛집 이름·거리·소비 신호를 문장으로 엮어 안내 문구를 만든다.
String tourGuideScript(List<LalaPlace> places, String language) {
  final items = places.take(5).toList(growable: false);
  if (items.isEmpty) {
    return lalaCopy(
      language,
      ko: '근처 맛집 후보를 찾으면 로컬 투어 스크립트를 준비합니다.',
      en: 'LALA prepares a local food tour script when nearby food stops are found.',
    );
  }
  final names = items
      .map((place) => placeDisplayName(place, language))
      .toList();
  final first = names.first;
  final tail = names.skip(1).take(3).toList();
  final localSignal = items
      .map((place) => place.score?.components.localSpendingScore ?? 0)
      .fold<double>(0, math.max);
  if (isLalaEnglish(language)) {
    final middle = tail.isEmpty ? '' : ' Continue through ${tail.join(', ')}.';
    final signal = localSignal >= 0.7
        ? ' These stops show strong local spending signals.'
        : ' The route favors nearby public and local context.';
    return 'Start at $first and keep the walk compact for a real neighborhood food route.$middle$signal Tap each stop for details before you go.';
  }
  final middle = tail.isEmpty ? '' : ' 이어서 ${tail.join(', ')} 쪽으로 걸어가면 좋아요.';
  final signal = localSignal >= 0.7
      ? ' 지역 소비 신호가 살아있는 맛집들을 우선 연결했습니다.'
      : ' 가까운 거리와 공공 장소 맥락을 함께 보고 묶은 코스입니다.';
  return '$first에서 시작해 동네 흐름을 따라 짧게 걷는 맛집 코스입니다.$middle$signal 출발 전 각 정류장을 눌러 상세 정보를 확인해보세요.';
}
