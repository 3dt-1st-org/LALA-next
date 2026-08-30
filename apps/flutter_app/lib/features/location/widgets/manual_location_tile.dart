import 'package:flutter/material.dart';

import '../../../app/lala_visual_tokens.dart';
import '../../../manual_location_options.dart';

/// 수동 지역 선택 시트의 지역 옵션 타일(C3 추출 — main.dart 의 _ManualLocationTile).
class ManualLocationTile extends StatelessWidget {
  const ManualLocationTile({
    super.key,
    required this.option,
    required this.language,
    required this.onSelected,
    this.selected = false,
  });

  final ManualLocationOption option;
  final String language;
  final VoidCallback onSelected;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: option.fullLabel(language),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
        child: InkWell(
          key: ValueKey('manual-location-option-${option.id}'),
          borderRadius: BorderRadius.circular(LalaVisualTokens.controlRadius),
          onTap: onSelected,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? LalaVisualColors.primarySoft
                  : LalaVisualColors.card,
              borderRadius: BorderRadius.circular(
                LalaVisualTokens.controlRadius,
              ),
              border: Border.all(
                color: selected
                    ? LalaVisualColors.primaryBlue
                    : LalaVisualColors.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? LalaVisualColors.primaryBlue
                        : LalaVisualColors.primarySoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.location_on_outlined,
                    color: selected
                        ? LalaVisualColors.card
                        : LalaVisualColors.primaryBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label(language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LalaVisualColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        option.provinceLabel(language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LalaVisualColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? LalaVisualColors.primaryBlue
                      : LalaVisualColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
