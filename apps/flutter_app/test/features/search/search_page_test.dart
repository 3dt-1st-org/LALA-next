// 모바일 비주얼 계약(Slice D / S5): 검색 진행 중 상태 검증.
// - pending: 결과 모양 중성 스켈레톤 정확히 3줄.
// - 에러 도착 후: 스켈레톤은 완전히 사라지고 재시도로 전환(loaded/empty 도 동일 분기).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/features/search/presentation/pages/search_page.dart';

void main() {
  testWidgets(
    'search pending shows exactly three neutral skeleton rows then removes them',
    (tester) async {
      final backend = _PendingPlacesBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _FoundLocationProvider(),
            // _load 가 백엔드를 재생성하므로 동일 인스턴스를 반환한다.
            backendFactory: (config) => backend,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      // 진행 중(getPlaces 미해결): 결과 모양 스켈레톤 3줄.
      expect(
        find.byKey(const ValueKey('search-skeleton-row')),
        findsNWidgets(3),
      );

      // 에러 도착 → 스켈레톤 제거, 재시도 노출.
      backend.completeError();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-skeleton-row')), findsNothing);
      expect(find.text('재시도'), findsOneWidget);
    },
  );
}

class _FoundLocationProvider implements LalaLocationProvider {
  @override
  Future<LalaLocationResult> requestCurrentLocation() async =>
      const LalaLocationResult.found(
        LalaLocation(lat: 37.2636, lng: 127.0286),
      );
}

/// getPlaces 를 Completer 로 지연시키는 테스트용 백엔드. pending 관측 후 에러로 종료.
class _PendingPlacesBackend implements LalaBackend {
  final Completer<LalaEnvelope<LalaPlacesResponse>> _placesCompleter =
      Completer<LalaEnvelope<LalaPlacesResponse>>();

  void completeError() =>
      _placesCompleter.completeError(StateError('search backend unavailable'));

  @override
  Future<LalaEnvelope<LalaPlacesResponse>> getPlaces() =>
      _placesCompleter.future;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in search: ${invocation.memberName}');
}
