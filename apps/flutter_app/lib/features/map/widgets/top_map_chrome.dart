import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../place/place_helpers.dart';
import 'category_chip.dart';
import 'map_round_button.dart';

/// 지도 상단 크롬(카테고리 필터 + 설정 버튼 + 로딩 바)(C3 추출 — main.dart 의 _TopMapChrome).
class TopMapChrome extends StatelessWidget {
  const TopMapChrome({
    super.key,
    required this.loading,
    required this.language,
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.onOpenSettings,
  });

  final bool loading;
  final String language;
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    // 모바일 비주얼 계약 remediation C1: 카테고리 행 상단 12, 좌우 12dp.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      CategoryChip(
                        label: categoryFilterLabel('all', language),
                        active: selectedCategory == 'all',
                        color: const Color(0xFF1A202C),
                        onTap: () => onSelectCategory('all'),
                      ),
                      CategoryChip(
                        label: categoryFilterLabel('attraction', language),
                        active: selectedCategory == 'attraction',
                        color: const Color(0xFFC53030),
                        onTap: () => onSelectCategory('attraction'),
                      ),
                      CategoryChip(
                        label: categoryFilterLabel('restaurant', language),
                        active: selectedCategory == 'restaurant',
                        color: const Color(0xFFF5C842),
                        onTap: () => onSelectCategory('restaurant'),
                      ),
                      CategoryChip(
                        label: categoryFilterLabel('event', language),
                        active: selectedCategory == 'event',
                        color: const Color(0xFF2B6CB0),
                        onTap: () => onSelectCategory('event'),
                      ),
                      CategoryChip(
                        label: categoryFilterLabel('culture_venue', language),
                        active: selectedCategory == 'culture_venue',
                        color: const Color(0xFF0F766E),
                        onTap: () => onSelectCategory('culture_venue'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              MapRoundButton(
                buttonKey: const ValueKey('settings-button'),
                tooltip: lalaCopy(language, ko: '설정', en: 'Settings'),
                icon: Icons.settings,
                onPressed: onOpenSettings,
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ],
      ),
    );
  }
}
