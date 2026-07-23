// 모바일 비주얼 계약(Slice B / 03-acceptance O4): S3 읽기전용 지도 미리보기 래퍼 검증.
// - 기존 kakao_map_view 조건부 import 경계를 그대로 사용한다(손그림/대체 타일 아님).
// - 라이브 키가 없으면 경계가 내는 명시적 폴백(blocked) 상태로 렌더된다.
// - 읽기 전용(IgnorePointer) 이며 좌표가 없으면 핀을 발명하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/onboarding/presentation/widgets/location_map_preview.dart';

void main() {
  testWidgets(
    'no key renders the explicit blocked/fallback state through the kakao boundary',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: LocationMapPreview(
              kakaoJavascriptKey: '',
              centerLat: 37.2636,
              centerLng: 127.0286,
            ),
          ),
        ),
      );
      await tester.pump();

      // 경계(buildKakaoMapView)를 거쳐 폴백 메시지로 떨어진다.
      expect(find.text('현재 지도를 표시할 수 없습니다.'), findsOneWidget);
      // 읽기 전용: 제스처 차단.
      expect(find.byType(IgnorePointer), findsWidgets);
      // 좌표가 없으면 발명된 매장/핀이 없어야 한다.
      expect(find.text('로컬 맛집'), findsNothing);
      expect(find.text('문화 행사'), findsNothing);
    },
  );
}
