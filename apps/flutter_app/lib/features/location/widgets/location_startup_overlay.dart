// C3 최종: main.dart 에서 이관. 본문 불변(이동만).
import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';


class LocationStartupOverlay extends StatelessWidget {
  const LocationStartupOverlay({super.key,required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    // V6: ko 이외 로케일은 EN 카피 체인을 따른다.
    final isEnglish = normalizeLalaLanguage(language) != 'ko';
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.82),
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
                          ko: '현재 위치로 시작할게요',
                          en: 'Start from your current location',
                          ja: '現在地から始めます',
                          zhHans: '从当前位置开始',
                          zhHant: '從目前位置開始',
                        )
                      : '현재 위치로 시작할게요',
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
                          ko: '브라우저의 위치 권한을 허용하면 주변 문화·날씨·로컬 경험 추천을 바로 불러옵니다.',
                          en: 'Allow location access in your browser and LALA will immediately load nearby culture, weather, and local experience recommendations.',
                          ja: 'ブラウザの位置情報を許可すると、近くの文化・気象・ローカル体験のおすすめをすぐに読み込みます。',
                          zhHans: '允许浏览器定位后，LALA 将立即加载附近的文化、天气和本地体验推荐。',
                          zhHant: '允許瀏覽器定位後，LALA 將立即載入附近的文化、天氣和在地體驗推薦。',
                        )
                      : '브라우저의 위치 권한을 허용하면 주변 문화·날씨·로컬 경험 추천을 바로 불러옵니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEnglish
                            ? lalaCopyMulti(
                                language,
                                ko: '위치 권한 확인 중',
                                en: 'Waiting for the browser permission prompt',
                                ja: '位置情報の許可を待っています',
                                zhHans: '正在等待浏览器授权',
                                zhHant: '正在等待瀏覽器授權',
                              )
                            : '위치 권한 확인 중',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF2B6CB0),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
