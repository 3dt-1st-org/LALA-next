import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../planner_helpers.dart';
import 'planner_loading_card.dart';
import 'planner_overview_card.dart';
import 'plan_slot_tile.dart';

/// 일정 시트 본문(C3 추출 — main.dart 의 _PlannerSheetContent).
/// 개요 카드 + 슬롯 타일 목록을 구성한다.
class PlannerSheetContent extends StatelessWidget {
  const PlannerSheetContent({
    super.key,
    required this.language,
    required this.weather,
    required this.dailyPlan,
    required this.intervention,
    required this.loading,
    required this.onRegenerate,
    required this.onSelectPlace,
  });

  final String language;
  final LalaWeather? weather;
  final LalaDailyPlan? dailyPlan;
  final LalaIntervention? intervention;
  final bool loading;
  final VoidCallback onRegenerate;
  final ValueChanged<LalaPlace> onSelectPlace;

  @override
  Widget build(BuildContext context) {
    final slots = dailyPlan?.slots ?? const <LalaPlanSlot>[];
    final visibleSlots = slots
        .where((slot) => hasVisiblePlanSlot(slot, language))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlannerOverviewCard(
          language: language,
          weather: weather,
          dailyPlan: dailyPlan,
          visibleSlotCount: visibleSlots.length,
          loading: loading,
          onRegenerate: () => _confirmRegenerate(context),
        ),
        const SizedBox(height: 12),
        if (visibleSlots.isEmpty)
          PlannerLoadingCard(language: language)
        else
          ...visibleSlots
              .take(5)
              .map(
                (slot) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PlanSlotTile(
                    slot: slot,
                    language: language,
                    onSelectPlace: onSelectPlace,
                  ),
                ),
              ),
      ],
    );
  }

  Future<void> _confirmRegenerate(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            lalaCopy(language, ko: '하루 일정 재생성', en: 'Regenerate Daily Plan'),
          ),
          content: Text(
            lalaCopy(
              language,
              ko: '현재 지도의 위치를 기준으로 새 일정이 만들어집니다.',
              en: 'A new plan will be created based on the current map center.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(lalaCopy(language, ko: '취소', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(lalaCopy(language, ko: '다시 생성', en: 'Regenerate')),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      onRegenerate();
    }
  }
}
