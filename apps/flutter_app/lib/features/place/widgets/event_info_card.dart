import 'package:flutter/material.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../../shared/widgets/inline_icon_text.dart';
import '../place_helpers.dart';
import 'event_status_pill.dart';

/// 행사 정보 카드(C3 추출 — main.dart 의 _EventInfoCard).
class EventInfoCard extends StatelessWidget {
  const EventInfoCard({super.key, required this.place, required this.language});

  final LalaPlace place;
  final String language;

  @override
  Widget build(BuildContext context) {
    final isOngoing = place.isOngoing != false;
    final dateText = eventDateRangeText(place, language);
    final eventUrl = validEventUri(place.eventUrl);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E3F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.event_available_outlined,
                  color: Color(0xFF1A202C),
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  lalaCopy(language, ko: '행사 정보', en: 'Event info'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              EventStatusPill(isOngoing: isOngoing, language: language),
            ],
          ),
          if (dateText != null) ...[
            const SizedBox(height: 10),
            InlineIconText(
              icon: Icons.calendar_month_outlined,
              label: dateText,
            ),
          ],
          if (place.isApproximateLocation == true) ...[
            const SizedBox(height: 8),
            InlineIconText(
              icon: Icons.near_me_disabled_outlined,
              label: lalaCopy(
                language,
                ko: '정확한 좌표가 없어 시 중심 위치로 표시돼요',
                en: 'Exact coordinates are unavailable, so the city center is shown.',
              ),
            ),
          ],
          if (eventUrl != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () =>
                    launchUrl(eventUrl, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  lalaCopy(language, ko: '행사 상세 보기', en: 'Open event details'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2B6CB0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
