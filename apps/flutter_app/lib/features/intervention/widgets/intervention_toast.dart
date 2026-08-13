import 'package:flutter/material.dart';

import '../../../shared/l10n/lala_copy.dart';

/// 날씨/폐업 개입(intervention) 알림 토스트.
///
/// presentational 위젯 — 표시할 [label] 은 호출부(plan_page / dashboard)에서
/// `interventionToastLabel(intervention, language)` 로 계산해 전달한다.
///
/// V3-D: 폐업 트리거(closure_detected) + 대체 장소(swap) 제안 + 일정 재생성 을
/// 추가한다. 모든 새 파라미터는 선택 옵셔널(defaulted) 이며, 기존 호출부(dashboard)
/// 가 하나도 넘기지 않으면 오늘의 모양 그대로 렌더된다(역호환).
class InterventionToast extends StatelessWidget {
  const InterventionToast({
    super.key,
    required this.label,
    required this.language,
    required this.onOpenPlanner,
    required this.onDismiss,
    this.triggerBadge,
    this.swapLabel,
    this.onSwap,
    this.regenerateLabel,
    this.onRegenerate,
    this.noAlternativeLabel,
  });

  final String label;
  final String language;
  final VoidCallback onOpenPlanner;
  final VoidCallback onDismiss;

  // V3-D additive optional params — defaulted so dashboard.dart (which passes
  // none) keeps today's single-row shape. plan_page.dart passes trigger-aware
  // values computed from the intervention payload.
  final String? triggerBadge;
  final String? swapLabel;
  final VoidCallback? onSwap;
  final String? regenerateLabel;
  final VoidCallback? onRegenerate;
  final String? noAlternativeLabel;

  bool get _hasExpanded =>
      triggerBadge != null ||
      (swapLabel != null && onSwap != null) ||
      noAlternativeLabel != null ||
      (regenerateLabel != null && onRegenerate != null);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 8),
                color: Color(0x30000000),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.tips_and_updates_outlined,
                    color: Color(0xFFF5C842),
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const ValueKey('intervention-toast-plan'),
                    onPressed: onOpenPlanner,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: const Color(0xFFF5C842),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    child: Text(lalaCopy(language, ko: '일정 보기', en: 'Plan')),
                  ),
                  IconButton(
                    key: const ValueKey('intervention-toast-close'),
                    tooltip: lalaCopy(language, ko: '닫기', en: 'Close'),
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close, size: 16),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size(32, 32),
                      foregroundColor: const Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
              if (_hasExpanded) ...[
                const SizedBox(height: 4),
                _expandedSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 트리거 배지 + swap/no-alternative + regenerate 영역. 호출부가 아무 옵션도
  /// 넘기지 않으면 렌더되지 않는다(역호환). 430 maxWidth 내에서 줄바꿈/ellipsis.
  Widget _expandedSection() {
    final hasSwap = swapLabel != null && onSwap != null;
    final showNoAlternative = !hasSwap && noAlternativeLabel != null;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 27, right: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (triggerBadge != null) ...[
              _TriggerBadge(text: triggerBadge!, language: language),
              const SizedBox(height: 6),
            ],
            if (showNoAlternative) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  noAlternativeLabel!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFCBD5E1).withValues(alpha: 0.9),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
            if (hasSwap || (regenerateLabel != null && onRegenerate != null))
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (hasSwap)
                    _ToastAction(
                      key: const ValueKey('intervention-toast-swap'),
                      icon: Icons.swap_horiz,
                      label: swapLabel!,
                      tooltip: swapLabel!,
                      onPressed: onSwap!,
                    ),
                  if (regenerateLabel != null && onRegenerate != null)
                    _ToastAction(
                      key: const ValueKey('intervention-toast-regenerate'),
                      icon: Icons.refresh,
                      label: regenerateLabel!,
                      tooltip: regenerateLabel!,
                      onPressed: onRegenerate!,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 트리거 종류를 한 줄로 표시하는 작은 칩(새 색 토큰 없이 기존 액센트 재사용).
class _TriggerBadge extends StatelessWidget {
  const _TriggerBadge({required this.text, required this.language});

  final String text;
  final String language;

  @override
  Widget build(BuildContext context) {
    // Text 자체가 semantics label("폐업 의심" 등)을 노출하므로 중복 Semantics
    // 래퍼는 생략 — 병합으로 라벨이 중복되는 것을 막는다.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF5C842).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFF5C842),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// swap/regenerate 공용 액션 버튼 — 기존 plan 버튼 스타일(≥34dp)에 맞춤.
/// maxWidth 로 캡해 430 토스트 내 오버플로를 막는다.
class _ToastAction extends StatelessWidget {
  const _ToastAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Tooltip(
        message: tooltip,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: const Color(0xFFF5C842),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}
