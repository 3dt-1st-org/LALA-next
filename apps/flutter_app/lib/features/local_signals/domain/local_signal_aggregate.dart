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
    this.readAvailable = false,
    this.region,
    this.regionApplied = false,
    this.freshnessState,
    this.freshnessThresholdDays,
  });

  final bool available;
  final List<LocalSignalPlaceAggregate> items;
  final String? computedAt;
  final String? lastRefreshedAt;

  /// Wire-level availability (governance read on, payload `available: true`),
  /// kept separate from [available]: a region-scoped read can be wire-available
  /// with zero rows — an honest region empty, not the flag-off state.
  final bool readAvailable;

  /// Echoed coarse region id from the request; null when unscoped.
  final String? region;

  /// True only when the server actually applied the region filter; a region
  /// id it cannot safely map stays false with zero items (fail-closed, no
  /// nationwide fallback).
  final bool regionApplied;

  /// Server-classified freshness ('fresh' | 'stale' | 'unknown'); null when
  /// an older server omitted the field — render the date without a suffix.
  final String? freshnessState;
  final int? freshnessThresholdDays;

  bool get isStale => freshnessState == 'stale';

  /// The read model is on but the scoped region has no aggregate rows —
  /// surfaced as a small honest-empty notice instead of a hidden section.
  bool get regionScopedEmpty => readAvailable && items.isEmpty;

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
    final freshness = json['freshness'];
    final freshnessMap = freshness is Map
        ? freshness.map((key, value) => MapEntry('$key', value))
        : const <String, Object?>{};
    final readAvailable = json['available'] == true;
    return LocalSignalAggregates(
      available: readAvailable && items.isNotEmpty,
      items: items,
      computedAt: _optionalString(json['computed_at']),
      lastRefreshedAt: _optionalString(json['last_refreshed_at']),
      readAvailable: readAvailable,
      region: _optionalString(json['region']),
      regionApplied: json['region_applied'] == true,
      freshnessState: _optionalString(freshnessMap['state']),
      freshnessThresholdDays: freshnessMap['threshold_days'] is int
          ? freshnessMap['threshold_days'] as int
          : null,
    );
  }

  /// Honest freshness label for the aggregate section header. The server owns
  /// the fresh/stale classification so the label never depends on the device
  /// wall clock; a missing state renders the bare date (older-server compat).
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
    switch (freshnessState) {
      case 'stale':
        return lalaCopyMulti(
          language,
          ko: '집계 기준 $datePart · 최신 아님',
          en: 'Aggregated as of $datePart · may be outdated',
          ja: '$datePart 時点の集計 · 最新ではない',
          zhHans: '汇总截至 $datePart · 可能已过期',
          zhHant: '彙總截至 $datePart · 可能已過期',
        );
      case 'fresh':
        return lalaCopyMulti(
          language,
          ko: '집계 기준 $datePart · 최신',
          en: 'Aggregated as of $datePart · current',
          ja: '$datePart 時点の集計 · 最新',
          zhHans: '汇总截至 $datePart · 最新',
          zhHant: '彙總截至 $datePart · 最新',
        );
      default:
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

  /// Prominent notice for the stale row under the aggregates header.
  String staleNoticeLabel(String language) => lalaCopyMulti(
        language,
        ko: '집계 데이터가 오래되어 최신 상태와 다를 수 있어요',
        en: 'This aggregate data is stale and may differ from current conditions',
        ja: '集計データが古く、最新の状態と異なる場合があります',
        zhHans: '汇总数据已过期，可能与当前状态不同',
        zhHant: '彙總資料已過期，可能與目前狀態不同',
      );
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
