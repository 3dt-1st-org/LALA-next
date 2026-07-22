// ONMU P0: 메인 쉘 — StatefulShellRoute 의 분기(body) + 하단 네비게이션 바를 조합.
// 각 분기(검색/지도/플랜)의 페이지가 navigationShell 안에서 독립적으로 보존된다.
// 지도 분기에 인-바디 시트가 열려 있으면 하단 바를 숨겨 시트가 전체 영역을 쓰도록 한다.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/map_sheet_visibility.dart';
import 'package:lala_next_app/shared/widgets/lala_bottom_nav_bar.dart';

class LalaMainShell extends StatelessWidget {
  const LalaMainShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: lalaMapSheetActive,
        builder: (BuildContext context, bool sheetActive, Widget? _) {
          if (sheetActive) {
            // 시트가 네비게이션 바 위까지 덮도록 영역을 비운다.
            return const SizedBox.shrink();
          }
          return LalaBottomNavBar(navigationShell: navigationShell);
        },
      ),
    );
  }
}
