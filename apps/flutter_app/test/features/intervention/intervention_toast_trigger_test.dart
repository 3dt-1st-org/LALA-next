// V3-D: InterventionToast + interventionToastLabel 트리거/swap/regenerate 검증.
// D1 closure_detected copy · D2 combined copy · D3 swap/no-alternative ·
// D4 regenerate wired · D5 overflow-safe · D6 single-language + semantics.
// LalaIntervention/LalaPlanSlot/LalaPlace 를 직접 생성(라이브 API 없음).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/features/intervention/widgets/intervention_toast.dart';

LalaCoordinate get _center => const LalaCoordinate(lat: 37.0, lng: 127.0);

LalaPlace _place({String name = '카페 솔', String nameEn = 'Cafe Sol'}) {
  return LalaPlace(
    placeId: 'p1',
    name: name,
    nameKo: name,
    nameEn: nameEn,
    category: 'cafe',
    lat: 37.0,
    lng: 127.0,
    address: '서울',
    distanceM: 120,
    source: 'test',
  );
}

LalaPlanSlot _slot({String title = '오전 · 카페 솔', LalaPlace? place}) {
  return LalaPlanSlot(period: 'morning', title: title, place: place ?? _place());
}

LalaIntervention _intervention({
  String? triggerType,
  LalaPlanSlot? alternativeSlot,
  String reason = '',
  String recommendedAction = '',
  LalaPlace? place,
}) {
  return LalaIntervention(
    center: _center,
    radiusM: 1000,
    shouldIntervene: true,
    reason: reason,
    recommendedAction: recommendedAction,
    source: 'test',
    triggerType: triggerType,
    alternativeSlot: alternativeSlot,
    place: place,
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('D1/D2 — interventionToastLabel trigger-aware fallback copy', () {
    test('closure_detected KO → closure copy, no weather wording', () {
      final label = interventionToastLabel(
        _intervention(triggerType: 'closure_detected'),
        'ko',
      );
      expect(label, contains('영업 중이 아닐'));
      expect(label, isNot(contains('날씨가 바뀌었어요')));
    });

    test('closure_detected EN → closure copy, single-language', () {
      final label = interventionToastLabel(
        _intervention(triggerType: 'closure_detected'),
        'en',
      );
      expect(label, contains('may be closed'));
      // EN 단일 언어 — 한글이 섞이지 않는다.
      expect(RegExp(r'[가-힣]').hasMatch(label), isFalse);
    });

    test('bad_weather_and_closure KO → combined copy mentions both', () {
      final label = interventionToastLabel(
        _intervention(triggerType: 'bad_weather_and_closure'),
        'ko',
      );
      expect(label, contains('날씨가 좋지 않고'));
      expect(label, contains('영업 중이 아닐'));
    });

    test('bad_weather_and_closure EN → combined copy, single-language', () {
      final label = interventionToastLabel(
        _intervention(triggerType: 'bad_weather_and_closure'),
        'en',
      );
      expect(label, contains('Weather is poor'));
      expect(label, contains('may be closed'));
      expect(RegExp(r'[가-힣]').hasMatch(label), isFalse);
    });

    test('bad_weather KO → existing weather copy (backward compat)', () {
      final label = interventionToastLabel(
        _intervention(triggerType: 'bad_weather'),
        'ko',
      );
      expect(label, '날씨가 바뀌었어요. 하루 일정을 다시 확인해보세요.');
    });

    test('null trigger KO → backward-compat weather copy, no fabricated closure', () {
      final label = interventionToastLabel(
        _intervention(triggerType: null),
        'ko',
      );
      // null/unknown 은 기존 weather 카피와 동일(역호환) — dashboard/widget_test 기대.
      expect(label, '날씨가 바뀌었어요. 하루 일정을 다시 확인해보세요.');
      expect(label, isNot(contains('영업 중이 아닐')));
    });

    test('reason/action from API still win over trigger fallback', () {
      final label = interventionToastLabel(
        _intervention(
          triggerType: 'closure_detected',
          reason: '비 내림 / Rain expected.',
          recommendedAction: '실내로 이동 / Move indoors.',
        ),
        'ko',
      );
      // KO 추출 — reason 단일 언어.
      expect(label, contains('비 내림'));
      expect(label, isNot(contains('영업 중이 아닐')));
    });
  });

  group('D3 — swap button vs honest no-alternative', () {
    testWidgets('swap button shown when swapLabel+onSwap present', (tester) async {
      var swaps = 0;
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '라벨',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            swapLabel: '대체 ▸ 카페 솔',
            onSwap: () => swaps += 1,
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();

      final swapFinder = find.byKey(const ValueKey('intervention-toast-swap'));
      expect(swapFinder, findsOneWidget);
      expect(find.textContaining('대체 ▸'), findsOneWidget);

      await tester.tap(swapFinder);
      await tester.pump();
      expect(swaps, 1);
    });

    testWidgets('honest no-alternative line shown when swap absent', (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '라벨',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            noAlternativeLabel: '지금은 대체 장소가 없어요.',
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('intervention-toast-swap')), findsNothing);
      expect(find.text('지금은 대체 장소가 없어요.'), findsOneWidget);
    });
  });

  group('D4 — regenerate wired', () {
    testWidgets('regenerate button invokes callback once', (tester) async {
      var regen = 0;
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '라벨',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            noAlternativeLabel: '지금은 대체 장소가 없어요.',
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () => regen += 1,
          ),
        ),
      );
      await tester.pump();

      final regenFinder = find.byKey(const ValueKey('intervention-toast-regenerate'));
      expect(regenFinder, findsOneWidget);

      await tester.tap(regenFinder);
      await tester.pump();
      expect(regen, 1);
    });
  });

  group('D5 — overflow-safe within 430; buttons ≥34dp', () {
    testWidgets('expanded toast respects 430 maxWidth', (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '아주 긴 라벨입니다. ' * 8,
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            triggerBadge: '폐업 의심',
            swapLabel: '대체 ▸ 매우 긴 장소 이름입니다 이것도 길어요',
            onSwap: () {},
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();

      final width = tester.getSize(find.byType(InterventionToast)).width;
      expect(width, lessThanOrEqualTo(430));
    });

    testWidgets('action buttons meet ≥34dp minimum height', (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '라벨',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            swapLabel: '대체 ▸ 카페',
            onSwap: () {},
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();

      final swapHeight = tester.getSize(
        find.byKey(const ValueKey('intervention-toast-swap')),
      ).height;
      expect(swapHeight, greaterThanOrEqualTo(34));
    });
  });

  group('D6 — single-language + trigger badge + semantics', () {
    testWidgets('KO trigger badge + swap/regenerate are single-language', (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '선택한 장소가 영업 중이 아닐 수 있어요.',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            triggerBadge: '폐업 의심',
            swapLabel: '대체 ▸ 카페 솔',
            onSwap: () {},
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('폐업 의심'), findsOneWidget);
      expect(find.text('일정 다시 짜기'), findsOneWidget);
      // KO 배타 — 영어 카피가 섞이지 않는다.
      expect(find.text('Regenerate'), findsNothing);
      expect(find.text('Possible closure'), findsNothing);
    });

    testWidgets('EN trigger badge + swap/regenerate are single-language', (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: 'The chosen place may be closed.',
            language: 'en',
            onOpenPlanner: () {},
            onDismiss: () {},
            triggerBadge: 'Possible closure',
            swapLabel: 'Swap ▸ Cafe Sol',
            onSwap: () {},
            regenerateLabel: 'Regenerate',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Possible closure'), findsOneWidget);
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.text('폐업 의심'), findsNothing);
      expect(find.text('일정 다시 짜기'), findsNothing);
    });

    testWidgets('trigger badge is exposed to semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '선택한 장소가 영업 중이 아닐 수 있어요.',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            triggerBadge: '폐업 의심',
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('폐업 의심'), findsOneWidget);
      handle.dispose();
    });
  });

  group('D8 — backward compat (no optional params = today shape)', () {
    testWidgets('dashboard path: no expanded section, plan + close present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '날씨가 바뀌었어요.',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pump();

      // 기본 행 그대로.
      expect(find.text('날씨가 바뀌었어요.'), findsOneWidget);
      expect(find.text('일정 보기'), findsOneWidget);
      expect(find.byTooltip('닫기'), findsOneWidget);
      // 확장 영역 없음.
      expect(find.byKey(const ValueKey('intervention-toast-swap')), findsNothing);
      expect(
        find.byKey(const ValueKey('intervention-toast-regenerate')),
        findsNothing,
      );
      expect(find.textContaining('대체'), findsNothing);
    });

    testWidgets('dashboard path: respects 430 maxWidth', (tester) async {
      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '날씨가 바뀌었어요. ' * 16,
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pump();
      final width = tester.getSize(find.byType(InterventionToast)).width;
      expect(width, lessThanOrEqualTo(430));
    });
  });

  group('D3 — full plan_page integration shape (alternativeSlot present/absent)', () {
    testWidgets('alternativeSlot != null → swap label carries alt place name', (tester) async {
      // plan_page 가 _interventionSwapLabel 로 계산하는 형태를 presentational 로 검증.
      final alt = _slot(title: '오전 · 카페 솔', place: _place(name: '카페 솔'));
      expect(alt.place, isNotNull);

      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: '선택한 장소가 영업 중이 아닐 수 있어요.',
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            triggerBadge: '폐업 의심',
            swapLabel: '대체 ▸ 카페 솔',
            onSwap: () {},
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('대체 ▸ 카페 솔'), findsOneWidget);
      // alternativeSlot 이 있으므로 honest no-alternative 는 렌더되지 않는다.
      expect(find.text('지금은 대체 장소가 없어요.'), findsNothing);
    });

    testWidgets('alternativeSlot == null → no swap, honest line only (no fabricated place)', (tester) async {
      final iv = _intervention(triggerType: 'closure_detected');
      expect(iv.alternativeSlot, isNull);

      await tester.pumpWidget(
        _wrap(
          InterventionToast(
            label: interventionToastLabel(iv, 'ko'),
            language: 'ko',
            onOpenPlanner: () {},
            onDismiss: () {},
            triggerBadge: '폐업 의심',
            noAlternativeLabel: '지금은 대체 장소가 없어요.',
            regenerateLabel: '일정 다시 짜기',
            onRegenerate: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('intervention-toast-swap')), findsNothing);
      expect(find.text('지금은 대체 장소가 없어요.'), findsOneWidget);
    });
  });
}
