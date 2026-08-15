import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';
import '../../home/home_view_helpers.dart';

/// 하단 독의 honest 상태 콘텐츠(§13.5). 세 가지를 서로 다른 아이콘·카피로 구분한다:
/// - 준비 중(loading): 아직 첫 응답 전. 실제 장소/핀이 없는 정직한 대기.
/// - unavailable: 서비스에 도달하지 못함(네트워크/타임아웃).
/// - error: 서비스가 오류로 응답.
/// 빈 상태(no-data, 응답은 왔으나 0건)와 실패 카피는 절대 겹치지 않는다.
/// 색상 단독 신호를 피하기 위해 아이콘 + 텍스트 + 시맨틱 라벨을 함께 쓴다.
class EmptyDockContent extends StatelessWidget {
  const EmptyDockContent({
    super.key,
    required this.language,
    this.errorLabel,
    this.failureKind,
    this.recoveryPending = false,
    this.onRetry,
  });

  final String language;
  final String? errorLabel;

  /// 추천 로드 실패 종류. null 이고 errorLabel 도 없으면 '준비 중' 상태.
  final RecommendationFailureKind? failureKind;
  final bool recoveryPending;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = errorLabel != null && errorLabel!.trim().isNotEmpty;
    final isUnavailable = failureKind == RecommendationFailureKind.unavailable;
    // 준비 중 vs unavailable vs error — 각각 고유 색상/아이콘/라벨.
    final Color iconBg;
    final Color iconColor;
    final IconData iconData;
    final String title;
    final String subtitle;
    if (hasError) {
      iconBg = isUnavailable
          ? const Color(0xFFEAF2FF)
          : const Color(0xFFFFF3E8);
      iconColor = isUnavailable
          ? const Color(0xFF2B6CB0)
          : const Color(0xFFB45309);
      iconData = isUnavailable
          ? Icons.wifi_off_rounded
          : Icons.error_outline_rounded;
      title = lalaCopyMulti(
        language,
        ko: isUnavailable ? '서버에 연결할 수 없어요' : '추천 연결을 다시 확인하고 있어요',
        en: isUnavailable
            ? 'Could not reach the service'
            : 'Checking recommendations again',
        ja: isUnavailable ? 'サーバーに接続できません' : 'おすすめを再確認しています',
        zhHans: isUnavailable ? '无法连接服务器' : '正在重新检查推荐',
        zhHant: isUnavailable ? '無法連線伺服器' : '正在重新檢查推薦',
      );
      subtitle = lalaCopyMulti(
        language,
        ko: recoveryPending
            ? '잠시 후 자동으로 다시 시도합니다. 지금 바로 다시 시도할 수도 있어요.'
            : (isUnavailable
                  ? '네트워크를 확인 후 다시 시도해 주세요.'
                  : '잠시 후 다시 시도해 주세요. 필요하면 지금 바로 다시 시도할 수 있어요.'),
        en: recoveryPending
            ? 'Retrying automatically soon. You can also retry right now.'
            : (isUnavailable
                  ? 'Check your connection and try again.'
                  : 'Please try again shortly. You can also retry right now.'),
        ja: recoveryPending
            ? 'まもなく自動で再試行します。今すぐ再試行することもできます。'
            : (isUnavailable
                  ? 'ネットワークを確認してもう一度お試しください。'
                  : 'しばらくしてからもう一度お試しください。今すぐ再試行もできます。'),
        zhHans: recoveryPending
            ? '即将自动重试，您也可以立即重试。'
            : (isUnavailable ? '请检查网络后重试。' : '请稍后重试，也可以立即重试。'),
        zhHant: recoveryPending
            ? '即將自動重試，您也可以立即重試。'
            : (isUnavailable ? '請檢查網路後重試。' : '請稍後重試，也可以立即重試。'),
      );
    } else {
      iconBg = const Color(0xFFEAF2FF);
      iconColor = const Color(0xFF2B6CB0);
      iconData = Icons.travel_explore;
      title = lalaCopyMulti(
        language,
        ko: '추천을 준비 중입니다',
        en: 'Preparing recommendations',
        ja: 'おすすめを準備しています',
        zhHans: '正在准备推荐',
        zhHant: '正在準備推薦',
      );
      subtitle = lalaCopyMulti(
        language,
        ko: '공식 데이터가 확인된 장소만 표시합니다.',
        en: 'Only places backed by official data are shown.',
        ja: '公式データが確認できたスポットのみを表示します。',
        zhHans: '仅显示经官方数据确认的地点。',
        zhHant: '僅顯示經官方資料確認的地點。',
      );
    }
    final semanticsLabel = lalaCopyMulti(
      language,
      ko: hasError
          ? (isUnavailable ? '서버 연결 불가. $title $subtitle' : '추천 불러오기 실패. $title $subtitle')
          : '추천 준비 중. $title $subtitle',
      en: hasError
          ? (isUnavailable ? 'Service unreachable. $title $subtitle' : 'Failed to load recommendations. $title $subtitle')
          : 'Preparing recommendations. $title $subtitle',
      ja: hasError
          ? (isUnavailable
                ? 'サーバーに接続できません。$title $subtitle'
                : 'おすすめの読み込みに失敗しました。$title $subtitle')
          : 'おすすめを準備中です。$title $subtitle',
      zhHans: hasError
          ? (isUnavailable ? '无法连接服务器。$title $subtitle' : '加载推荐失败。$title $subtitle')
          : '正在准备推荐。$title $subtitle',
      zhHant: hasError
          ? (isUnavailable ? '無法連線伺服器。$title $subtitle' : '載入推薦失敗。$title $subtitle')
          : '正在準備推薦。$title $subtitle',
    );
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(iconData, color: iconColor, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasError && onRetry != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    // §13.5: 최소 44dp 터치 타겟을 보장한다(기존 32dp 에서 상향).
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: TextButton.icon(
                        key: const ValueKey('dock-error-retry'),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(
                          lalaCopyMulti(
                            language,
                            ko: '지금 다시 시도',
                            en: 'Retry now',
                            ja: '今すぐ再試行',
                            zhHans: '立即重试',
                            zhHant: '立即重試',
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
