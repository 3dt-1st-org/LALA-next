// SignalGrid 정직 결측 회귀: null 신호를 가짜 fallback 수치로 채우지 않는다.
// - 실제(non-null) 값은 값/막대를 truthful 하게 렌더(기존 동작 유지).
// - null 신호는 행 전체를 생략 → 0.82/0.78/0.91/0.74 같은 조작값이 진짜로 노출되지 않음.
// - 네 신호 모두 null(일반 경로: include_scores=false) → 수치/막대 없는 정직한 빈 상태.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/place/widgets/signal_grid.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SignalGrid — real (non-null) values render truthfully', () {
    testWidgets('renders each value, label and bar (4 meters)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SignalGrid(
            language: 'ko',
            localSpending: 0.66,
            demandDispersion: 0.55,
            cultureRelevance: 0.88,
            weatherFit: 0.42,
          ),
        ),
      );

      // 실제 값 텍스트가 truthful 하게 노출된다.
      expect(find.text('0.66'), findsOneWidget);
      expect(find.text('0.55'), findsOneWidget);
      expect(find.text('0.88'), findsOneWidget);
      expect(find.text('0.42'), findsOneWidget);
      // 라벨 4종 모두 노출.
      expect(find.text('내국인 소비'), findsOneWidget);
      expect(find.text('수요 분산'), findsOneWidget);
      expect(find.text('문화 연계'), findsOneWidget);
      expect(find.text('날씨 적합'), findsOneWidget);
      // 실제 막대(LinearProgressIndicator) 4개.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
    });
  });

  group('SignalGrid — null signals omit fabrication (no fake fallback)', () {
    testWidgets('null 신호는 가짜 fallback 수치/막대를 렌더하지 않는다', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SignalGrid(
            language: 'ko',
            localSpending: 0.66,
            demandDispersion: null,
            cultureRelevance: null,
            weatherFit: null,
          ),
        ),
      );

      // 실제 신호는 그대로 truthful 노출(값 + 막대 1개).
      expect(find.text('0.66'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // null 신호의 가짜 fallback 이 진짜로 노출되지 않는다.
      expect(
        find.text('0.82'),
        findsNothing,
      ); // localSpending fallback (real 값이므로 본래 표시 안 됨)
      expect(find.text('0.78'), findsNothing); // demandDispersion fallback
      expect(find.text('0.91'), findsNothing); // cultureRelevance fallback
      expect(find.text('0.74'), findsNothing); // weatherFit fallback
      // null 신호는 라벨까지 생략(행 전체 누락).
      expect(find.text('수요 분산'), findsNothing);
      expect(find.text('문화 연계'), findsNothing);
      expect(find.text('날씨 적합'), findsNothing);
    });
  });

  group('SignalGrid — all-null (normal path) honest empty state', () {
    testWidgets('네 신호 모두 null → 어떤 수치/막대도 없고 정직한 빈 상태만 노출', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SignalGrid(
            language: 'ko',
            localSpending: null,
            demandDispersion: null,
            cultureRelevance: null,
            weatherFit: null,
          ),
        ),
      );

      // 어떤 조작 fallback 수치도 노출되지 않는다.
      expect(find.text('0.82'), findsNothing);
      expect(find.text('0.78'), findsNothing);
      expect(find.text('0.91'), findsNothing);
      expect(find.text('0.74'), findsNothing);
      // 가짜 막대도 없다.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // 미터 라벨도 누락.
      expect(find.text('내국인 소비'), findsNothing);
      expect(find.text('수요 분산'), findsNothing);
      // 정직한 비수치 placeholder 만 노출(숫자 아님).
      expect(find.text('데이터 없음'), findsOneWidget);
    });

    testWidgets('en: honest empty state is English (no KO/EN mix)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SignalGrid(
            language: 'en',
            localSpending: null,
            demandDispersion: null,
            cultureRelevance: null,
            weatherFit: null,
          ),
        ),
      );
      expect(find.text('No data yet'), findsOneWidget);
      expect(find.text('데이터 없음'), findsNothing);
    });
  });
}
