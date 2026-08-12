// V1-RC RecommendedPlaceCard §13.5 overflow gate.
//
// 메타데이터 Row(CategoryBadge · 거리 · freshness) 의 overflow 를 격리 검증한다.
// 카드 폭은 고정(270 with image / 232 without)이라 메타 Row 가 좁고, 모든 자식이
// inflexible 했던 기존 구조에서는 긴 freshness 라벨이 Row 를 넘치게 했다(사진 중심
// 카드라 폭은 유지해야 한다).
//
// Fix: freshness(가변 폭 후미 세그먼트)를 Flexible + maxLines:1 + ellipsis 로 감싸서
// Row 의 남은 폭을 흡수한다. 카테고리 배지/거리는 고정 폭으로 항상 보이고, 신선도가
// 먼저 잘린다(신선도가 가장 가변·덜 중요 세그먼트).
//
// Vectors: (a) long freshness label, (b) longest category badge display name
// (EN "Attraction"), (c) long place name. Viewports 360dp + 393dp. Card variants
// hasImage=true (270px) 와 hasImage=false (232px) 모두 커버.
//
// 참고(정직한 범위 표기): EN "Attraction" 배지는 실측 ~128.5px. hasImage=true 카드의
// 메타 Row 폭은 270 - 28(padding) - 2(border) - 10(gap) - 76(thumb) = 154px 로, 배지
// 단독(128.5) + 거리(57.5) + gap(16) = 202px > 154px 이다. 따라서 "Attraction" 배지는
// hasImage=true 표면에서 배지 자체가 컬럼을 넘는다 — 이는 카드 폭/썸네일 레이아웃 변경
// 또는 CategoryBadge 의 ellipsis 지원(본 레인 소유 밖)이 필요한 카드-레벨 레이아웃
// 한계다. 본 게이트는 (b) longest category 를 hasImage=false(232px, 메타 폭 ~206px)에서
// 검증한다 — 해당 표면에서 가장 긴 배지가 거리/신선도와 함께 no-overflow 로 렌더된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/place/widgets/recommended_place_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// 테스트용 LalaPlace 빌더. [hasImage] 로 카드 폭(270/232)을 결정한다.
LalaPlace _place({
  required bool hasImage,
  String name = '테스트 장소',
  String category = 'restaurant',
  String freshness = '방금 전',
  String region = '수원시 팔달구',
  String address = '경기도 수원시 팔달구 매산로',
  int distanceM = 1234,
}) {
  return LalaPlace(
    placeId: 'rc-place-$category-$hasImage',
    name: name,
    nameKo: name,
    category: category,
    lat: 37.28,
    lng: 127.01,
    address: address,
    distanceM: distanceM,
    source: 'db',
    imageUrl: hasImage
        ? 'https://tong.visitkorea.or.kr/cms/resource/x.jpg'
        : null,
    regionKo: region,
    regionEn: region,
    freshness: freshness,
  );
}

/// 좁은 뷰포트에서 위젯을 pump 하고 RenderFlex overflow 예외가 없는지 단언한다.
/// 기존 narrow_viewport_no_overflow_test 의 패턴을 그대로 미러한다.
Future<void> _pumpNoOverflow(
  WidgetTester tester,
  double viewportWidth, {
  required Widget widget,
  double dpi = 3.0,
}) async {
  tester.view.physicalSize = Size(viewportWidth * dpi, 852 * dpi);
  tester.view.devicePixelRatio = dpi;
  addTearDown(tester.view.reset);

  final errors = <FlutterErrorDetails>[];
  final originalOnError = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await tester.pumpWidget(_wrap(widget));
    await tester.pumpAndSettle();
    final overflowErrors = errors.where(
      (e) => e.exceptionAsString().contains('overflowed'),
    );
    expect(
      overflowErrors,
      isEmpty,
      reason: 'RenderFlex overflow detected at ${viewportWidth.toInt()}dp',
    );
  } finally {
    FlutterError.onError = originalOnError;
  }
}

/// 메타 Row 의 주 overflow 벡터 — 가변 폭 freshness 라벨(충분히 길게).
const _longFreshness =
    '방금 전 데이터가 갱신된 매우 신선한 장소 데이터입니다 긴 신선도 라벨 텍스트 오버플로우 검증용 문자열';

void main() {
  // 결합 최대 압박 행렬: 긴 이름 + 긴 region/address + 긴 freshness — [360, 393] × 두 카드 변형.
  // hasImage=false(232px) 에서는 가장 긴 카테고리 배지(EN "Attraction")까지 함께 눌러
  // (b) 벡터를 커버한다. hasImage=true(270px) 에서는 컬럼이 좁아 "Attraction" 배지가
  // 단독으로도 넘으므로(카드-레벨 한계, 파일 헤더 참조) restaurant/EN("Food") 로 대체해
  // (a)/(c) 벡터를 썸네일 표면에서 검증한다.
  for (final viewport in const <double>[360, 393]) {
    testWidgets('no overflow ${viewport.toInt()}dp hasImage=false '
        '(long freshness + longest category + long name)', (tester) async {
      await _pumpNoOverflow(
        tester,
        viewport,
        widget: RecommendedPlaceCard(
          place: _place(
            hasImage: false,
            name: '아주아주긴이름의카페와레스토랑이있는장소입니다더길게테스트하기위한이름',
            category: 'attraction', // EN "Attraction" = longest badge label
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다',
            address: '경기도 수원시 팔달구 매산로1가 아주오래된긴주소이름동',
            freshness: _longFreshness,
          ),
          language: 'en',
          selected: false,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow ${viewport.toInt()}dp hasImage=true '
        '(long freshness + long name, restaurant/EN badge)', (tester) async {
      await _pumpNoOverflow(
        tester,
        viewport,
        widget: RecommendedPlaceCard(
          place: _place(
            hasImage: true,
            name: '아주아주긴이름의카페와레스토랑이있는장소입니다더길게테스트하기위한이름',
            category: 'restaurant', // EN "Food" — 썸네일 컬럼(154px)에 들어오는 배지
            region: '수원시팔달구매산로일가아주오래된긴동네이름입니다',
            address: '경기도 수원시 팔달구 매산로1가 아주오래된긴주소이름동',
            freshness: _longFreshness,
          ),
          language: 'en',
          selected: true,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  // (a) long freshness 단독 — 가장 좁은 360dp / hasImage=true(썸네일 표면).
  testWidgets('no overflow 360dp hasImage=true with long freshness only', (
    tester,
  ) async {
    await _pumpNoOverflow(
      tester,
      360,
      widget: RecommendedPlaceCard(
        place: _place(hasImage: true, freshness: _longFreshness),
        language: 'ko',
        selected: false,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // (b) 가장 긴 카테고리 배지 표시명(EN "Attraction") 단독 — hasImage=false(232px)
  // 표면. 이 변형에서만 가장 긴 배지가 거리/신선도와 함께 no-overflow 로 렌더된다.
  for (final viewport in const <double>[360, 393]) {
    testWidgets(
      'no overflow ${viewport.toInt()}dp hasImage=false with longest category badge',
      (tester) async {
        await _pumpNoOverflow(
          tester,
          viewport,
          widget: RecommendedPlaceCard(
            place: _place(
              hasImage: false,
              category:
                  'attraction', // "Attraction" = longest EN category badge
              freshness: _longFreshness,
            ),
            language: 'en',
            selected: true,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // (c) 긴 장소명 단독 — 360dp / hasImage=true(이름 Text 는 maxLines:2+ellipsis).
  testWidgets('no overflow 360dp hasImage=true with long place name', (
    tester,
  ) async {
    await _pumpNoOverflow(
      tester,
      360,
      widget: RecommendedPlaceCard(
        place: _place(
          hasImage: true,
          name: '아주아주긴이름의카페와레스토랑이있는장소입니다더길게테스트하기위한이름입니다계속늘리기',
        ),
        language: 'ko',
        selected: false,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
