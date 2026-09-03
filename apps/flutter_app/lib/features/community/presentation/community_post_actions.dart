// 커뮤니티 게시글 팔로우·신고 액션 공용 모듈(F-080).
// - S-40 피드 카드와 S-41 상세 헤더가 같은 팔로우 버튼/문구를 공유한다.
// - 신고 사유는 서버 계약의 제한된 reason_code 목록만 노출한다(자유 서술 없음).
// - 알 수 없는 wire 값은 지원 상태로 재표기하지 않는다: 접수 증복 여부는
//   서버가 내려준 duplicate 불리언만 사용하고 status 문자열은 그대로 둔다.
import 'package:flutter/material.dart';

import 'package:lala_next_app/shared/l10n/lala_copy.dart';

/// 팔로우 토글 버튼. 낙관적 상태는 호출부에서 관리하고 여기선 표시 전용.
class CommunityFollowButton extends StatelessWidget {
  const CommunityFollowButton({
    super.key,
    required this.following,
    required this.busy,
    required this.onPressed,
    required this.language,
    this.compact = false,
  });

  final bool following;
  final bool busy;
  final VoidCallback? onPressed;
  final String language;
  final bool compact;

  String get _label => communityFollowLabel(language, following);

  // Why: 진행 중 탭은 부모 카드의 상세 내비게이션으로 새어 가지 않도록
  // 제스처를 받아서 무시한다(null 이면 부모 InkWell 이 대신 승리한다).
  void _absorbTap() {}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: _label,
      button: true,
      child: InkWell(
        key: const ValueKey('community-follow-toggle'),
        onTap: busy ? _absorbTap : onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: following
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (busy)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  following
                      ? Icons.check_rounded
                      : Icons.person_add_alt_rounded,
                  size: compact ? 13 : 15,
                  color: following
                      ? theme.colorScheme.onPrimaryContainer
                      : const Color(0xFF64748B),
                ),
              const SizedBox(width: 5),
              Text(
                _label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: following
                      ? theme.colorScheme.onPrimaryContainer
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String communityFollowLabel(String language, bool following) => lalaCopyMulti(
  language,
  ko: following ? '팔로잉' : '팔로우',
  en: following ? 'Following' : 'Follow',
  ja: following ? 'フォロー中' : 'フォロー',
  zhHans: following ? '已关注' : '关注',
  zhHant: following ? '已追蹤' : '追蹤',
);

String communityFollowActionLabel(String language) => lalaCopyMulti(
  language,
  ko: '팔로우',
  en: 'following authors',
  ja: 'フォロー',
  zhHans: '关注',
  zhHant: '追蹤',
);

String communityFollowFailureMessage(String language) => lalaCopyMulti(
  language,
  ko: '팔로우 처리에 실패했어요. 잠시 후 다시 시도해 주세요.',
  en: 'Could not update your follow. Please try again.',
  ja: 'フォローを更新できませんでした。しばらくしてからもう一度お試しください。',
  zhHans: '无法更新关注，请稍后重试。',
  zhHant: '無法更新追蹤，請稍後再試。',
);

/// 서버가 자기 자신 팔로우(422 INVALID_FOLLOW_TARGET)를 거절한 경우의 안내.
String communitySelfFollowMessage(String language) => lalaCopyMulti(
  language,
  ko: '내 계정은 팔로우할 수 없어요.',
  en: 'You cannot follow your own account.',
  ja: '自分のアカウントはフォローできません。',
  zhHans: '不能关注自己的账号。',
  zhHant: '無法追蹤自己的帳號。',
);

String communityReportActionLabel(String language) => lalaCopyMulti(
  language,
  ko: '신고',
  en: 'reporting',
  ja: '報告',
  zhHans: '举报',
  zhHant: '檢舉',
);

String communityReportMenuLabel(String language) => lalaCopyMulti(
  language,
  ko: '이 게시글 신고',
  en: 'Report this post',
  ja: 'この投稿を報告',
  zhHans: '举报这篇帖子',
  zhHant: '檢舉這篇貼文',
);

/// 제한된 신고 사유 코드와 5개 언어 라벨. 서버 Literal 계약과 1:1 대응하며,
/// 여기에 없는 코드는 UI에 노출되지 않는다.
List<(String, String)> communityReportReasonOptions(String language) =>
    <(String, String)>[
      (
        'spam_promotion',
        lalaCopyMulti(
          language,
          ko: '스팸·홍보',
          en: 'Spam or promotion',
          ja: 'スパム・宣伝',
          zhHans: '垃圾信息或广告',
          zhHant: '垃圾訊息或廣告',
        ),
      ),
      (
        'harassment_hate',
        lalaCopyMulti(
          language,
          ko: '괴롭힘·혐오 표현',
          en: 'Harassment or hate',
          ja: 'ハラスメント・ヘイト',
          zhHans: '骚扰或仇恨言论',
          zhHant: '騷擾或仇恨言論',
        ),
      ),
      (
        'explicit_content',
        lalaCopyMulti(
          language,
          ko: '부적절한 내용',
          en: 'Explicit content',
          ja: '不適切な内容',
          zhHans: '不当内容',
          zhHant: '不當內容',
        ),
      ),
      (
        'privacy_exposure',
        lalaCopyMulti(
          language,
          ko: '개인정보 노출',
          en: 'Privacy exposure',
          ja: '個人情報の露出',
          zhHans: '隐私泄露',
          zhHant: '隱私洩露',
        ),
      ),
      (
        'misinformation',
        lalaCopyMulti(
          language,
          ko: '허위 정보',
          en: 'Misinformation',
          ja: '誤情報',
          zhHans: '虚假信息',
          zhHant: '虛假資訊',
        ),
      ),
      (
        'other_policy',
        lalaCopyMulti(
          language,
          ko: '기타 정책 위반',
          en: 'Other policy violation',
          ja: 'その他のポリシー違反',
          zhHans: '其他违规',
          zhHant: '其他違規',
        ),
      ),
    ];

/// 신고 사유 바텀시트. 선택된 reason_code 만 반환하고 취소하면 null.
Future<String?> showCommunityReportReasonSheet(
  BuildContext context,
  String language,
) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: <Widget>[
          Text(
            lalaCopyMulti(
              language,
              ko: '신고 사유',
              en: 'Report reason',
              ja: '報告理由',
              zhHans: '举报原因',
              zhHant: '檢舉原因',
            ),
            style: Theme.of(
              sheetContext,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...communityReportReasonOptions(language).map(
            (option) => ListTile(
              key: ValueKey('community-report-reason-${option.$1}'),
              onTap: () => Navigator.of(sheetContext).pop(option.$1),
              title: Text(option.$2),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ],
      );
    },
  );
}

/// 접수 결과 안내. 증복 접수(duplicate=true)는 서버가 보관한 최초 신고가
/// 그대로 유지됨을 알린다 — 새 접수로 표시하지 않는다.
String communityReportReceiptMessage(String language, bool duplicate) =>
    duplicate
    ? lalaCopyMulti(
        language,
        ko: '이미 신고한 게시글이에요. 접수된 신고는 그대로 유지됩니다.',
        en: 'You already reported this post. Your original report is kept.',
        ja: 'この投稿はすでに報告済みです。最初の報告がそのまま維持されます。',
        zhHans: '你已举报过这篇帖子，原举报会被保留。',
        zhHant: '你已檢舉過這篇貼文，原檢舉會保留。',
      )
    : lalaCopyMulti(
        language,
        ko: '신고가 접수됐어요.',
        en: 'Your report was received.',
        ja: '報告を受け付けました。',
        zhHans: '举报已提交。',
        zhHant: '檢舉已提交。',
      );

String communityReportFailureMessage(String language) => lalaCopyMulti(
  language,
  ko: '신고 접수에 실패했어요. 잠시 후 다시 시도해 주세요.',
  en: 'Could not submit your report. Please try again.',
  ja: '報告を送信できませんでした。しばらくしてからもう一度お試しください。',
  zhHans: '无法提交举报，请稍后重试。',
  zhHant: '無法提交檢舉，請稍後再試。',
);
