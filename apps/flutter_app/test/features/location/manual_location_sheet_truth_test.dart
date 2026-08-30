import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/location/widgets/manual_location_sheet.dart';
import 'package:lala_next_app/features/location/widgets/manual_location_tile.dart';
import 'package:lala_next_app/manual_location_options.dart';

void main() {
  testWidgets(
    'all-areas filter is distinct from current region and selection needs apply',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: _SheetHarness()));
      await tester.tap(find.byKey(const ValueKey('open-region-sheet')));
      await tester.pumpAndSettle();

      expect(find.text('전체 지역 보기'), findsOneWidget);
      expect(find.text('현재 탐색 지역'), findsOneWidget);
      expect(find.text('기본 지역 · 수원'), findsOneWidget);

      final initialApply = tester.widget<FilledButton>(
        find.byKey(const ValueKey('manual-location-apply')),
      );
      expect(initialApply.onPressed, isNull);
      expect(
        tester
            .widgetList<ManualLocationTile>(find.byType(ManualLocationTile))
            .where((tile) => tile.selected),
        isEmpty,
      );

      await tester.tap(
        find.byKey(const ValueKey('manual-location-option-gyeonggi-suwon')),
      );
      await tester.pumpAndSettle();

      // 행 탭만으로 시트가 닫히거나 외부 선택값이 바뀌지 않는다.
      expect(find.text('지역 선택'), findsOneWidget);
      expect(find.text('selected:none'), findsOneWidget);
      expect(find.textContaining('경기도 수원시'), findsOneWidget);
      final pendingApply = tester.widget<FilledButton>(
        find.byKey(const ValueKey('manual-location-apply')),
      );
      expect(pendingApply.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('manual-location-apply')));
      await tester.pumpAndSettle();
      expect(find.text('selected:gyeonggi-suwon'), findsOneWidget);
      expect(find.text('지역 선택'), findsNothing);
    },
  );

  testWidgets('active manual region is preselected without changing list filter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: _SheetHarness(activeManualRegion: true)),
    );
    await tester.tap(find.byKey(const ValueKey('open-region-sheet')));
    await tester.pumpAndSettle();

    expect(find.text('전체 지역 보기'), findsOneWidget);
    expect(find.text('수원시'), findsWidgets);
    final suwonTile = tester.widget<ManualLocationTile>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ManualLocationTile &&
            widget.option.id == 'gyeonggi-suwon',
      ),
    );
    expect(suwonTile.selected, isTrue);
  });
}

class _SheetHarness extends StatefulWidget {
  const _SheetHarness({this.activeManualRegion = false});

  final bool activeManualRegion;

  @override
  State<_SheetHarness> createState() => _SheetHarnessState();
}

class _SheetHarnessState extends State<_SheetHarness> {
  ManualLocationOption? _selected;

  Future<void> _open() async {
    final result = await showModalBottomSheet<ManualLocationOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualLocationSheet(
        language: 'ko',
        activeRegionId: widget.activeManualRegion
            ? 'gyeonggi-suwon'
            : null,
        activeRegionLabel: widget.activeManualRegion
            ? '수원시'
            : '기본 지역 · 수원',
      ),
    );
    if (mounted) {
      setState(() => _selected = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            key: const ValueKey('open-region-sheet'),
            onPressed: _open,
            child: const Text('open'),
          ),
          Text('selected:${_selected?.id ?? 'none'}'),
        ],
      ),
    );
  }
}
