// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';


class LocationStartPromptOverlay extends StatelessWidget {
  const LocationStartPromptOverlay({super.key,
    required this.language,
    required this.onStartLocation,
  });

  final String language;
  final VoidCallback onStartLocation;

  @override
  Widget build(BuildContext context) {
    // V6: ko 이외 로케일은 EN 카피 체인을 따른다.
    final isEnglish = normalizeLalaLanguage(language) != 'ko';
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.86),
      child: SafeArea(
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 430),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE1ECF8)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 34,
                  offset: Offset(0, 18),
                  color: Color(0x22000000),
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
                    Icons.my_location_outlined,
                    color: Color(0xFF2B6CB0),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  isEnglish
                      ? lalaCopyMulti(
                          language,
                          ko: '현재 위치에서 시작할게요',
                          en: 'Start from here',
                          ja: 'ここから始めます',
                          zhHans: '从这里开始',
                          zhHant: '從這裡開始',
                        )
                      : '현재 위치에서 시작할게요',
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
                          ko: '주변 장소와 날씨, 로컬 동선을 불러오기 위해 대략적인 위치를 확인합니다.',
                          en: 'LALA uses your approximate location to load nearby places, weather, and local routes.',
                          ja: '近くのスポット・気象・ローカルルートを読み込むため、おおよその位置情報を確認します。',
                          zhHans: '为加载附近的地点、天气和本地路线，需要确认大致位置。',
                          zhHant: '為載入附近的地點、天氣和在地路線，需要確認大致位置。',
                        )
                      : '주변 장소와 날씨, 로컬 동선을 불러오기 위해 대략적인 위치를 확인합니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('location-start-confirm'),
                  onPressed: onStartLocation,
                  icon: const Icon(Icons.my_location),
                  label: Text(
                    isEnglish
                        ? lalaCopyMulti(
                            language,
                            ko: '현재 위치 사용',
                            en: 'Use my location',
                            ja: '現在地を使う',
                            zhHans: '使用当前位置',
                            zhHant: '使用目前位置',
                          )
                        : '현재 위치 사용',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: const Color(0xFF2B6CB0),
                    foregroundColor: Colors.white,
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
