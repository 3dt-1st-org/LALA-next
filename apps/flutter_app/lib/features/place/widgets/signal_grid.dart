import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';
import 'signal_meter.dart';

/// 추천 신호 지표 그리드(C3 추출 — main.dart 의 _SignalGrid).
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SignalMeter(
              label: lalaCopy(language, ko: '내국인 소비', en: 'Local spending'),
              value: localSpending ?? 0.82,
              color: const Color(0xFFC53030),
            ),
          ),
          Expanded(
            child: SignalMeter(
              label: lalaCopy(language, ko: '수요 분산', en: 'Demand spread'),
              value: demandDispersion ?? 0.78,
              color: const Color(0xFFF5C842),
            ),
          ),
          Expanded(
            child: SignalMeter(
              label: lalaCopy(language, ko: '문화 연계', en: 'Culture fit'),
              value: cultureRelevance ?? 0.91,
              color: const Color(0xFF2B6CB0),
            ),
          ),
          Expanded(
            child: SignalMeter(
              label: lalaCopy(language, ko: '날씨 적합', en: 'Weather fit'),
              value: weatherFit ?? 0.74,
              color: const Color(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
  }
}
