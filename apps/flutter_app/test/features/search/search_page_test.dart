// 모바일 비주얼 계약(Slice D / S5 + remediation D): 검색 상태 검증.
// - pending: 결과 모양 중성 스켈레톤 정확히 3줄.
// - 에러 도착 후: 스켈레톤은 완전히 사라지고 재시도로 전환.
// - loaded: 스켈레톤 제거 + 실제 장소명/지역/거리/공식 이미지 슬롯.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/location/lala_location.dart';
import 'package:lala_next_app/features/place/widgets/place_thumb.dart';
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

  testWidgets(
    'search loaded renders the real place name, region, distance and official image',
    (tester) async {
      final backend = _LoadedPlacesBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: SearchPage(
            locationProvider: _FoundLocationProvider(),
            backendFactory: (config) => backend,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // loaded: 스켈레톤은 완전히 제거(에러 경로로 대체하지 않는다).
      expect(find.byKey(const ValueKey('search-skeleton-row')), findsNothing);
      // 실제 장소명/지역/거리.
      expect(find.text('행궁동 카페'), findsOneWidget);
      expect(find.text('수원'), findsWidgets);
      expect(find.text('320m'), findsOneWidget);
      // 공식 이미지 슬롯(빌려온/발명 이미지가 아님).
      expect(find.byType(PlaceThumb), findsOneWidget);
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

/// 실제 장소(공식 이미지 포함)를 반환하는 테스트용 백엔드.
class _LoadedPlacesBackend implements LalaBackend {
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
      throw UnimplementedError('not used in search: ${invocation.memberName}');
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
    imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/photo.jpg',
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
