// §13.5 Map 탭 상태 honesty + 접근성 검증.
// 지도 본문은 항상 Kakao WebView 타일 위에 오버레이(상단 크롬 로딩 바 / 하단 독 /
// 실패 토스트)로 상태를 표현하므로, 상태 표면 위젯들을 직접 검증한다:
//   loading  -> TopMapChrome 로딩 바 + EmptyDockContent(preparing)
//   loaded   -> MapBottomDock 이 실제 장소(topPlace)를 표시
//   empty    -> 응답은 왔으나 장소 없음(no-data): EmptyDockContent(preparing) copy
//   unavailable -> EmptyDockContent/MapToast 의 도달 실패 카피(wifi_off)
//   error       -> EmptyDockContent/MapToast 의 서비스 오류 카피(error_outline)
// unavailable vs error vs empty(preparing) 카피는 서로 겹치지 않으며, 색상 단독 신호가
// 아니라 아이콘+텍스트+시맨틱 라벨로 구분한다(§13.5). 최소 44dp 터치 타겟 / 393dp 오버플로
// 없음도 검증. mock/demo 데이터는 쓰지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/home/home_view_helpers.dart';
import 'package:lala_next_app/features/map/widgets/category_chip.dart';
import 'package:lala_next_app/features/map/widgets/empty_dock_content.dart';
import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';
import 'package:lala_next_app/features/map/widgets/map_toast.dart';
import 'package:lala_next_app/features/map/widgets/top_map_chrome.dart';

void main() {
  // ---- loading (preparing): no error -> preparing copy, never failure copy ----
  testWidgets('preparing state shows preparing copy, distinct from any failure',
      (tester) async {
    await _pump(tester, EmptyDockContent(language: 'ko'));
    await tester.pump();

    expect(find.text('추천을 준비 중입니다'), findsOneWidget);
    // 준비 중 카피는 실패 카피와 겹치지 않는다.
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
  });

  // ---- unavailable (network/timeout; can't reach the service) ----
  testWidgets('unavailable shows the reachability copy and is not error/empty copy',
      (tester) async {
    await _pump(
      tester,
      EmptyDockContent(
        language: 'ko',
        errorLabel: '일시적으로 서버에 연결할 수 없어요.',
        failureKind: RecommendationFailureKind.unavailable,
        onRetry: () {},
      ),
    );
    await tester.pump();

    expect(find.text('서버에 연결할 수 없어요'), findsOneWidget);
    expect(find.text('지금 다시 시도'), findsOneWidget);
    // unavailable ≠ error copy.
    expect(find.textContaining('다시 확인하고 있어요'), findsNothing);
  });

  // ---- error (service responded with an error) ----
  testWidgets('error shows the service-error copy, distinct from unavailable',
      (tester) async {
    await _pump(
      tester,
      EmptyDockContent(
        language: 'ko',
        errorLabel: '추천 장소를 불러오지 못했어요.',
        failureKind: RecommendationFailureKind.error,
        onRetry: () {},
      ),
    );
    await tester.pump();

    expect(find.text('추천 연결을 다시 확인하고 있어요'), findsOneWidget);
    expect(find.text('지금 다시 시도'), findsOneWidget);
    // error ≠ unavailable copy.
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
  });

  // ---- empty no-data copy never equals failure copy ----
  testWidgets('preparing copy never overlaps unavailable or error copy',
      (tester) async {
    await _pump(
      tester,
      EmptyDockContent(
        language: 'ko',
        errorLabel: '추천 장소를 불러오지 못했어요.',
        failureKind: RecommendationFailureKind.error,
        onRetry: () {},
      ),
    );
    await tester.pump();
    // 준비 중(preparing) 카피는 실패 상태에서 등장하지 않는다.
    expect(find.text('추천을 준비 중입니다'), findsNothing);
  });

  // ---- loaded: bottom dock shows a real place, never EmptyDockContent ----
  testWidgets('loaded dock shows a real place and not the empty/failure content',
      (tester) async {
    await _pump(tester, _dock(topPlace: _cafe));
    await tester.pump();

    expect(find.text('행궁동 카페'), findsWidgets);
    // 실제 장소가 있으면 빈/실패 콘텐츠(EmptyDockContent)가 렌더되지 않는다.
    expect(find.byType(EmptyDockContent), findsNothing);
    expect(find.text('추천을 준비 중입니다'), findsNothing);
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
  });

  // ---- empty(no top place) renders EmptyDockContent, not a real place ----
  testWidgets('empty dock with no place renders EmptyDockContent', (tester) async {
    await _pump(tester, _dock(topPlace: null));
    await tester.pump();

    expect(find.byType(EmptyDockContent), findsOneWidget);
    expect(find.text('행궁동 카페'), findsNothing);
  });

  // ---- a11y: Semantics labels on each dock state ----
  testWidgets('preparing dock exposes a Semantics label', (tester) async {
    await _pump(tester, EmptyDockContent(language: 'ko'));
    await tester.pump();
    expect(
      _hasSemanticsLabel(tester, containing: '추천 준비 중'),
      isTrue,
      reason: 'preparing must expose a Semantics label',
    );
  });

  testWidgets('unavailable dock exposes a Semantics label', (tester) async {
    await _pump(
      tester,
      EmptyDockContent(
        language: 'ko',
        errorLabel: '일시적으로 서버에 연결할 수 없어요.',
        failureKind: RecommendationFailureKind.unavailable,
        onRetry: () {},
      ),
    );
    await tester.pump();
    expect(
      _hasSemanticsLabel(tester, containing: '서버 연결 불가'),
      isTrue,
      reason: 'unavailable must expose a label',
    );
  });

  testWidgets('error dock exposes a Semantics label', (tester) async {
    await _pump(
      tester,
      EmptyDockContent(
        language: 'ko',
        errorLabel: '추천 장소를 불러오지 못했어요.',
        failureKind: RecommendationFailureKind.error,
        onRetry: () {},
      ),
    );
    await tester.pump();
    expect(
      _hasSemanticsLabel(tester, containing: '추천 불러오기 실패'),
      isTrue,
      reason: 'error must expose a label',
    );
  });

  testWidgets('TopMapChrome loading bar exposes a Semantics label', (tester) async {
    await _pump(
      tester,
      TopMapChrome(
        loading: true,
        language: 'ko',
        selectedCategory: 'all',
        onSelectCategory: (_) {},
        onOpenSettings: () {},
      ),
    );
    await tester.pump();
    expect(
      _hasSemanticsLabel(tester, containing: '추천 장소를 불러오는 중'),
      isTrue,
      reason: 'map loading bar must expose a Semantics label',
    );
  });

  // ---- a11y: failure retry button meets 44dp ----
  testWidgets('dock failure retry button meets the 44dp minimum touch target',
      (tester) async {
    await _pump(
      tester,
      EmptyDockContent(
        language: 'ko',
        errorLabel: '추천 장소를 불러오지 못했어요.',
        failureKind: RecommendationFailureKind.error,
        onRetry: () {},
      ),
    );
    await tester.pump();

    final retry = find.byKey(const ValueKey('dock-error-retry'));
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
  });

  // ---- a11y: CategoryChip meets 44dp min height ----
  testWidgets('CategoryChip meets the 44dp minimum touch target', (tester) async {
    await _pump(
      tester,
      CategoryChip(
        label: '전체',
        active: true,
        color: const Color(0xFF2B6CB0),
        onTap: () {},
        width: 36,
      ),
    );
    await tester.pump();

    final chip = find.byType(CategoryChip);
    expect(chip, findsOneWidget);
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
  });

  // ---- a11y: unavailable vs error map toast use distinct icons (not color alone) ----
  testWidgets('unavailable and error toasts use distinct icons (color not alone)',
      (tester) async {
    await _pump(
      tester,
      MapToast(
        icon: Icons.wifi_off_rounded,
        label: '일시적으로 서버에 연결할 수 없어요.',
        color: const Color(0xFFEAF2FF),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);

    await _pump(
      tester,
      MapToast(
        icon: Icons.error_outline,
        label: '추천 장소를 불러오지 못했어요.',
        color: const Color(0xFFFFF3E8),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  // ---- a11y: no RenderFlex overflow at 393dp on each state ----
  testWidgets('dock preparing/unavailable/error do not overflow at 393dp',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, EmptyDockContent(language: 'ko'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await _pump(
      tester,
      EmptyDockContent(
        language: 'ko',
        errorLabel: '일시적으로 서버에 연결할 수 없어요.',
        failureKind: RecommendationFailureKind.unavailable,
        onRetry: () {},
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await _pump(
      tester,
      EmptyDockContent(
        language: 'ko',
        errorLabel: '추천 장소를 불러오지 못했어요.',
        failureKind: RecommendationFailureKind.error,
        onRetry: () {},
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

// ---- helpers ----

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

/// 시맨틱 트리 전체에서 [containing] 부분문자열을 label 로 갖는 노드가 하나라도
/// 있는지 재귀 탐색.
bool _hasSemanticsLabel(WidgetTester tester, {required String containing}) {
  final root = tester.getSemantics(find.byType(MaterialApp));
  bool deep(SemanticsNode node) {
    if (node.label.contains(containing)) {
      return true;
    }
    var found = false;
    node.visitChildren((child) {
      if (!found) {
        found = deep(child);
      }
      return !found;
    });
    return found;
  }

  return deep(root);
}

MapBottomDock _dock({LalaPlace? topPlace}) {
  return MapBottomDock(
    isWide: false,
    places: topPlace == null ? const <LalaPlace>[] : <LalaPlace>[_cafe],
    source: 'db',
    dataAsOf: null,
    topPlace: topPlace,
    uiLanguage: 'ko',
    height: 240,
    docentScript: null,
    docentAudio: null,
    docentAction: null,
    audioLoading: false,
    audioError: null,
    canFetchAudio: false,
    showEvidence: false,
    error: null,
    placeFailureKind: null,
    recommendationRecoveryPending: false,
    onFetchAudio: () {},
    onAddToPlan: () {},
    onOpenDetail: () {},
    onRefresh: () {},
    onToggleEvidence: () {},
  );
}

const LalaPlace _cafe = LalaPlace(
  placeId: 'map-test-cafe',
  name: '행궁동 카페',
  nameKo: '행궁동 카페',
  nameEn: 'Haenggung Cafe',
  category: 'restaurant',
  lat: 37.2828,
  lng: 127.0101,
  address: '경기도 수원시 팔달구 행궁동',
  regionKo: '수원',
  regionEn: 'Suwon',
  distanceM: 320,
  source: 'db',
  upstreamSource: 'tour_api',
);
