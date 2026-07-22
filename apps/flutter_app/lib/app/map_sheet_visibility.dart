// ONMU P0: 지도 분기 인-바디 시트(detail/planner/weather/tour) 활성화 상태를 쉘과 공유.
// 시트가 열리면 하단 네비게이션 바를 숨겨 시트가 전체 영역을 쓰도록 한다
// (모달 시트와 동일하게 네비게이션 바 위까지 덮어 콘텐츠가 가려지지 않게 함).
import 'package:flutter/foundation.dart';

/// 지도 분기에 시트가 활성화되어 있으면 true. Dashboard.build 이후 갱신, LalaMainShell 이 구독.
final ValueNotifier<bool> lalaMapSheetActive = ValueNotifier<bool>(false);
