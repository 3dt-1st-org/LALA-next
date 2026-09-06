// 다섯 로케일 reason 카피(유계 고정 토큰 매핑) 검증.
// 계약: 서버 /places language 는 ko/en 이고 클라이언트는 방문객 로케일을 en 로
// 요청하므로(lala_copy.dart apiRequestLanguage), 방문객 화면의 reason 은 고정 EN
// 세그먼트다. placeReasonText/placeReasonText(language) 는 그 유한 세그먼트만
// 로케일 고정 문구로 바꾼다 — 원본(지명/출처 기관명)은 보존하고, 운영 상태
// 주장 토큰(영업중/Open now)은 매핑에 없어 검증된 주장으로 번역되지 않는다.
// ko/en 은 서버 원문을 바이트 단위로 그대로(기존 동작 보존).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/place/place_helpers.dart';
import 'package:lala_next_app/features/place/widgets/place_reason_freshness.dart';

LalaPlace _place({String? reason}) => LalaPlace(
  placeId: 'p1',
  name: 'Suwon Museum',
  nameKo: '수원 박물관',
  nameEn: 'Suwon Museum',
  category: 'culture_venue',
  lat: 37.26,
  lng: 127.03,
  address: 'Yeongtong-gu, Suwon',
  distanceM: 300,
  source: 'db',
  upstreamSource: 'tour_api',
  reason: reason,
);

void main() {
  group('localizePlaceReasonText (bounded fixed-token mapping)', () {
    test('maps every fixed EN segment to each visitor locale', () {
      const reason =
          'Warm weather · Active local spending · Ongoing event · Nearby · '
          'Korea Tourism Organization data';
      expect(localizePlaceReasonText(reason, 'ja'), isNot(reason));
      expect(
        localizePlaceReasonText(reason, 'ja'),
        '暖かい天気 · 地元の消費が活発 · 開催中のイベント · 近く · '
        'Korea Tourism Organization data',
      );
      expect(
        localizePlaceReasonText(reason, 'zh-Hans'),
        '温暖天气 · 本地消费活跃 · 进行中的活动 · 近距离 · '
        'Korea Tourism Organization data',
      );
      expect(
        localizePlaceReasonText(reason, 'zh-Hant'),
        '溫暖天氣 · 本地消費活躍 · 進行中的活動 · 近距離 · '
        'Korea Tourism Organization data',
      );
    });

    test('maps the full bounded segment set', () {
      const segments = [
        'Indoor-friendly',
        'Cold weather',
        'Cool weather',
        'Warm weather',
        'Hot weather',
        'Active local spending',
        'Ongoing event',
        'Linked event',
        'Nearby',
      ];
      for (final segment in segments) {
        for (final locale in ['ja', 'zh-Hans', 'zh-Hant']) {
          final mapped = localizePlaceReasonText(segment, locale);
          expect(mapped, isNot(segment), reason: '$segment @ $locale');
          expect(mapped, isNotEmpty);
        }
      }
    });

    test('ko/en return the server string byte-identical', () {
      const reason = '선선한 날씨 · 로컬 소비 활발 · 근접 · 한국관광공사 데이터';
      expect(localizePlaceReasonText(reason, 'ko'), reason);
      // EN 서버 문자열은 매핑을 거치지 않고 그대로(SSOT).
      const enReason = 'Cool weather · Active local spending · Nearby';
      expect(localizePlaceReasonText(enReason, 'en'), enReason);
      // BCP-47 접두어 정규화 후에도 동일.
      expect(localizePlaceReasonText(enReason, 'zh-CN'), isNot(enReason));
    });

    test('preserves unmapped segments (proper names, source citations)', () {
      const reason =
          'Nearby · Korea Tourism Organization data · Hwaseong Haenggung';
      expect(
        localizePlaceReasonText(reason, 'ja'),
        '近く · Korea Tourism Organization data · Hwaseong Haenggung',
      );
    });

    test('does not translate a legacy Open now token into a claim', () {
      // 구버전 서버 잔여 토큰은 매핑되지 않고 EN 폴백으로 남는다 — 검증된
      // 운영 주장으로 번역하지 않는다(신규 서버는 운영 세그먼트를 만들지 않음).
      const reason = 'Open now · Nearby';
      expect(localizePlaceReasonText(reason, 'ja'), 'Open now · 近く');
    });
  });

  group('placeReasonText language gating', () {
    test('null/empty reason stays null for every locale', () {
      expect(placeReasonText(_place(), 'ja'), isNull);
      expect(placeReasonText(_place(reason: ''), 'zh-Hans'), isNull);
      expect(placeReasonText(_place(), 'ko'), isNull);
    });

    test('omitted language returns the server string unchanged', () {
      // 하위 호환: language 를 모르는 호출측은 원문 그대로(정직한 EN 폴백).
      const enReason = 'Warm weather · Nearby';
      expect(placeReasonText(_place(reason: enReason)), enReason);
    });

    test('ko/en return server copy; visitor locales map fixed tokens', () {
      const enReason = 'Indoor-friendly · Nearby';
      expect(placeReasonText(_place(reason: enReason), 'en'), enReason);
      expect(placeReasonText(_place(reason: enReason), 'ko'), enReason);
      expect(placeReasonText(_place(reason: enReason), 'ja'), '屋内活動に適した · 近く');
    });
  });

  group('PlaceReasonLine widget', () {
    Future<void> pumpChild(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      await tester.pumpAndSettle();
    }

    testWidgets('renders localized visible text for visitor locales', (
      tester,
    ) async {
      const reason = 'Warm weather · Nearby · Korea Tourism Organization data';
      await pumpChild(
        tester,
        SingleChildScrollView(
          child: PlaceReasonLine(
            place: _place(reason: reason),
            language: 'ja',
          ),
        ),
      );
      expect(
        find.text('暖かい天気 · 近く · Korea Tourism Organization data'),
        findsOneWidget,
      );
      // 방문객 로케일에 한국어 코드포인트 노출 금지.
      expect(
        find.textContaining(RegExp('[\u{AC00}-\u{D7AF}]', unicode: true)),
        findsNothing,
      );
      // 매핑 안 된 EN 폴백(구 토큰)은 번역되어 보이지 않는다.
      await pumpChild(
        tester,
        SingleChildScrollView(
          child: PlaceReasonLine(
            place: _place(reason: 'Open now'),
            language: 'zh-Hans',
          ),
        ),
      );
      expect(find.text('Open now'), findsOneWidget);
    });

    testWidgets('ko/en render the server string unchanged', (tester) async {
      const enReason = 'Cool weather · Nearby';
      await pumpChild(
        tester,
        SingleChildScrollView(
          child: PlaceReasonLine(
            place: _place(reason: enReason),
            language: 'en',
          ),
        ),
      );
      expect(find.text(enReason), findsOneWidget);
    });

    testWidgets('null reason renders nothing for every locale', (tester) async {
      for (final locale in ['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant']) {
        await pumpChild(
          tester,
          PlaceReasonLine(place: _place(), language: locale),
        );
        expect(find.byType(Text), findsNothing);
      }
    });

    testWidgets('long localized reason stays on one line without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const reason =
          'Warm weather · Active local spending · Ongoing event · Nearby · '
          'Korea Tourism Organization data · '
          'Suwon Hwaseong Cultural Festival Extra Long Tail Segment';
      await pumpChild(
        tester,
        PlaceReasonLine(
          place: _place(reason: reason),
          language: 'ja',
        ),
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byType(Text).first);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('placeCardSemanticsLabel carries localized reason', () {
    test('semantics label uses the mapped reason for visitor locales', () {
      const reason = 'Nearby · Korea Tourism Organization data';
      final label = placeCardSemanticsLabel(_place(reason: reason), 'ja');
      expect(label, contains('近く'));
      expect(label, contains('Korea Tourism Organization data'));
      // EN 세미antics 는 서버 원문.
      final enLabel = placeCardSemanticsLabel(_place(reason: reason), 'en');
      expect(enLabel, contains('Nearby'));
    });
  });
}
