import 'package:flutter/material.dart';

import '../../../app/lala_visual_tokens.dart';
import '../../../shared/l10n/lala_copy.dart';
import 'signal_meter.dart';

/// 추천 신호 지표 그리드(C3 추출 — main.dart 의 _SignalGrid).
///
/// 점수가 null 인 신호는 가짜 fallback 수치를 진짜처럼 그리지 않고 생략한다.
/// 일반 경로에서는 점수가 집계되지 않아 네 신호 모두 null 이 될 수 있으며,
/// 이때 조작된 값을(0.82 등) 실제 점수처럼 보여선 안 된다(playbook 데이터 불변).
class SignalGrid extends StatelessWidget {
  const SignalGrid({
    super.key,
    required this.language,
    required this.localSpending,
    required this.demandDispersion,
    required this.cultureRelevance,
    required this.weatherFit,
  });

  final String language;
  final double? localSpending;
  final double? demandDispersion;
  final double? cultureRelevance;
  final double? weatherFit;

  @override
  Widget build(BuildContext context) {
    // null 신호는 미터에서 제외 — 가짜 fallback(0.82 등)을 진짜처럼 렌더하지 않기 위함.
    final localSpendingValue = localSpending;
    final demandDispersionValue = demandDispersion;
    final cultureRelevanceValue = cultureRelevance;
    final weatherFitValue = weatherFit;

    final meters = <Widget>[
      if (localSpendingValue != null)
        Expanded(
          child: SignalMeter(
            label: lalaCopyMulti(
              language,
              ko: '내국인 소비',
              en: 'Local spending',
              ja: '地元民の消費',
              zhHans: '本地人消费',
              zhHant: '本地人消費',
            ),
            value: localSpendingValue,
            color: const Color(0xFFC53030),
          ),
        ),
      if (demandDispersionValue != null)
        Expanded(
          child: SignalMeter(
            label: lalaCopyMulti(
              language,
              ko: '수요 분산',
              en: 'Demand spread',
              ja: '需要の分散',
              zhHans: '需求分散',
              zhHant: '需求分散',
            ),
            value: demandDispersionValue,
            color: const Color(0xFFF5C842),
          ),
        ),
      if (cultureRelevanceValue != null)
        Expanded(
          child: SignalMeter(
            label: lalaCopyMulti(
              language,
              ko: '문화 연계',
              en: 'Culture fit',
              ja: '文化との関連',
              zhHans: '文化关联',
              zhHant: '文化關聯',
            ),
            value: cultureRelevanceValue,
            color: const Color(0xFF2B6CB0),
          ),
        ),
      if (weatherFitValue != null)
        Expanded(
          child: SignalMeter(
            label: lalaCopyMulti(
              language,
              ko: '날씨 적합',
              en: 'Weather fit',
              ja: '天候の適合',
              zhHans: '天气适宜',
              zhHant: '天氣適宜',
            ),
            value: weatherFitValue,
            color: const Color(0xFF0F766E),
          ),
        ),
    ];

    if (meters.isEmpty) {
      // 네 신호 모두 null: 수치/막대 없이 정직한 빈 상태만 노출(조작값 금지).
      return _card(
        child: Center(
          child: Text(
            lalaCopyMulti(
              language,
              ko: '데이터 없음',
              en: 'No data yet',
              ja: 'データなし',
              zhHans: '暂无数据',
              zhHant: '暫無資料',
            ),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: LalaVisualColors.muted),
          ),
        ),
      );
    }

    return _card(child: Row(children: meters));
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: child,
    );
  }
}
