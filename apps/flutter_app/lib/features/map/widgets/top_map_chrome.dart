import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../place/place_helpers.dart';
import 'category_chip.dart';
import 'map_round_button.dart';

String _mapCategoryLabel(String category, String language) {
  if (language != 'en') {
    return categoryFilterLabel(category, language);
  }
  return switch (category) {
    'all' => 'All',
    'attraction' => 'Sights',
    'restaurant' => 'Food',
    'event' => 'Events',
    'culture_venue' => 'Culture',
    _ => categoryFilterLabel(category, language),
  };
}

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
                        key: const ValueKey('map-category-all'),
                        label: _mapCategoryLabel('all', language),
                        width: 36,
                        active: selectedCategory == 'all',
                        color: categoryColor('all'),
                        onTap: () => onSelectCategory('all'),
                      ),
                      CategoryChip(
                        key: const ValueKey('map-category-attraction'),
                        label: _mapCategoryLabel('attraction', language),
                        width: 52,
                        active: selectedCategory == 'attraction',
                        color: categoryColor('attraction'),
                        onTap: () => onSelectCategory('attraction'),
                      ),
                      CategoryChip(
                        key: const ValueKey('map-category-restaurant'),
                        label: _mapCategoryLabel('restaurant', language),
                        width: 44,
                        active: selectedCategory == 'restaurant',
                        color: categoryColor('restaurant'),
                        onTap: () => onSelectCategory('restaurant'),
                      ),
                      CategoryChip(
                        key: const ValueKey('map-category-event'),
                        label: _mapCategoryLabel('event', language),
                        width: 52,
                        active: selectedCategory == 'event',
                        color: categoryColor('event'),
                        onTap: () => onSelectCategory('event'),
                      ),
                      CategoryChip(
                        key: const ValueKey('map-category-culture_venue'),
                        label: _mapCategoryLabel('culture_venue', language),
                        width: 56,
                        active: selectedCategory == 'culture_venue',
                        color: categoryColor('culture_venue'),
                        onTap: () => onSelectCategory('culture_venue'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              MapRoundButton(
                buttonKey: const ValueKey('settings-button'),
                tooltip: lalaCopyMulti(
      language,
      ko: '설정',
      en: 'Settings',
      ja: '設定',
      zhHans: '设置',
      zhHant: '設定',
    ),
                icon: Icons.settings,
                onPressed: onOpenSettings,
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 8),
            // 시맨틱: 지도 추천 로딩 중임을 화면 읽기 사용자에게 알린다(§13.5).
            Semantics(
              container: true,
              label: lalaCopy(
                language,
                ko: '추천 장소를 불러오는 중',
                en: 'Loading recommendations',
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
