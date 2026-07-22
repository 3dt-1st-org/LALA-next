// C3 최종: 대형 클래스/도메인 모델/상수/위젯을 app/·features/·core/ 로 이관.
// main.dart 는 thin entry point — main() + import + 테스트 호환 re-export 만 잔류.
// 본문 로직은 모두 그대로(이동만).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/lala_app.dart';

// 테스트(test/widget_test.dart)가 main.dart import 로 접근하던 public 심볼 호환용 re-export.
export 'app/lala_app.dart' show LalaApp;
export 'core/backend/lala_backend.dart'
    show LalaBackend, LalaApiBackend, LalaBackendFactory;
export 'core/config/app_config.dart' show LalaAppConfig;
export 'core/geo/geo_helpers.dart'
    show
        distanceMeters,
        loadWithSingleRetry,
        shouldReloadPlacesForMapMove,
        shouldReloadWeatherForMapMove;
export 'core/location/lala_location.dart'
    show
        GeolocatorLalaLocationProvider,
        LalaLocation,
        LalaLocationProvider,
        LalaLocationResult,
        LalaLocationResultStatus;
export 'features/map/map_helpers.dart' show clusterMapPlacesForMap;

SemanticsHandle? _webSemanticsHandle;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Force the Flutter semantics tree on web so assistive tech and browser
    // automation can inspect more than the canvas fallback placeholder.
    _webSemanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
  }
  // C2: Riverpod 루트. feature 컨트롤러(C3)가 ProviderScope 하위에서 동작한다.
  runApp(const ProviderScope(child: LalaApp()));
}
