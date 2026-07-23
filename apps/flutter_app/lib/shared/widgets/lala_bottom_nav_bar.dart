// ONMU P0: 하단 3-탭 네비게이션 바.
// navigationShell.goBranch 로 분기를 전환한다(현재 분기 재탭 시 루트로 리셋).
// 라벨은 앱 SSOT 언어(OnboardingState.language)를 따라 검색/지도/일정(Search/Map/Plan).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_metrics.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

class LalaBottomNavBar extends StatelessWidget {
  const LalaBottomNavBar({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    // 온보딩/스플래시/시작/언어 페이지와 동일한 SSOT 언어로 라벨을 표시한다.
    final language = OnboardingState.language;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: <NavigationDestination>[
          _destination(
            'nav-search',
            Icons.search_outlined,
            Icons.search,
            lalaCopy(language, ko: '검색', en: 'Search'),
          ),
          _destination(
            'nav-map',
            Icons.map_outlined,
            Icons.map,
            lalaCopy(language, ko: '지도', en: 'Map'),
          ),
          _destination(
            'nav-plan',
            Icons.calendar_today_outlined,
            Icons.calendar_today,
            lalaCopy(language, ko: '일정', en: 'Plan'),
          ),
        ],
      ),
    );
  }

  NavigationDestination _destination(
    String keyValue,
    IconData icon,
    IconData selectedIcon,
    String label,
  ) {
    return NavigationDestination(
      key: ValueKey(keyValue),
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon),
      label: label,
    );
  }
}

// 경로 상수를 탭 인덱스와 짝지기 위한 헬퍼(초기 위치 검증/확장용).
const List<String> lalaTabPaths = <String>[
  LalaRoutePaths.search,
  LalaRoutePaths.mapRoute,
  LalaRoutePaths.plan,
];

// 하단탭 라벨 타이포(컴팩트 12sp). NavigationBarTheme 에서 사용.
TextStyle lalaNavLabelStyle(BuildContext context) =>
    TextStyle(fontSize: LalaMetrics.navLabelSp, fontWeight: FontWeight.w800);
