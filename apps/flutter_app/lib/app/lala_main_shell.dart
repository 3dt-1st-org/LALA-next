// ONMU P0: 메인 쉘 — StatefulShellRoute 의 분기(body) + 하단 네비게이션 바를 조합.
// 각 분기(검색/지도/플랜)의 페이지가 navigationShell 안에서 독립적으로 보존된다.
// 지도 분기에 인-바디 시트가 열려 있으면 하단 바를 숨겨 시트가 전체 영역을 쓰도록 한다.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/app/map_sheet_visibility.dart';
import 'package:lala_next_app/core/routing/lala_route_paths.dart';
import 'package:lala_next_app/features/docent/experience/docent_experience_controller.dart';
import 'package:lala_next_app/features/docent/experience/docent_mini_player.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/shared/widgets/lala_bottom_nav_bar.dart';

class LalaMainShell extends StatelessWidget {
  const LalaMainShell({
    required this.navigationShell,
    required this.docentExperienceController,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  /// 이슈 #120 §6.2: 미니플레이어가 노출하는 단일 도슨트 경험 세션 소유자.
  final DocentExperienceController docentExperienceController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: lalaMapSheetActive,
        builder: (BuildContext context, bool sheetActive, Widget? _) {
          if (sheetActive) {
            // 시트가 네비게이션 바 위까지 덮도록 영역을 비운다.
            // 미니플레이어도 같이 숨긴다(§6.2: 시트가 열리면 하단 체인 전체를 내준다).
            return const SizedBox.shrink();
          }
          return ValueListenableBuilder<String>(
            valueListenable: OnboardingState.languageListenable,
            builder: (BuildContext context, String language, Widget? _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 도슨트 미니플레이어 — 5-탭 하단 바 바로 위에 상주(idle 시 자체 축소).
                  DocentMiniPlayer(
                    controller: docentExperienceController,
                    language: language,
                    onOpenPlayer: () =>
                        context.push(LalaRoutePaths.docentPlayer),
                  ),
                  LalaBottomNavBar(
                    navigationShell: navigationShell,
                    language: language,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
