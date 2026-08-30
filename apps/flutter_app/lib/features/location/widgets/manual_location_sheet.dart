import 'package:flutter/material.dart';

import '../../../app/lala_visual_tokens.dart';
import '../../../core/location/region_context.dart';
import '../../../manual_location_options.dart';
import '../../../shared/l10n/lala_copy.dart';
import 'manual_location_empty_state.dart';
import 'manual_location_province_chip.dart';
import 'manual_location_section_label.dart';
import 'manual_location_tile.dart';

/// 시/도 필터와 실제 지역 선택을 분리한 수동 지역 선택 시트.
///
/// 필터 chip은 목록 범위만 바꾸고, 지역 행 탭은 pending selection만 갱신한다.
/// 하단 CTA를 눌러야 선택값을 반환하므로 탐색 context가 우발적으로 바뀌지 않는다.
class ManualLocationSheet extends StatefulWidget {
  const ManualLocationSheet({
    super.key,
    required this.language,
    this.activeRegionId,
    this.activeRegionLabel,
  });

  final String language;

  /// 현재 적용된 수동 지역 ID. current/default context는 null이다.
  final String? activeRegionId;

  /// 시트 상단에 표시할 실제 탐색 context label.
  final String? activeRegionLabel;

  @override
  State<ManualLocationSheet> createState() => _ManualLocationSheetState();
}

class _ManualLocationSheetState extends State<ManualLocationSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedProvinceId = 'all';
  String _query = '';
  ManualLocationOption? _pendingOption;

  @override
  void initState() {
    super.initState();
    final stored = RegionContextStore.current;
    final activeId =
        widget.activeRegionId ??
        (stored?.source == RegionSource.manual ? stored?.regionId : null);
    _pendingOption = _findOption(activeId);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ManualLocationOption? _findOption(String? id) {
    if (id == null) {
      return null;
    }
    for (final option in manualLocationOptions) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }

  void _choose(ManualLocationOption option) {
    setState(() => _pendingOption = option);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final stored = RegionContextStore.current;
    final activeRegionLabel =
        widget.activeRegionLabel ?? stored?.label(language);
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
      ko: '전체 지역 보기',
      en: 'View all areas',
      ja: 'すべての地域',
      zhHans: '查看全部地区',
      zhHant: '查看全部地區',
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
    final currentRegionTitle = lalaCopyMulti(
      language,
      ko: '현재 탐색 지역',
      en: 'Current exploration region',
      ja: '現在の探索地域',
      zhHans: '当前探索地区',
      zhHant: '目前探索地區',
    );
    final selectedRegionTitle = lalaCopyMulti(
      language,
      ko: '선택한 지역',
      en: 'Selected area',
      ja: '選択した地域',
      zhHans: '已选地区',
      zhHant: '已選地區',
    );
    final applyLabel = lalaCopyMulti(
      language,
      ko: '이 지역으로 탐색',
      en: 'Explore this area',
      ja: 'この地域を探索',
      zhHans: '探索此地区',
      zhHant: '探索此地區',
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
      initialChildSize: 0.82,
      minChildSize: 0.56,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: LalaVisualColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                offset: Offset(0, -10),
                color: Color(0x26000000),
              ),
            ],
          ),
          child: Stack(
            children: [
              ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 128),
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: LalaVisualColors.line,
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
                          backgroundColor: LalaVisualColors.card,
                          foregroundColor: LalaVisualColors.ink,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: LalaVisualColors.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              countText,
                              style: const TextStyle(
                                color: LalaVisualColors.muted,
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
                  if (activeRegionLabel != null &&
                      activeRegionLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      key: const ValueKey('manual-location-current-region'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: LalaVisualColors.primarySoft,
                        borderRadius: BorderRadius.circular(
                          LalaVisualTokens.controlRadius,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.explore_rounded,
                            size: 20,
                            color: LalaVisualColors.primaryBlue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentRegionTitle,
                                  style: const TextStyle(
                                    color: LalaVisualColors.muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activeRegionLabel,
                                  key: const ValueKey(
                                    'manual-location-current-region-label',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: LalaVisualColors.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
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
                      fillColor: LalaVisualColors.card,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: LalaVisualColors.line,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: LalaVisualColors.line,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: LalaVisualColors.primaryBlue,
                          width: 1.5,
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
                          key: ValueKey(
                            'manual-location-province-${province.id}',
                          ),
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
                        selected: _pendingOption?.id == option.id,
                        onSelected: () => _choose(option),
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
                        selected: _pendingOption?.id == option.id,
                        onSelected: () => _choose(option),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: LalaVisualColors.card,
                    border: Border(
                      top: BorderSide(color: LalaVisualColors.line),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_pendingOption != null) ...[
                          Text(
                            '$selectedRegionTitle · ${_pendingOption!.fullLabel(language)}',
                            key: const ValueKey(
                              'manual-location-pending-label',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: LalaVisualColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 7),
                        ],
                        FilledButton.icon(
                          key: const ValueKey('manual-location-apply'),
                          onPressed: _pendingOption == null
                              ? null
                              : () => Navigator.of(context).pop(_pendingOption),
                          icon: const Icon(Icons.explore_rounded, size: 19),
                          label: Text(applyLabel),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(
                              LalaVisualTokens.actionHeight,
                            ),
                            backgroundColor: LalaVisualColors.primaryBlue,
                            foregroundColor: LalaVisualColors.card,
                            disabledBackgroundColor:
                                LalaVisualColors.disabledFill,
                            disabledForegroundColor:
                                LalaVisualColors.disabledInk,
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                LalaVisualTokens.controlRadius,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
