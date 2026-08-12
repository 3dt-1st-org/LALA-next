// §13.5 Search 탭 5개 상태(loading/loaded/empty/unavailable/error) honest distinct
// 표시 + 접근성(최소 44dp 터치 타겟, Semantics 라벨, 393dp 오버플로 없음) 검증.
// 어떤 상태도 mock/demo 데이터를 쓰지 않으며, API 실패 카피는 빈 상태(no-data)
// 카피와 절대 겹치지 않는다(unavailable vs error 도 서로 구분).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';

void main() {
  setUp(() {
    RegionContextStore.clear();
    OnboardingState.selectLanguage('ko');
  });

  // ---- loading ----
  testWidgets('loading shows exactly three neutral skeleton rows, no results/failure',
      (tester) async {
    await _pumpSearch(tester, backend: _HangingSearchBackend());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.byKey(const ValueKey('search-skeleton-row')), findsNWidgets(3));
    // 실제 결과/실패 카피가 로딩 중에는 섞이지 않는다.
    expect(find.text('행궁동 카페'), findsNothing);
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
  });

  // ---- loaded ----
  testWidgets('loaded shows real results and never a skeleton', (tester) async {
    await _pumpSearch(tester, backend: _LoadedSearchBackend());
    await tester.pumpAndSettle();

    expect(find.text('행궁동 카페'), findsOneWidget);
    // loaded 는 스켈레톤/빈·실패 카피를 띄우지 않는다.
    expect(find.byKey(const ValueKey('search-skeleton-row')), findsNothing);
    expect(find.textContaining('추천이 없어요'), findsNothing);
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
  });

  // ---- empty (no-data; distinct from any failure) ----
  testWidgets('empty shows the no-data message, distinct from failure copy',
      (tester) async {
    await _pumpSearch(tester, backend: _EmptySearchBackend());
    await tester.pumpAndSettle();

    expect(find.text('이 주변엔 아직 추천이 없어요.'), findsOneWidget);
    // 빈 상태 카피는 실패 카피와 겹치지 않는다.
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    // 빈 상태는 스켈레톤을 띄우지 않는다.
    expect(find.byKey(const ValueKey('search-skeleton-row')), findsNothing);
  });

  // ---- unavailable (network/timeout; can't reach the service) ----
  testWidgets('unavailable shows the reachability copy and is not empty/error copy',
      (tester) async {
    await _pumpSearch(
      tester,
      backend: _ThrowingSearchBackend(
        const LalaApiException(
          code: 'NETWORK_ERROR',
          message: 'unreachable',
          statusCode: 0,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-unavailable-view')), findsOneWidget);
    expect(find.textContaining('연결할 수 없어요'), findsOneWidget);
    expect(find.text('재시도'), findsOneWidget);
    // unavailable ≠ empty no-data copy.
    expect(find.text('이 주변엔 아직 추천이 없어요.'), findsNothing);
    // unavailable ≠ error copy (서비스가 응답한 오류 문구).
    expect(find.textContaining('불러오지 못했어요'), findsNothing);
    expect(find.byKey(const ValueKey('search-skeleton-row')), findsNothing);
  });

  // ---- error (service responded with an error) ----
  testWidgets('error shows the service-error copy, distinct from empty and unavailable',
      (tester) async {
    await _pumpSearch(
      tester,
      backend: _ThrowingSearchBackend(
        const LalaApiException(
          code: 'HTTP_503',
          message: 'upstream error',
          statusCode: 503,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-error-view')), findsOneWidget);
    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    expect(find.text('재시도'), findsOneWidget);
    // error ≠ empty no-data copy.
    expect(find.text('이 주변엔 아직 추천이 없어요.'), findsNothing);
    // error ≠ unavailable copy.
    expect(find.textContaining('연결할 수 없어요'), findsNothing);
  });

  // ---- a11y: Semantics labels present on each terminal state ----
  testWidgets('loading state exposes a Semantics label', (tester) async {
    await _pumpSearch(tester, backend: _HangingSearchBackend());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(
      _hasSemanticsLabel(tester, containing: '추천 장소를 불러오는 중'),
      isTrue,
      reason: 'loading state must expose a Semantics label',
    );
  });

  testWidgets('empty state exposes a Semantics label', (tester) async {
    await _pumpSearch(tester, backend: _EmptySearchBackend());
    await tester.pumpAndSettle();
    expect(
      _hasSemanticsLabel(tester, containing: '빈 추천'),
      isTrue,
      reason: 'empty state must expose a Semantics label',
    );
  });

  testWidgets('unavailable state exposes a Semantics label', (tester) async {
    await _pumpSearch(
      tester,
      backend: _ThrowingSearchBackend(
        const LalaApiException(
          code: 'REQUEST_TIMEOUT',
          message: 'timed out',
          statusCode: 0,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _hasSemanticsLabel(tester, containing: '서버 연결 불가'),
      isTrue,
      reason: 'unavailable must expose a label',
    );
  });

  testWidgets('error state exposes a Semantics label', (tester) async {
    await _pumpSearch(
      tester,
      backend: _ThrowingSearchBackend(
        const LalaApiException(
          code: 'HTTP_500',
          message: 'server error',
          statusCode: 500,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _hasSemanticsLabel(tester, containing: '추천 불러오기 실패'),
      isTrue,
      reason: 'error must expose a label',
    );
  });

  // ---- a11y: loaded place tile aggregates name/category/distance/region ----
  testWidgets('loaded place tile exposes a Semantics label with name/distance',
      (tester) async {
    await _pumpSearch(tester, backend: _LoadedSearchBackend());
    await tester.pumpAndSettle();

    expect(_hasSemanticsLabel(tester, containing: '행궁동 카페'), isTrue);
    expect(_hasSemanticsLabel(tester, containing: '320m'), isTrue);
  });

  // ---- a11y: minimum 44dp touch targets ----
  testWidgets('failure retry button meets the 44dp minimum touch target',
      (tester) async {
    await _pumpSearch(
      tester,
      backend: _ThrowingSearchBackend(
        const LalaApiException(
          code: 'HTTP_500',
          message: 'server error',
          statusCode: 500,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final retry = find.widgetWithText(FilledButton, '재시도');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
  });

  testWidgets('category chips meet the 44dp minimum touch target', (tester) async {
    await _pumpSearch(tester, backend: _LoadedSearchBackend());
    await tester.pumpAndSettle();

    final chip = find.byType(FilterChip).first;
    expect(chip, findsWidgets);
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
  });

  // ---- a11y: no RenderFlex overflow at 393dp on each state ----
  testWidgets('loaded, empty, unavailable, and error do not overflow at 393dp',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpSearch(tester, backend: _LoadedSearchBackend());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _pumpSearch(tester, backend: _EmptySearchBackend());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _pumpSearch(
      tester,
      backend: _ThrowingSearchBackend(
        const LalaApiException(
          code: 'NETWORK_ERROR',
          message: 'unreachable',
          statusCode: 0,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _pumpSearch(
      tester,
      backend: _ThrowingSearchBackend(
        const LalaApiException(
          code: 'HTTP_500',
          message: 'server error',
          statusCode: 500,
          retryable: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  tearDown(() {
    RegionContextStore.clear();
    OnboardingState.reset();
  });
}

// ---- helpers ----

Future<void> _pumpSearch(WidgetTester tester, {required LalaBackend backend}) {
  return tester.pumpWidget(
    MaterialApp(
      home: SearchPage(
        locationProvider: _FoundLocationProvider(),
        backendFactory: (config) => backend,
      ),
    ),
  );
}

/// 시맨틱 트리 전체에서 [containing] 부분문자열을 label 로 갖는 노드가 하나라도
/// 있는지 재귀 탐색. Semantics 라벨 존재/내용 검증에 사용.
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

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(LalaLocation(lat: 37.2636, lng: 127.0286));
}

/// getPlaces 를 영원히 대기(hanging) — loading 상태 고정용. mock 데이터 없음.
class _HangingSearchBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() =>
      Completer<LalaEnvelope<LalaPlacesResponse>>().future;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

class _LoadedSearchBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
        LalaPlacesResponse(
          count: 1,
          places: <LalaPlace>[_cafe()],
          query: const LalaPlacesQuery(
            lat: 37.2636,
            lng: 127.0286,
            radiusM: 2000,
            limit: 60,
            category: 'all',
            language: 'ko',
          ),
          source: 'db',
          locationEngine: 'postgis',
        ),
      );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

class _EmptySearchBackend implements LalaBackend {
  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async => _envelope(
        const LalaPlacesResponse(
          count: 0,
          places: <LalaPlace>[],
          query: LalaPlacesQuery(
            lat: 37.2636,
            lng: 127.0286,
            radiusM: 2000,
            limit: 60,
            category: 'all',
            language: 'ko',
          ),
          source: 'db',
          locationEngine: 'postgis',
        ),
      );

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

/// getPlaces 가 [failure] 를 throw — unavailable/error 분류 검증용.
class _ThrowingSearchBackend implements LalaBackend {
  _ThrowingSearchBackend(this.failure);

  final Object failure;

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() async {
    throw failure;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: ${invocation.memberName}');
}

LalaPlace _cafe() {
  return const LalaPlace(
    placeId: 'search-test-cafe',
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
}

LalaEnvelope<T> _envelope<T>(T data) {
  return LalaEnvelope<T>(
    ok: true,
    data: data,
    meta: const <String, dynamic>{'request_id': 'test-request-id'},
    error: null,
    statusCode: 200,
    requestId: 'test-request-id',
  );
}
