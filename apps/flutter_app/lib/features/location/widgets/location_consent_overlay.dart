// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
// C3 최종: main.dart 에서 이관. V6: 방문객 로케일 번역 추가.
import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

class LocationConsentOverlay extends StatelessWidget {
  const LocationConsentOverlay({
    super.key,
    required this.language,
    required this.onOpenSettings,
    required this.onRetryLocation,
  });

  final String language;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetryLocation;

  @override
  Widget build(BuildContext context) {
    // V6: ko 이외 로케일은 EN 카피 체인을 따린다.
    final isEnglish = normalizeLalaLanguage(language) != 'ko';
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.34),
      child: SafeArea(
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 32,
                  offset: Offset(0, 16),
                  color: Color(0x33000000),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FB),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.location_off_outlined,
                    color: Color(0xFF2B6CB0),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isEnglish
                      ? lalaCopyMulti(
                          language,
                          ko: '위치기반 추천이 꺼져 있어요',
                          en: 'Location consent is off',
                          ja: '位置情報に基づくおすすめがオフです',
                          zhHans: '基于位置的推荐已关闭',
                          zhHant: '基於位置的推薦已關閉',
                        )
                      : '위치기반 추천이 꺼져 있어요',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEnglish
                      ? lalaCopyMulti(
                          language,
                          ko: 'LALA는 주변 문화·날씨·지역 소비 신호를 연결하기 위해 대략적인 위치 동의가 필요합니다.',
                          en: 'LALA uses your approximate location only to recommend nearby public culture, weather, and local spending signals.',
                          ja: 'LALAは近くの文化・気象・地域消費のシグナルをつなぐため、おおよその位置情報の同意が必要です。',
                          zhHans: 'LALA 需要大致位置授权，以连接附近的文化、天气和本地消费信号。',
                          zhHant: 'LALA 需要大致位置授權，以連結附近的文化、天氣和在地消費訊號。',
                        )
                      : 'LALA는 주변 문화·날씨·지역 소비 신호를 연결하기 위해 대략적인 위치 동의가 필요합니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                  label: Text(
                    isEnglish
                        ? lalaCopyMulti(
                            language,
                            ko: '위치 동의 켜기',
                            en: 'Turn on location',
                            ja: '位置情報をオンにする',
                            zhHans: '开启定位',
                            zhHant: '開啟定位',
                          )
                        : '위치 동의 켜기',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('location-consent-retry'),
                  onPressed: onRetryLocation,
                  icon: const Icon(Icons.my_location_outlined),
                  label: Text(
                    isEnglish
                        ? lalaCopyMulti(
                            language,
                            ko: '다시 확인',
                            en: 'Retry location',
                            ja: '再試行',
                            zhHans: '重试',
                            zhHant: '重試',
                          )
                        : '다시 확인',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: const Color(0xFF2B6CB0),
                    side: const BorderSide(color: Color(0xFFB9D4F3)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
