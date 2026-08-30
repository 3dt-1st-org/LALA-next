// Main-shell bottom navigation bar.
// navigationShell.goBranch 로 분기를 전환한다(현재 분기 재탭 시 루트로 리셋).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/lala_visual_tokens.dart';
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
    final systemBottomInset = MediaQuery.paddingOf(context).bottom;
    final compactBottomInset =
        systemBottomInset > LalaVisualTokens.bottomNavMaxSafeInset
        ? LalaVisualTokens.bottomNavMaxSafeInset
        : systemBottomInset;

    return DecoratedBox(
      key: const ValueKey('lala-bottom-nav-surface'),
      decoration: const BoxDecoration(
        color: LalaVisualColors.card,
        border: Border(top: BorderSide(color: LalaVisualColors.primarySoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: LalaVisualColors.card,
                elevation: 0,
                indicatorColor: LalaVisualColors.primarySoft,
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final isSelected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    color: isSelected
                        ? LalaVisualColors.primaryBlue
                        : LalaVisualColors.ink,
                    size: isSelected ? 24 : 23,
                  );
                }),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final isSelected = states.contains(WidgetState.selected);
                  return TextStyle(
                    color: isSelected
                        ? LalaVisualColors.primaryBlue
                        : LalaVisualColors.ink,
                    fontSize: LalaVisualTokens.bottomNavSize,
                    height:
                        LalaVisualTokens.bottomNavLineHeight /
                        LalaVisualTokens.bottomNavSize,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: 0,
                  );
                }),
              ),
              child: NavigationBar(
                height: LalaVisualTokens.bottomNavHeight,
                backgroundColor: LalaVisualColors.card,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                elevation: 0,
                indicatorColor: LalaVisualColors.primarySoft,
                indicatorShape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
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
              ),
            ),
          ),
          SizedBox(
            key: const ValueKey('lala-bottom-nav-safe-inset'),
            width: double.infinity,
            height: compactBottomInset,
          ),
        ],
      ),
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
