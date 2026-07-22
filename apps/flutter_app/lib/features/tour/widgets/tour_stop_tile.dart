import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/l10n/place_labels.dart';
import '../../../shared/labels/basis_label.dart';
import '../../../shared/widgets/tiny_meta.dart';

/// 맛집 투어 정류장 타일(C3 추출 — main.dart 의 _TourStopTile).
class TourStopTile extends StatelessWidget {
  const TourStopTile({
    super.key,
    required this.index,
    required this.place,
    required this.language,
    required this.onTap,
  });

  final int index;
  final LalaPlace place;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spending = place.score?.components.localSpendingScore;
    final spendingLabel = spending == null
        ? basisLabel(
            place.score?.dataBasis ?? place.source,
            language: language,
          )
        : '${(spending.clamp(0.0, 1.0) * 100).round()}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                blurRadius: 14,
                offset: Offset(0, 7),
                color: Color(0x10000000),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFC53030).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFFC53030),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      placeDisplayName(place, language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        TinyMeta('${place.distanceM}m'),
                        TinyMeta(
                          lalaCopy(
                            language,
                            ko: '소비 신호 $spendingLabel',
                            en: 'Spend $spendingLabel',
                          ),
                        ),
                        if (place.regionKo?.trim().isNotEmpty == true ||
                            place.regionEn?.trim().isNotEmpty == true)
                          TinyMeta(placeRegionLabel(place, language)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF94A3B8),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
