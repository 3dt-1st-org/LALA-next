// Main-shell bottom navigation bar.
// navigationShell.goBranch 로 분기를 전환한다(현재 분기 재탭 시 루트로 리셋).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/core/routing/lala_route_paths.dart';

class LalaBottomNavBar extends StatelessWidget {
  const LalaBottomNavBar({
    required this.navigationShell,
    required this.language,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final String language;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) {
        navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        );
      },
      destinations: <NavigationDestination>[
        NavigationDestination(
          key: ValueKey('nav-search'),
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: language == 'en' ? 'Search' : '검색',
        ),
        NavigationDestination(
          key: ValueKey('nav-map'),
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: language == 'en' ? 'Map' : '지도',
        ),
        NavigationDestination(
          key: ValueKey('nav-plan'),
          icon: Icon(Icons.calendar_today_outlined),
          selectedIcon: Icon(Icons.calendar_today),
          label: language == 'en' ? 'Plan' : '일정',
        ),
        NavigationDestination(
          key: const ValueKey('nav-local-signals'),
          icon: const Icon(Icons.campaign_outlined),
          selectedIcon: const Icon(Icons.campaign),
          label: language == 'en' ? 'Local Signals' : '로컬 신호',
        ),
      ],
    );
  }
}

// 경로 상수를 탭 인덱스와 짝지기 위한 헬퍼(초기 위치 검증/확장용).
const List<String> lalaTabPaths = <String>[
  LalaRoutePaths.search,
  LalaRoutePaths.mapRoute,
  LalaRoutePaths.plan,
  LalaRoutePaths.localSignals,
];
