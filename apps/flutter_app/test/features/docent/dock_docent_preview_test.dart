// P6E (P6A §13.3 / 01 Map Selected place detail panel): compact bottom place panel.
// compact = name/category/distance/docent summary; score & rationale folded by default;
// add-to-plan action; docent summary real-data-based (honest when absent).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/docent/widgets/dock_docent_preview.dart';
import 'package:lala_next_app/features/place/widgets/signal_grid.dart';

const _place = LalaPlace(
  placeId: 'p1',
  name: 'p1',
  nameKo: '행궁동 카페',
  category: 'restaurant',
  lat: 37.28,
  lng: 127.01,
  address: '경기도 수원시 팔달구',
  distanceM: 210,
  source: 'db',
  regionKo: '수원',
  regionEn: 'Suwon',
);

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

DockDocentPreview _dock({
  String language = 'ko',
  String? script,
  bool audioLoading = false,
  String? audioError,
  bool canFetchAudio = false,
  VoidCallback? onAddToPlan,
}) {
  return DockDocentPreview(
    place: _place,
    language: language,
    script: script,
    action: null,
    audioLoading: audioLoading,
    audioError: audioError,
    docentAudio: null,
    canFetchAudio: canFetchAudio,
    onFetchAudio: () {},
    onAddToPlan: onAddToPlan ?? () {},
    onOpenDetail: () {},
  );
}

void main() {
  group('DockDocentPreview compact content (P6A §13.3)', () {
    testWidgets('shows name, category, walk distance and docent summary', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_dock(script: '이 카페는 수원 화성 행궁 인근의 로컬 명소로 자리 잡았습니다.')),
      );
      await tester.pump();
      expect(find.textContaining('행궁동 카페'), findsAtLeastNWidgets(1));
      expect(find.text('맛집 · 도보 210m'), findsOneWidget);
      expect(find.textContaining('이 카페는'), findsAtLeastNWidgets(1));
    });

    testWidgets('English copy is exclusive', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _dock(
            language: 'en',
            script: 'This cafe is a local favorite near Hwaseong Haenggung.',
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('docent'), findsAtLeastNWidgets(1));
      expect(find.text('Food · 210m walk'), findsOneWidget);
      expect(find.textContaining('도보'), findsNothing);
    });
  });

  group('score and rationale folded by default', () {
    testWidgets(
      'compact panel exposes no score, signal grid or rationale toggle',
      (tester) async {
        await tester.pumpWidget(_wrap(_dock(script: '요약 문장.')));
        await tester.pump();
        expect(find.byType(SignalGrid), findsNothing);
        expect(find.textContaining('점수'), findsNothing);
        expect(find.textContaining('왜 지금'), findsNothing);
      },
    );
  });

  group('add-to-plan action', () {
    testWidgets('tapping the plan button fires onAddToPlan', (tester) async {
      var added = false;
      await tester.pumpWidget(
        _wrap(_dock(script: '요약.', onAddToPlan: () => added = true)),
      );
      await tester.pump();
      await tester.tap(find.text('하루 일정 보기'));
      expect(added, isTrue);
    });
  });

  group('honest docent + states', () {
    testWidgets(
      'without a script shows an honest loading message, no invented text',
      (tester) async {
        await tester.pumpWidget(_wrap(_dock(script: null)));
        await tester.pump();
        expect(
          find.text('도슨트 스크립트를 불러오는 중입니다. 잠시 뒤 다시 확인해 주세요.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('rejects placeholder/skeleton scripts honestly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_dock(script: 'This is a migration skeleton docent script.')),
      );
      await tester.pump();
      expect(
        find.text('도슨트 스크립트를 불러오는 중입니다. 잠시 뒤 다시 확인해 주세요.'),
        findsOneWidget,
      );
      expect(find.textContaining('migration skeleton'), findsNothing);
    });

    testWidgets('audio error surfaces honestly', (tester) async {
      await tester.pumpWidget(
        _wrap(_dock(script: '요약.', audioError: '오디오를 불러올 수 없어요.')),
      );
      await tester.pump();
      expect(find.text('오디오를 불러올 수 없어요.'), findsOneWidget);
    });

    testWidgets('audio loading state shows preparing copy', (tester) async {
      await tester.pumpWidget(
        _wrap(_dock(script: '요약.', audioLoading: true, canFetchAudio: true)),
      );
      await tester.pump();
      expect(find.text('음성 생성 중'), findsOneWidget);
    });
  });
}
