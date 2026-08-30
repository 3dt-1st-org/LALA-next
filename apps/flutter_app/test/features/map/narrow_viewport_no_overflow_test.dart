// P6F §13.5 + responsive contract: narrow-viewport no-overflow gate.
// Tests text-heavy interactive widgets at 360dp and 393dp base viewport with
// deliberately long input strings, asserting NO RenderFlex overflow occurs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
import 'package:lala_next_app/features/docent/widgets/dock_docent_preview.dart';
import 'package:lala_next_app/features/map/widgets/category_chip.dart';
import 'package:lala_next_app/features/map/widgets/map_bottom_dock.dart';
import 'package:lala_next_app/features/map/widgets/map_place_carousel_overlay.dart';
import 'package:lala_next_app/features/place/widgets/map_rail_place_card.dart';
import 'package:lala_next_app/features/place/widgets/recommended_place_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Helper to create a test LalaPlace with long text values.
LalaPlace _longPlace({
  String name = '아주아주긴이름의카페와레스토랑이있는장소입니다더길게테스트',
  String region = '수원시팔달구매산로일가아주오래된긴동네이름입니다',
  String address = '경기도 수원시 팔달구 매산로1가 아주오래된긴주소이름동 건물층호',
  int distanceM = 1234,
  String? reason,
  String? freshness,
}) {
  return LalaPlace(
    placeId: 'long-place',
    name: name,
    nameKo: name,
    category: 'restaurant',
    lat: 37.28,
    lng: 127.01,
    address: address,
    distanceM: distanceM,
    source: 'db',
    imageUrl: 'https://tong.visitkorea.or.kr/cms/resource/x.jpg',
    regionKo: region,
    regionEn: region,
    reason: reason,
    freshness: freshness,
  );
}

/// V1-RC3 overflow gate: 독 날씨 줄 바인딩용 실측 날씨 픽스처(긴 dust 라벨 유발).
LalaWeather _dockWeather() {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: '23',
    icon: 'partly-cloudy',
    dust: LalaDust(
      pm10: '30',
      pm25: '25',
      grade: 'normal',
      gradeKo: '보통',
      pm10Grade: 'normal',
      pm10GradeKo: '보통',
      pm25Grade: 'good',
      pm25GradeKo: '좋음',
    ),
    forecast: const <LalaForecastItem>[],
    outdoorStatus: 'normal',
    force: false,
    source: 'kma_ultra_srt_ncst',
    location: 'Suwon',
    recordTime: '2026-07-24T09:00:00+09:00',
    locationMatch: true,
  );
}

/// Helper to set viewport and capture overflow errors.
///
/// Returns a function that restores the original FlutterError.onError.
Future<void> _pumpAndCaptureOverflow(
  WidgetTester tester,
  double viewportWidth, {
  required Widget widget,
  double dpi = 3.0,
}) async {
  // Set narrow viewport
  tester.view.physicalSize = Size(viewportWidth * dpi, 852 * dpi);
  tester.view.devicePixelRatio = dpi;
  addTearDown(tester.view.reset);

  // Capture Flutter errors during pump
  final errors = <FlutterErrorDetails>[];
  final originalOnError = FlutterError.onError;
  FlutterError.onError = errors.add;

  try {
    await tester.pumpWidget(_wrap(widget));
    await tester.pumpAndSettle();

    // Assert no overflow errors
    final overflowErrors = errors.where(
      (e) => e.exceptionAsString().contains('overflowed'),
    );
    expect(
      overflowErrors,
      isEmpty,
      reason:
          'RenderFlex overflow detected at ${viewportWidth.toInt()}dp viewport',
    );
  } finally {
    FlutterError.onError = originalOnError;
  }
}

/// V1 three-signals(§3/§6) Lane 3: reason 이 정식 6세그먼트로 풍부해진 현실 최장 케이스.
/// 정준 순서 — 영업중(S0) · 날씨 밴드(D3) · 로컬 소비 활발(D1) · 진행 중인 행사(D4) ·
/// 근접 · 출처 구문(D2). ellipsis 가 꼬리만 자르므로 신규 overflow 벡터가 없다(§6).
const _enrichedSixSegmentReason =
    '영업중 · 선선한 날씨 · 로컬 소비 활발 · 진행 중인 행사 · 근접 · 한국관광공사 데이터';

void main() {
  group('MapRailPlaceCard narrow viewport no overflow', () {
    testWidgets('360dp with very long place name, region, address', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: MapRailPlaceCard(
          place: _longPlace(
            name: '아주아주긴이름의카페와레스토랑이있는장소입니다더길게테스트하기위해서더많은글자를넣습니다',
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다더길게만듭니다',
            address: '경기도 수원시 팔달구 매산로1가 아주오래된긴주소이름동 건물층호 더많은주소',
          ),
          language: 'ko',
          selected: false,
          compact: true,
        ),
      );
    });

    testWidgets('393dp base viewport with long text', (tester) async {
      await _pumpAndCaptureOverflow(
        tester,
        393,
        widget: MapRailPlaceCard(
          place: _longPlace(
            name: '긴카페이름테스트용문자열여기에더많은글자를계속추가합니다',
            region: '수원시팔달구매산로일가동네이름',
            address: '경기도 수원시 팔달구 매산로1가',
          ),
          language: 'ko',
          selected: true,
          compact: true,
        ),
      );
    });

    // V1-RC2: 새로 바인딩된 reason 줄이 compact carousel card 에서 overflow 를
    // 발생시키지 않는다(PlaceReasonLine 의 1줄 ellipsis).
    testWidgets('360dp with long reason line does not overflow', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: MapRailPlaceCard(
          place: _longPlace(
            reason: '영업중 · 실내활동 적합 · 근접 · 공식 데이터 · 아주긴추가이유텍스트',
            freshness: '방금 전',
          ),
          language: 'ko',
          selected: false,
          compact: true,
        ),
      );
    });

    // V1-RC4 §13.2/§13.5: category 라벨이 메타 줄에 병치되고 freshness 줄이 추가된 상태에서
    // 가장 긴 category 라벨(Restaurant)·긴 region·reason·freshness 가 좁은 뷰포트에서
    // overflow 를 발생시키지 않는다(메타 줄 1줄 ellipsis).
    testWidgets('360dp with longest category label + freshness no overflow', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: MapRailPlaceCard(
          place: _longPlace(
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다더길게만듭니다',
            reason: '영업중 · 실내활동 적합 · 근접 · 공식 데이터 · 아주긴추가이유텍스트',
            freshness: '방금 전 데이터 신선도 표시용 약간 긴 문자열입니다',
          ),
          language: 'en', // 'Restaurant' = longest category display name
          selected: false,
          compact: true,
        ),
      );
    });

    testWidgets('393dp with longest category label + freshness no overflow', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        393,
        widget: MapRailPlaceCard(
          place: _longPlace(
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다더길게만듭니다',
            reason: '영업중 · 실내활동 적합 · 근접 · 공식 데이터 · 아주긴추가이유텍스트',
            freshness: '방금 전 데이터 신선도 표시용 약간 긴 문자열입니다',
          ),
          language: 'en',
          selected: true,
          compact: true,
        ),
      );
    });
  });

  group('CategoryChip narrow viewport no overflow', () {
    testWidgets('360dp with very long label', (tester) async {
      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: CategoryChip(
          label: '아주긴카테고리라벨이여기에들어갑니다더많은글자추가테스트',
          active: false,
          color: LalaVisualColors.restaurant,
          onTap: () {},
        ),
      );
    });

    testWidgets('393dp base viewport with long label', (tester) async {
      await _pumpAndCaptureOverflow(
        tester,
        393,
        widget: CategoryChip(
          label: '긴카테고리라벨테스트용',
          active: true,
          color: LalaVisualColors.restaurant,
          onTap: () {},
        ),
      );
    });
  });

  group('DockDocentPreview narrow viewport no overflow', () {
    testWidgets('360dp with long docent summary text', (tester) async {
      final longScript = '''
        이 장소에 대한 아주 긴 도슨트 설명입니다. 첫 번째 문장이 매우 길게 이어지고 있습니다.
        두 번째 문장도 상세한 설명을 위해서 많은 내용을 포함하고 있습니다.
        세 번째 문장에서는 장소의 역사와 특징에 대해 더 자세히 설명합니다.
      ''';

      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: SizedBox(
          width: 360,
          child: DockDocentPreview(
            place: _longPlace(),
            language: 'ko',
            script: longScript,
            action: '이 경로를 따라 걸어보세요. 매우 긴 경로 설명이 여기에 포함됩니다.',
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            onAddToPlan: () {},
            onOpenDetail: () {},
          ),
        ),
      );
    });

    testWidgets('393dp base viewport with long script', (tester) async {
      await _pumpAndCaptureOverflow(
        tester,
        393,
        widget: SizedBox(
          width: 393,
          child: DockDocentPreview(
            place: _longPlace(),
            language: 'ko',
            script: '긴 도슨트 설명입니다. 이 장소의 역사와 특징에 대해 상세히 설명합니다.',
            action: '긴 경로 설명이 포함된 행동 제안입니다.',
            audioLoading: false,
            audioError: null,
            docentAudio: null,
            canFetchAudio: false,
            onFetchAudio: () {},
            onAddToPlan: () {},
            onOpenDetail: () {},
          ),
        ),
      );
    });
  });

  group('MapPlaceCarouselOverlay narrow viewport no overflow', () {
    testWidgets('360dp with long place count and source text', (tester) async {
      final longPlaces = List.generate(
        5,
        (i) => _longPlace(
          name: '매우긴장소이름$i번째입니다추가글자더넣기',
          region: '긴지역이름$i',
          address: '매우긴주소$i번째건물',
        ),
      );

      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: SizedBox(
          width: 360,
          child: MapPlaceCarouselOverlay(
            places: longPlaces,
            source: '매우긴출처이름입니다추가정보포함',
            language: 'ko',
            selectedPlaceId: null,
            explicitSelectedPlaceId: null,
            expanded: true,
            compact: true,
            onSelectPlace: (_) {},
            onReselectSelectedPlace: () {},
            onToggleExpanded: () {},
          ),
        ),
      );
    });

    testWidgets('393dp base viewport with multiple places', (tester) async {
      await _pumpAndCaptureOverflow(
        tester,
        393,
        widget: SizedBox(
          width: 393,
          child: MapPlaceCarouselOverlay(
            places: [
              _longPlace(),
              _longPlace(name: '또다른긴이름'),
            ],
            source: '긴출처',
            language: 'ko',
            selectedPlaceId: null,
            explicitSelectedPlaceId: null,
            expanded: true,
            compact: true,
            onSelectPlace: (_) {},
            onReselectSelectedPlace: () {},
            onToggleExpanded: () {},
          ),
        ),
      );
    });
  });

  // V1-RC3: 독 날씨 요약·출처 1줄(PlaceWeatherSourceLine)이 좁은 뷰포트에서
  // RenderFlex overflow 를 발생시키지 않는다(1줄 ellipsis + SingleChildScrollView).
  group('MapBottomDock narrow viewport no overflow (V1-RC3 weather line)', () {
    testWidgets('360dp with weather line + long reason/dust', (tester) async {
      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: SizedBox(
          width: 360,
          child: MapBottomDock(
            isWide: false,
            places: <LalaPlace>[_dockPlace()],
            source: 'db',
            weather: _dockWeather(),
            dataAsOf: '2026-06-19T02:24:44.557686+00:00',
            topPlace: _dockPlace(),
            uiLanguage: 'ko',
            height: 196,
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
          ),
        ),
      );
    });

    testWidgets('393dp base viewport with weather line', (tester) async {
      await _pumpAndCaptureOverflow(
        tester,
        393,
        widget: SizedBox(
          width: 393,
          child: MapBottomDock(
            isWide: false,
            places: <LalaPlace>[_dockPlace()],
            source: 'db',
            weather: _dockWeather(),
            dataAsOf: '2026-06-19T02:24:44.557686+00:00',
            topPlace: _dockPlace(),
            uiLanguage: 'ko',
            height: 196,
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
          ),
        ),
      );
    });

    testWidgets('360dp collapsed summary with very long place identity', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: SizedBox(
          width: 360,
          child: MapBottomDock(
            isWide: false,
            places: <LalaPlace>[_dockPlace()],
            source: 'db',
            weather: _dockWeather(),
            dataAsOf: '2026-06-19T02:24:44.557686+00:00',
            topPlace: _dockPlace(),
            uiLanguage: 'ko',
            height: 96,
            expanded: false,
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
            onToggleExpanded: () {},
          ),
        ),
      );
    });
  });

  // V1 three-signals §6/§8 (Lane 3 overflow gate): reason 이 정식 6세그먼트(정준 순서,
  // 현실 최장)로 풍부해져도 PlaceReasonLine(Row>Expanded>Text maxLines:1 ellipsis) 가
  // 좁은 뷰포트에서 RenderFlex overflow 를 발생시키지 않는다. MapRailPlaceCard +
  // RecommendedPlaceCard 양 표면 × 360/393dp — 계약 §8 presentation 게이트.
  group('V1 three-signals six-segment reason no overflow '
      '(MapRailPlaceCard + RecommendedPlaceCard)', () {
    testWidgets('MapRailPlaceCard 360dp with full six-segment reason', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: MapRailPlaceCard(
          place: _longPlace(
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다더길게만듭니다',
            reason: _enrichedSixSegmentReason,
            freshness: '방금 전 데이터 신선도 표시용 약간 긴 문자열입니다',
          ),
          language: 'ko',
          selected: false,
          compact: true,
        ),
      );
      // §6/§8: 현실 최장 reason 도 예외 없이 ellipsis truncation 만 발생한다.
      expect(tester.takeException(), isNull);
    });

    testWidgets('MapRailPlaceCard 393dp with full six-segment reason', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        393,
        widget: MapRailPlaceCard(
          place: _longPlace(
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다더길게만듭니다',
            reason: _enrichedSixSegmentReason,
            freshness: '방금 전 데이터 신선도 표시용 약간 긴 문자열입니다',
          ),
          language: 'ko',
          selected: true,
          compact: true,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('RecommendedPlaceCard 360dp with full six-segment reason', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        360,
        widget: RecommendedPlaceCard(
          place: _longPlace(
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다더길게만듭니다',
            reason: _enrichedSixSegmentReason,
            // freshness 생략: 본 게이트는 reason 줄(§6/§8)이 대상. RecommendedPlaceCard
            // 메타 Row(line 54)는 Expanded/ellipsis 미보호라 긴 freshness 에 별도 overflow
            // 벡터가 있으나, reason 과 무관한 사전 취약점(본 레인 범위 밖).
          ),
          language: 'ko',
          selected: false,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('RecommendedPlaceCard 393dp with full six-segment reason', (
      tester,
    ) async {
      await _pumpAndCaptureOverflow(
        tester,
        393,
        widget: RecommendedPlaceCard(
          place: _longPlace(
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다더길게만듭니다',
            reason: _enrichedSixSegmentReason,
            // freshness 생략(위 360dp 케이스 주석 참조) — reason 줄 게이트만 격리.
          ),
          language: 'ko',
          selected: true,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// V1-RC3 dock overflow fixture: 긴 지역/이름/사유로 Wrap·reason·weather 줄을 동시에 압박.
LalaPlace _dockPlace() {
  return _longPlace(
    name: '아주아주긴이름의카페와레스토랑이있는장소입니다더길게테스트하기위한이름',
    region: '수원시팔달구매산로일가아주오래된긴동네이름입니다',
    address: '경기도 수원시 팔달구 매산로1가 아주오래된긴주소이름동',
    reason: '영업중 · 실내활동 적합 · 근접 · 공식 데이터 · 아주긴추가이유텍스트',
    freshness: '방금 전',
  );
}
