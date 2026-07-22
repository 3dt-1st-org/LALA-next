import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 개인정보 처리안내 상세 시트(C3 추출 — main.dart 의 _PrivacyDetailsSheet).
class PrivacyDetailsSheet extends StatelessWidget {
  const PrivacyDetailsSheet({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    final closeLabel = lalaCopy(language, ko: '닫기', en: 'Close');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.54,
      minChildSize: 0.34,
      maxChildSize: 0.82,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                offset: Offset(0, -10),
                color: Color(0x24000000),
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
                  Expanded(
                    child: Text(
                      lalaCopy(language, ko: '개인정보 동의 안내', en: 'Privacy notice'),
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: closeLabel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A202C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PrivacyDetailRow(
                icon: Icons.my_location_outlined,
                title: lalaCopy(language, ko: '위치 기반 추천', en: 'Location context'),
                body: lalaCopy(
                  language,
                  ko: '현재 화면의 지도 중심과 반경을 사용해 가까운 장소, 날씨, 일정을 계산합니다.',
                  en: 'LALA uses the current map center and radius for nearby places, weather, and plans.',
                ),
              ),
              PrivacyDetailRow(
                icon: Icons.public_outlined,
                title: lalaCopy(
                  language,
                  ko: '공식 데이터 우선',
                  en: 'Official data first',
                ),
                body: lalaCopy(
                  language,
                  ko: '관광·문화·날씨·지역 소비 신호는 공식 기관 데이터와 공개 데이터를 우선 사용합니다.',
                  en: 'Tourism, culture, weather, and local signals prioritize official and public datasets.',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 개인정보 상세 행(C3 추출 — main.dart 의 _PrivacyDetailRow).
class PrivacyDetailRow extends StatelessWidget {
  const PrivacyDetailRow({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2B6CB0), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 개인정보 상세 시트 표시 헬퍼(C3 추출 — main.dart 의 _showPrivacyDetailsSheet).
Future<void> showPrivacyDetailsSheet(
  BuildContext context,
  String language,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => PrivacyDetailsSheet(language: language),
  );
}
