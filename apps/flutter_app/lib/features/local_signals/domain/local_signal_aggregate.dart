/// Governed system-aggregate read model for the Local Signals tab.
///
/// This is a TYPED system aggregate — never a user post and never a fake
/// contributor item. The wire shape carries counts, scalar scores, and
/// provenance/freshness only; by construction it cannot hold raw review text,
/// author identity, external keys, or URLs. Unknown wire fields are ignored.
library;

import '../../../../shared/l10n/lala_copy.dart';

class LocalSignalPlaceAggregate {
  const LocalSignalPlaceAggregate({
    required this.placeId,
    required this.placeNameKo,
    required this.category,
    required this.mentionCount,
    required this.organicMentionCount,
    required this.sentimentScore,
    required this.reviewQualityScore,
    required this.weekStart,
    required this.weekEnd,
  });

  /// Canonical place id; null when the source row could not resolve one.
  final String? placeId;
  final String placeNameKo;
  final String category;
  final int mentionCount;
  final int? organicMentionCount;
  final double? sentimentScore;
  final double? reviewQualityScore;
  final String weekStart;
  final String weekEnd;

  static LocalSignalPlaceAggregate? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry('$key', value));
    // A row is only an aggregate when the server explicitly typed it so;
    // anything else must not render as an aggregate card.
    if (json['kind'] != 'system_aggregate') return null;
    final placeNameKo = _requiredString(json['place_name_ko']);
    final category = _requiredString(json['category']);
    final mentionCount = json['mention_count'];
    final weekStart = _requiredString(json['week_start']);
    if (placeNameKo == null || category == null || weekStart == null) {
      return null;
    }
    if (mentionCount is! int || mentionCount < 0) return null;
    final weekEnd = _requiredString(json['week_end']) ?? weekStart;
    return LocalSignalPlaceAggregate(
      placeId: _optionalString(json['place_id']),
      placeNameKo: placeNameKo,
      category: category,
      mentionCount: mentionCount,
      organicMentionCount: json['organic_mention_count'] is int
          ? json['organic_mention_count'] as int
          : null,
      sentimentScore: json['sentiment_score'] is num
          ? (json['sentiment_score'] as num).toDouble()
          : null,
      reviewQualityScore: json['review_quality_score'] is num
          ? (json['review_quality_score'] as num).toDouble()
          : null,
      weekStart: weekStart,
      weekEnd: weekEnd,
    );
  }

  /// Honest provenance label: aggregated review mentions, not user posts.
  String providerLabel(String language) => lalaCopyMulti(
        language,
        ko: '리뷰 언급 집계',
        en: 'Aggregated review mentions',
        ja: 'レビュー言及の集計',
        zhHans: '评论提及汇总',
        zhHant: '評論提及彙總',
      );
}

/// Envelope of the governed aggregate read model, including honest
/// availability: [available] false means the governance flag is off or no
/// approved aggregate exists — the tab must show its honest empty state,
/// never fabricated rows.
class LocalSignalAggregates {
  const LocalSignalAggregates({
    required this.available,
    required this.items,
    required this.computedAt,
    required this.lastRefreshedAt,
  });

  final bool available;
  final List<LocalSignalPlaceAggregate> items;
  final String? computedAt;
  final String? lastRefreshedAt;

  static LocalSignalAggregates fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid aggregates payload.');
    }
    final json = value.map((key, value) => MapEntry('$key', value));
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .map(LocalSignalPlaceAggregate.fromJson)
              .whereType<LocalSignalPlaceAggregate>()
              .toList(growable: false)
        : const <LocalSignalPlaceAggregate>[];
    return LocalSignalAggregates(
      available: json['available'] == true && items.isNotEmpty,
      items: items,
      computedAt: _optionalString(json['computed_at']),
      lastRefreshedAt: _optionalString(json['last_refreshed_at']),
    );
  }

  /// Honest freshness label for the aggregate section header.
  String freshnessLabel(String language) {
    final refreshed = lastRefreshedAt ?? computedAt;
    if (refreshed == null) {
      return lalaCopyMulti(
        language,
        ko: '집계 시점 미확인',
        en: 'Aggregation time unknown',
        ja: '集計時点は不明',
        zhHans: '汇总时间未知',
        zhHant: '彙總時間未知',
      );
    }
    final datePart = refreshed.length >= 10 ? refreshed.substring(0, 10) : refreshed;
    return lalaCopyMulti(
      language,
      ko: '집계 기준 $datePart',
      en: 'Aggregated as of $datePart',
      ja: '$datePart 時点の集計',
      zhHans: '汇总截至 $datePart',
      zhHant: '彙總截至 $datePart',
    );
  }
}

String? _requiredString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
