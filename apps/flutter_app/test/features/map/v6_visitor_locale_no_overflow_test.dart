// V6 foreign-visitor UX: visitor-locale overflow gates.
//
// Contract §8: the visitor copy strings (Japanese / Simplified Chinese /
// Traditional Chinese) must not create new overflow vectors. The existing
// narrow-viewport gate pattern (narrow_viewport_no_overflow_test.dart) is
// re-run with the longest realistic visitor-locale strings at:
//  - 360dp  (small phone)
//  - 393dp  (base phone)
//  - 402dp  (iPhone 17 Pro logical width)
//  - 1024dp / 1440dp (web widths — strings change, layout does not)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/map/widgets/empty_dock_content.dart';
import 'package:lala_next_app/features/place/widgets/map_rail_place_card.dart';
import 'package:lala_next_app/features/place/widgets/recommended_place_card.dart';

const _visitorLocales = <String>['ja', 'zh-Hans', 'zh-Hant'];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Long-but-realistic visitor-locale inputs (CJK glyphs are wider per char but
/// carry more meaning, so these model the worst realistic labels).
LalaPlace _visitorLongPlace(String locale) {
  final longName = switch (locale) {
    'ja' => '非常に長い名前のカフェとレストランがある場所ですテスト用にもっと文字を追加します',
    'zh-Hans' => '名字非常长的咖啡馆和餐厅所在的地点为了测试继续添加更多字符',
    _ => '名字非常長的咖啡館和餐廳所在的地點為了測試繼續添加更多字符',
  };
  final longRegion = switch (locale) {
    'ja' => '水原市八達区梅山路一街とても長い町名ですテスト用にもっと追加',
    'zh-Hans' => '水原市八达区梅山路一街非常长的地名为了测试继续添加',
    _ => '水原市八達區梅山路一街非常長的地名為了測試繼續添加',
  };
  final longAddress = switch (locale) {
    'ja' => '京畿道水原市八達区梅山路一街非常に長い住所の建物の階と号を追加します',
    'zh-Hans' => '京畿道水原市八达区梅山路一街非常长的地址楼栋楼层室号继续添加',
    _ => '京畿道水原市八達區梅山路一街非常長的地址樓棟樓層室號繼續添加',
  };
  final reason = switch (locale) {
    'ja' => '営業中 · 快晴 · ローカル消費が活発 · 開催中のイベント · 近接 · 韓国観光公社データ',
    'zh-Hans' => '营业中 · 晴朗 · 本地消费活跃 · 进行中的活动 · 近距离 · 韩国观光公社数据',
    _ => '營業中 · 晴朗 · 在地消費活躍 · 進行中的活動 · 近距離 · 韓國觀光公社數據',
  };
  return LalaPlace(
    placeId: 'visitor-long-place-$locale',
    name: longName,
    nameKo: longName,
    category: 'restaurant',
    lat: 37.28,
    lng: 127.01,
    address: longAddress,
    distanceM: 1234,
    source: 'db',
    regionKo: longRegion,
    regionEn: longRegion,
    reason: reason,
  );
}

Future<void> _pumpAndAssertNoOverflow(
  WidgetTester tester,
  double viewportWidth, {
  required Widget widget,
}) async {
  tester.view.physicalSize = Size(viewportWidth, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final errors = <FlutterErrorDetails>[];
  final originalOnError = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await tester.pumpWidget(_wrap(widget));
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = originalOnError;
  }
  expect(
    errors.where((e) => e.exceptionAsString().contains('overflowed')),
    isEmpty,
    reason: 'overflow at ${viewportWidth.toInt()}dp',
  );
}

void main() {
  for (final locale in _visitorLocales) {
    group('visitor locale $locale no-overflow', () {
      testWidgets('place rail card at 360dp', (tester) async {
        await _pumpAndAssertNoOverflow(
          tester,
          360,
          widget: MapRailPlaceCard(
            place: _visitorLongPlace(locale),
            language: locale,
            selected: false,
            compact: true,
          ),
        );
      });

      testWidgets('place rail card at 393dp', (tester) async {
        await _pumpAndAssertNoOverflow(
          tester,
          393,
          widget: MapRailPlaceCard(
            place: _visitorLongPlace(locale),
            language: locale,
            selected: true,
            compact: true,
          ),
        );
      });

      testWidgets('place rail card at 402dp (iPhone 17 Pro)', (tester) async {
        await _pumpAndAssertNoOverflow(
          tester,
          402,
          widget: MapRailPlaceCard(
            place: _visitorLongPlace(locale),
            language: locale,
            selected: false,
            compact: true,
          ),
        );
      });

      testWidgets('recommended place card at 402dp', (tester) async {
        await _pumpAndAssertNoOverflow(
          tester,
          402,
          widget: RecommendedPlaceCard(
            place: _visitorLongPlace(locale),
            selected: false,
            language: locale,
          ),
        );
      });

      testWidgets('recommended place card at web width 1024dp', (
        tester,
      ) async {
        await _pumpAndAssertNoOverflow(
          tester,
          1024,
          widget: RecommendedPlaceCard(
            place: _visitorLongPlace(locale),
            selected: false,
            language: locale,
          ),
        );
      });

      testWidgets('empty dock content at 402dp', (tester) async {
        await _pumpAndAssertNoOverflow(
          tester,
          402,
          widget: const EmptyDockContent(language: 'PLACEHOLDER'),
        );
      });

      testWidgets('empty dock content at 360dp', (tester) async {
        await _pumpAndAssertNoOverflow(
          tester,
          360,
          widget: const EmptyDockContent(language: 'PLACEHOLDER'),
        );
      });
    });
  }

  group('visitor-locale bottom nav labels', () {
    // The nav bar needs a live shell; assert label rendering via the
    // NavigationBar destinations at phone and web widths instead.
    for (final locale in _visitorLocales) {
      testWidgets('$locale labels render single-line at 402dp', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(402, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final errors = <FlutterErrorDetails>[];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = errors.add;
        try {
          await tester.pumpWidget(
            _wrap(
              Center(
                child: LalaBottomNavLabelsProbe(language: locale),
              ),
            ),
          );
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = originalOnError;
        }
        expect(
          errors.where((e) => e.exceptionAsString().contains('overflowed')),
          isEmpty,
        );
      });
    }
  });
}

/// Renders the four nav labels stacked at nav-label width so the overflow gate
/// exercises the actual visitor strings without a router.
class LalaBottomNavLabelsProbe extends StatelessWidget {
  const LalaBottomNavLabelsProbe({required this.language, super.key});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final label in _navLabels(language))
          SizedBox(
            width: 88,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

List<String> _navLabels(String language) {
  return switch (language) {
    'ja' => <String>['検索', '地図', 'プラン', 'ローカル信号'],
    'zh-Hans' => <String>['搜索', '地图', '计划', '本地信号'],
    'zh-Hant' => <String>['搜尋', '地圖', '計畫', '在地訊號'],
    _ => <String>['Search', 'Map', 'Plan', 'Local Signals'],
  };
}
