import 'package:flutter/material.dart';

import '../../../manual_location_options.dart';
import '../../../shared/l10n/lala_copy.dart';
import 'manual_location_empty_state.dart';
import 'manual_location_province_chip.dart';
import 'manual_location_section_label.dart';
import 'manual_location_tile.dart';

/// 수동 지역 선택 시트(C3 추출 — main.dart 의 _ManualLocationSheet).
/// 시/도 필터 + 검색 + 빠른 선택/전체 목록을 제공한다.
class ManualLocationSheet extends StatefulWidget {
  const ManualLocationSheet({super.key, required this.language});

  final String language;

  @override
  State<ManualLocationSheet> createState() => _ManualLocationSheetState();
}

class _ManualLocationSheetState extends State<ManualLocationSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedProvinceId = 'all';
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final title = lalaCopyMulti(
      language,
      ko: '지역 선택',
      en: 'Choose area',
      ja: '地域を選択',
      zhHans: '选择地区',
      zhHant: '選擇地區',
    );
    final closeLabel = lalaCopyMulti(
      language,
      ko: '닫기',
      en: 'Close',
      ja: '閉じる',
      zhHans: '关闭',
      zhHant: '關閉',
    );
    final allLabel = lalaCopyMulti(
      language,
      ko: '전국',
      en: 'All',
      ja: 'すべて',
      zhHans: '全部',
      zhHant: '全部',
    );
    final searchHint = lalaCopyMulti(
      language,
      ko: '시군구 또는 시도 검색',
      en: 'Search city or province',
      ja: '市区郡または道府県を検索',
      zhHans: '搜索城市或省份',
      zhHant: '搜尋城市或省份',
    );
    final quickLabel = lalaCopyMulti(
      language,
      ko: '빠른 선택',
      en: 'Quick picks',
      ja: 'クイック選択',
      zhHans: '快速选择',
      zhHant: '快速選擇',
    );
    final resultLabel = lalaCopyMulti(
      language,
      ko: '선택 가능한 지역',
      en: 'Available areas',
      ja: '選択できる地域',
      zhHans: '可选择地区',
      zhHant: '可選擇地區',
    );
    final normalizedQuery = _query.trim();
    ManualLocationProvince? selectedProvince;
    for (final province in manualLocationProvinces) {
      if (province.id == _selectedProvinceId) {
        selectedProvince = province;
        break;
      }
    }
    final featuredIds = featuredManualLocationOptions
        .map((option) => option.id)
        .toSet();
    final showFeatured =
        normalizedQuery.isEmpty && _selectedProvinceId == 'all';
    final filteredOptions = manualLocationOptions
        .where((option) {
          if (showFeatured && featuredIds.contains(option.id)) {
            return false;
          }
          if (_selectedProvinceId != 'all' &&
              option.provinceId != _selectedProvinceId) {
            return false;
          }
          return option.matches(normalizedQuery);
        })
        .toList(growable: false);
    final headerCount = _selectedProvinceId == 'all'
        ? manualLocationOptions.length
        : selectedProvince?.options.length ?? filteredOptions.length;
    final countText = lalaCopyMulti(
      language,
      ko: '$headerCount개 지역',
      en: '$headerCount areas',
      ja: '$headerCount地域',
      zhHans: '$headerCount 个地区',
      zhHant: '$headerCount 個地區',
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.74,
      minChildSize: 0.48,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF5F5F5),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                offset: Offset(0, -10),
                color: Color(0x26000000),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC8D0D9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: closeLabel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A202C),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          countText,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('manual-location-search'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: lalaCopyMulti(
                            language,
                            ko: '검색어 지우기',
                            en: 'Clear',
                            ja: 'クリア',
                            zhHans: '清除',
                            zhHant: '清除',
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF2B6CB0),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: manualLocationProvinces.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ManualLocationProvinceChip(
                        key: const ValueKey('manual-location-province-all'),
                        label: allLabel,
                        selected: _selectedProvinceId == 'all',
                        onSelected: () =>
                            setState(() => _selectedProvinceId = 'all'),
                      );
                    }
                    final province = manualLocationProvinces[index - 1];
                    return ManualLocationProvinceChip(
                      key: ValueKey('manual-location-province-${province.id}'),
                      label: province.shortLabel(language),
                      selected: _selectedProvinceId == province.id,
                      onSelected: () =>
                          setState(() => _selectedProvinceId = province.id),
                    );
                  },
                ),
              ),
              if (showFeatured) ...[
                const SizedBox(height: 18),
                ManualLocationSectionLabel(quickLabel),
                const SizedBox(height: 8),
                for (final option in featuredManualLocationOptions) ...[
                  ManualLocationTile(
                    option: option,
                    language: language,
                    onSelected: () => Navigator.of(context).pop(option),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 10),
              ManualLocationSectionLabel(
                selectedProvince?.label(language) ?? resultLabel,
              ),
              const SizedBox(height: 8),
              if (filteredOptions.isEmpty)
                ManualLocationEmptyState(language: language)
              else
                for (final option in filteredOptions) ...[
                  ManualLocationTile(
                    option: option,
                    language: language,
                    onSelected: () => Navigator.of(context).pop(option),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        );
      },
    );
  }
}
