// Main-shell bottom navigation bar.
// navigationShell.goBranch 로 분기를 전환한다(현재 분기 재탭 시 루트로 리셋).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/shared/l10n/lala_copy.dart';

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
          label: lalaCopyMulti(
            language,
            ko: '검색',
            en: 'Search',
            ja: '検索',
            zhHans: '搜索',
            zhHant: '搜尋',
          ),
        ),
        NavigationDestination(
          key: ValueKey('nav-map'),
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: lalaCopyMulti(
            language,
            ko: '지도',
            en: 'Map',
            ja: '地図',
            zhHans: '地图',
            zhHant: '地圖',
          ),
        ),
        NavigationDestination(
          key: ValueKey('nav-plan'),
          icon: Icon(Icons.calendar_today_outlined),
          selectedIcon: Icon(Icons.calendar_today),
          label: lalaCopyMulti(
            language,
            ko: '일정',
            en: 'Plan',
            ja: 'プラン',
            zhHans: '计划',
            zhHant: '計畫',
          ),
        ),
        NavigationDestination(
          key: const ValueKey('nav-local-signals'),
          icon: const Icon(Icons.campaign_outlined),
          selectedIcon: const Icon(Icons.campaign),
          label: lalaCopyMulti(
            language,
            ko: '로컬 신호',
            en: 'Local Signals',
            ja: 'ローカル信号',
            zhHans: '本地信号',
            zhHant: '在地訊號',
          ),
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
