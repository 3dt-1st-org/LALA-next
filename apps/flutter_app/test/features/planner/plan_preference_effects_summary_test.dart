// CP1: 선호 반영 요약 위젯 계약 —
// - grounded(반영된) 효과 수만 카운트로 표시.
// - 미지원 필드(요리/예산/마감 임박)는 절대 '반영됨'으로 표시하지 않는다.
// - 안내문은 클라이언트 소유 5-locale 카피: 알려진 사유 코드 전부에 대해
//   KO/EN/JA/zh-Hans/zh-Hant 가 각 로케일 문장을 쓰고, JA/zh 행에는 서버
//   ko/en 원문이 절대 새지 않는다. 알 수 없는 코드만 서버 원문 폴백.
// - 200% 텍스트 스케일에서 오버플로 없음(soft wrap).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/planner/widgets/plan_preference_effects_summary.dart';

// 모든 픽스처 설명에 심는 원문 마커(서버 ko/en 문장 대리). 알려진 코드 로케일에서
// 이 문장이 보이면 클라이언트 카피 미사용(원문 누출)이다.
const String _rawServerSentence =
    'RAWSERVER-서버-원문-korean-english-sentence-for-leak-proof';

const List<LalaPlanPreferenceEffect> _effects = <LalaPlanPreferenceEffect>[
  LalaPlanPreferenceEffect(
    field: 'max_one_way_minutes',
    applied: true,
    reasonCode: 'RADIUS_CAPPED_TO_WALKING_TIME',
    explanation: '이동 시간 선호(15분)에 맞춰 탐색 반경을 5000m에서 1005m로 줄였어요. '
        '도보 4km/h 기준 추정이에요.',
    details: <String, dynamic>{
      'requested_radius_m': 5000,
      'effective_radius_m': 1005,
      'effective_one_way_minutes': 15,
    },
  ),
  LalaPlanPreferenceEffect(
    field: 'indoor_outdoor',
    applied: false,
    reasonCode: 'INDOOR_STATUS_UNAVAILABLE',
    explanation: '실내/야외 정보가 있는 장소가 없어 순서를 바꾸지 못했어요.',
  ),
  LalaPlanPreferenceEffect(
    field: 'food_cuisines',
    applied: false,
    reasonCode: 'CUISINE_FACET_UNAVAILABLE',
    explanation: '장소 데이터에 요리 정보가 없어 요리 선호를 반영하지 못했어요.',
  ),
  LalaPlanPreferenceEffect(
    field: 'budget_band',
    applied: false,
    reasonCode: 'PRICE_FACET_UNAVAILABLE',
    explanation: '장소 데이터에 가격 정보가 없어 예산 선호를 반영하지 못했어요.',
  ),
  LalaPlanPreferenceEffect(
    field: 'exclude_closing_soon',
    applied: false,
    reasonCode: 'CLOSING_SOON_FACET_UNAVAILABLE',
    explanation: '장소 데이터에 마감 임박 정보가 없어 제외 선호를 반영하지 못했어요.',
  ),
];

Widget _host(String language, {List<LalaPlanPreferenceEffect>? effects}) =>
    MaterialApp(
      locale: const Locale('ko'),
      home: Scaffold(
        body: ListView(
          children: [
            PlanPreferenceEffectsSummary(
              effects: effects ?? _effects,
              language: language,
            ),
          ],
        ),
      ),
    );

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('plan-preference-effects-expansion')),
  );
  await tester.pumpAndSettle();
}

/// 알려진 사유 코드 전부(경계: radius 계열은 bounded details 보간 포함).
const Map<String, Map<String, String>> _codeFragments = <String, Map<String, String>>{
  'RADIUS_CAPPED_TO_WALKING_TIME': <String, String>{
    'ko': '5000m에서 1005m로 줄였어요',
    'en': 'from 5000m to 1005m',
    'ja': '検索範囲を5000mから1005mに狭めました',
    'zh-Hans': '已将搜索范围从 5000 米缩小到 1005 米',
    'zh-Hant': '已將搜尋範圍從 5000 公尺縮小到 1005 公尺',
  },
  'RADIUS_CAP_NOT_BINDING': <String, String>{
    'ko': '그대로 유지했어요',
    'en': 'was kept as-is',
    'ja': 'そのまま維持しました',
    'zh-Hans': '因此保持不变',
    'zh-Hant': '因此維持不變',
  },
  'INDOOR_ORDERING_APPLIED': <String, String>{
    'ko': '후보 순서를 조정했어요',
    'en': 'adjusted to match the indoor/outdoor preference',
    'ja': '並び順を調整しました',
    'zh-Hans': '已根据室内/室外偏好调整候选顺序',
    'zh-Hant': '已依據室內/室外偏好調整候選順序',
  },
  'WEATHER_SAFETY_INDOOR_PRIORITY': <String, String>{
    'ko': '실내 후보를 우선 배치했어요',
    'en': 'prioritized over the outdoor preference',
    'ja': '屋内の候補を優先しました',
    'zh-Hans': '优先安排室内候选',
    'zh-Hant': '優先安排室內候選',
  },
  'INDOOR_ORDERING_NOT_DIRECTIONAL': <String, String>{
    'ko': '순서를 바꾸지 않았어요',
    'en': 'no ordering was applied',
    'ja': '並び順は変更しませんでした',
    'zh-Hans': '因此未调整顺序',
    'zh-Hant': '因此未調整順序',
  },
  'INDOOR_ORDERING_NO_CHANGE': <String, String>{
    'ko': '바뀐 항목이 없어요',
    'en': 'nothing changed',
    'ja': '変更はありませんでした',
    'zh-Hans': '没有变化',
    'zh-Hant': '沒有變動',
  },
  'INDOOR_STATUS_UNAVAILABLE': <String, String>{
    'ko': '순서를 바꾸지 못했어요',
    'en': 'no ordering was possible',
    'ja': '並び順を変更できませんでした',
    'zh-Hans': '无法调整顺序',
    'zh-Hant': '無法調整順序',
  },
  'CUISINE_FACET_UNAVAILABLE': <String, String>{
    'ko': '요리 선호를 반영하지 못했어요',
    'en': 'cuisine preference was not applied',
    'ja': '料理の設定は反映されませんでした',
    'zh-Hans': '未应用菜系偏好',
    'zh-Hant': '未套用菜系偏好',
  },
  'PRICE_FACET_UNAVAILABLE': <String, String>{
    'ko': '예산 선호를 반영하지 못했어요',
    'en': 'budget preference was not applied',
    'ja': '予算の設定は反映されませんでした',
    'zh-Hans': '未应用预算偏好',
    'zh-Hant': '未套用預算偏好',
  },
  'CLOSING_SOON_FACET_UNAVAILABLE': <String, String>{
    'ko': '제외 선호를 반영하지 못했어요',
    'en': 'exclusion preference was not applied',
    'ja': '除外の設定は反映されませんでした',
    'zh-Hans': '未应用排除偏好',
    'zh-Hant': '未套用排除偏好',
  },
};

LalaPlanPreferenceEffect _effectFor(String code) {
  final isRadiusCapped = code == 'RADIUS_CAPPED_TO_WALKING_TIME';
  final isRadiusNotBinding = code == 'RADIUS_CAP_NOT_BINDING';
  return LalaPlanPreferenceEffect(
    field: code.startsWith('RADIUS') ? 'max_one_way_minutes' : 'indoor_outdoor',
    applied: code == 'RADIUS_CAPPED_TO_WALKING_TIME' ||
        code == 'INDOOR_ORDERING_APPLIED' ||
        code == 'WEATHER_SAFETY_INDOOR_PRIORITY',
    reasonCode: code,
    explanation: _rawServerSentence,
    details: <String, dynamic>{
      if (isRadiusCapped) ...<String, dynamic>{
        'requested_radius_m': 5000,
        'effective_radius_m': 1005,
        'effective_one_way_minutes': 15,
      },
      if (isRadiusNotBinding) 'effective_one_way_minutes': 30,
    },
  );
}

void main() {
  testWidgets('compact count shows grounded effects only (ko)', (tester) async {
    await tester.pumpWidget(_host('ko'));

    // grounded 1건만 카운트에 반영(5건 중 applied=true 1건).
    expect(find.text('여행 선호 반영 1건'), findsOneWidget);
    expect(find.textContaining('2건'), findsNothing);
  });

  testWidgets('expanded entries never mark unsupported fields as applied', (
    tester,
  ) async {
    await tester.pumpWidget(_host('ko'));
    await _expand(tester);

    // applied=true 인 항목에만 '반영됨' 라벨 — 미지원 필드는 '미반영'.
    final appliedRows = tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && widget.data != null && widget.data!.contains('반영됨 ·'),
          ),
        )
        .toList();
    expect(appliedRows, hasLength(1));
    expect(appliedRows.single.data, contains('1005'));
    // 미지원(요리/예산/마감) 3종 + 실내 미지원 1종 = '미반영' 4행.
    expect(
      tester
          .widgetList<Text>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.data != null &&
                  widget.data!.contains('미반영 ·'),
            ),
          )
          .length,
      4,
    );
    // 시맨틱: 요약 라벨이 grounded/미반영 구분과 안내를 전달한다.
    expect(
      find.bySemanticsLabel(
        '여행 선호 중 1건이 일정에 반영되었고, 4건은 데이터가 없어 반영되지 않았어요. '
        '자세히 보기로 항목별 설명을 확인할 수 있어요.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty effects render nothing (legacy plans)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              PlanPreferenceEffectsSummary(effects: [], language: 'ko'),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plan-preference-effects-summary')), findsNothing);
  });

  const localizedTitles = <String, String>{
    'ko': '여행 선호 반영 1건',
    'en': '1 preference effects applied',
    'ja': '旅行の好みを1件反映',
    'zh-Hans': '已应用 1 项旅行偏好',
    'zh-Hant': '已套用 1 項旅行偏好',
  };
  for (final language in localizedTitles.keys) {
    final expectedTitle = localizedTitles[language]!;
    testWidgets('localized title completes for $language', (tester) async {
      await tester.pumpWidget(_host(language));

      expect(find.text(expectedTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // 알려진 사유 코드 전부 × 5 로케일: 클라이언트 카피 사용 + JA/zh 원문 미누출.
  for (final language in const <String>['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant']) {
    testWidgets(
      'every known reason code renders client copy in $language '
      '(raw server sentence never leaks)',
      (tester) async {
        for (final code in _codeFragments.keys) {
          // 코드별 고유 key: 이전 반복의 ExpansionTile 확장 상태가 재사되어
          // 탭이 '접기'로 동작하는 비결정성을 차단한다(항상 접힌 상태에서 시작).
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('summary-host-$language-$code'),
              locale: const Locale('ko'),
              home: Scaffold(
                body: ListView(
                  children: [
                    PlanPreferenceEffectsSummary(
                      key: ValueKey('summary-$language-$code'),
                      effects: <LalaPlanPreferenceEffect>[_effectFor(code)],
                      language: language,
                    ),
                  ],
                ),
              ),
            ),
          );
          await _expand(tester);

          // 1) 해당 로케일의 클라이언트 카피 문장이 실제 렌더된다.
          expect(
            find.textContaining(_codeFragments[code]![language]!),
            findsOneWidget,
            reason: '$language / $code',
          );
          // 2) 서버 ko/en 원문(대리 마커)은 보이지 않는다 — 원문 폴백 금지.
          expect(
            find.textContaining(_rawServerSentence),
            findsNothing,
            reason: '$language / $code must not leak the raw server sentence',
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  // KO/EN 의미 동등성: applied/not-applied 라벨 + bounded 값 보간 유지(대표 코드).
  testWidgets('ko/en rows keep applied labels and radius interpolation', (
    tester,
  ) async {
    for (final language in const <String>['ko', 'en']) {
      await tester.pumpWidget(_host(language));
      await _expand(tester);

      expect(
        find.textContaining(
          language == 'ko' ? '반영됨 · ' : 'Applied · ',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(language == 'ko' ? '미반영 · ' : 'Not applied · '),
        findsNWidgets(4),
      );
      expect(find.textContaining('1005'), findsOneWidget);
    }
  });

  testWidgets('unknown reason code falls back to the raw server explanation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        'ja',
        effects: const <LalaPlanPreferenceEffect>[
          LalaPlanPreferenceEffect(
            field: 'indoor_outdoor',
            applied: false,
            reasonCode: 'SOME_FUTURE_CODE',
            explanation: _rawServerSentence,
          ),
        ],
      ),
    );
    await _expand(tester);

    // 알 수 없는 코드: 정직한 서버 원문 폴백(클라이언트 카피 지도에 없음).
    expect(find.textContaining(_rawServerSentence), findsOneWidget);
  });

  testWidgets('radius code with missing details falls back to the raw server text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        'ja',
        effects: const <LalaPlanPreferenceEffect>[
          LalaPlanPreferenceEffect(
            field: 'max_one_way_minutes',
            applied: true,
            reasonCode: 'RADIUS_CAPPED_TO_WALKING_TIME',
            explanation: _rawServerSentence,
            // details 없음 — 보간 불가 → 서버 원문.
          ),
        ],
      ),
    );
    await _expand(tester);

    expect(find.textContaining(_rawServerSentence), findsOneWidget);
  });

  testWidgets('no overflow at 200% text scale in all five locales', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final language in const <String>[
      'ko',
      'en',
      'ja',
      'zh-Hans',
      'zh-Hant',
    ]) {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: _host(language),
        ),
      );
      await _expand(tester);

      expect(tester.takeException(), isNull,
          reason: '200% text overflow in $language');
      // 확장된 모든 항목의 안내문이 화면에 존재한다(잘림 없이 줄바꿈).
      expect(
        find.byKey(const ValueKey('plan-preference-effects-count')),
        findsOneWidget,
      );
    }
  });
}
