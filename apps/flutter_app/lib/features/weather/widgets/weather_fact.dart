import 'package:flutter/material.dart';

import '../../../shared/widgets/compact_info_tile.dart';

/// 날씨 시트의 팩트 아이템(C3 추출 — main.dart 의 _WeatherFact).
class WeatherFact extends StatelessWidget {
  const WeatherFact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: CompactInfoTile(
        icon: Icons.check_circle_outline,
        label: label,
        value: value,
      ),
    );
  }
}
