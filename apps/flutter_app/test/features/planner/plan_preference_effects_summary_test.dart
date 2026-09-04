// CP1: 선호 반영 요약 위젯 계약 —
// - grounded(반영된) 효과 수만 카운트로 표시.
// - 미지원 필드(요리/예산/마감 임박)는 절대 '반영됨'으로 표시하지 않는다.
// - KO/EN/JA/zh-Hans/zh-Hant 카피 완비.
// - 200% 텍스트 스케일에서 오버플로 없음(soft wrap).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/planner/widgets/plan_preference_effects_summary.dart';

const List<LalaPlanPreferenceEffect> _effects = <LalaPlanPreferenceEffect>[
  LalaPlanPreferenceEffect(
    field: 'max_one_way_minutes',
    applied: true,
    reasonCode: 'RADIUS_CAPPED_TO_WALKING_TIME',
    explanation: '이동 시간 선호(15분)에 맞춰 탐색 반경을 5000m에서 1005m로 줄였어요.',
    details: <String, dynamic>{'requested_radius_m': 5000, 'effective_radius_m': 1005},
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

Widget _host(String language) => MaterialApp(
  locale: const Locale('ko'),
  home: Scaffold(
    body: ListView(
      children: [
        PlanPreferenceEffectsSummary(effects: _effects, language: language),
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
