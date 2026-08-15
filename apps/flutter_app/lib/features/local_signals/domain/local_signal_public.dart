/// Safe client-side representation of the Local Signals public projection.
///
/// This model intentionally has no author identity, moderation state, score,
/// capability token, coordinates, or third-party review fields. Unknown wire
/// fields are ignored so private server-side data cannot enter app state.
library;

import '../../../shared/l10n/lala_copy.dart';

enum LocalSignalKind {
  placeTip('place_tip'),
  routeNote('route_note'),
  localQuestion('local_question'),
  accessibilityNote('accessibility_note'),
  seasonalUpdate('seasonal_update'),
  correction('correction'),
  localStory('local_story');

  const LocalSignalKind(this.wireValue);

  final String wireValue;

  static LocalSignalKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }

  String label(String language) => switch (this) {
    // V6: ko 이외는 현지화(kind 라벨). ko 반환값은 기존과 동일.
    LocalSignalKind.placeTip => lalaCopyMulti(
      language,
      ko: '장소 팁',
      en: 'Place tip',
      ja: 'スポットのヒント',
      zhHans: '地点提示',
      zhHant: '地點提示',
    ),
    LocalSignalKind.routeNote => lalaCopyMulti(
      language,
      ko: '동선 메모',
      en: 'Route note',
      ja: 'ルートメモ',
      zhHans: '路线笔记',
      zhHant: '路線筆記',
    ),
    LocalSignalKind.localQuestion => lalaCopyMulti(
      language,
      ko: '로컬 질문',
      en: 'Local question',
      ja: 'ローカルな質問',
      zhHans: '本地提问',
      zhHant: '在地提問',
    ),
    LocalSignalKind.accessibilityNote => lalaCopyMulti(
      language,
      ko: '접근성 메모',
      en: 'Accessibility',
      ja: 'バリアフリー情報',
      zhHans: '无障碍信息',
      zhHant: '無障礙資訊',
    ),
    LocalSignalKind.seasonalUpdate => lalaCopyMulti(
      language,
      ko: '계절 업데이트',
      en: 'Seasonal update',
      ja: '季節の最新情報',
      zhHans: '季节更新',
      zhHant: '季節更新',
    ),
    LocalSignalKind.correction => lalaCopyMulti(
      language,
      ko: '정정',
      en: 'Correction',
      ja: '訂正',
      zhHans: '更正',
      zhHant: '更正',
    ),
    LocalSignalKind.localStory => lalaCopyMulti(
      language,
      ko: '로컬 이야기',
      en: 'Local story',
      ja: 'ローカルの物語',
      zhHans: '本地故事',
      zhHant: '在地故事',
    ),
  };
}

enum LocalSignalCommercialDisclosure {
  none('none'),
  visitor('visitor'),
  ownerOrStaff('owner_or_staff'),
  paidOrGifted('paid_or_gifted');

  const LocalSignalCommercialDisclosure(this.wireValue);

  final String wireValue;

  static LocalSignalCommercialDisclosure? fromWire(Object? value) {
    for (final disclosure in values) {
      if (disclosure.wireValue == value) return disclosure;
    }
    return null;
  }

  String label(String language) => switch (this) {
    LocalSignalCommercialDisclosure.none => '',
    LocalSignalCommercialDisclosure.visitor => lalaCopyMulti(
      language,
      ko: '방문객 경험 기반 고지',
      en: 'Visitor disclosure',
      ja: '訪問者体験に基づく表示',
      zhHans: '基于访客体验的披露',
      zhHant: '基於訪客體驗的揭露',
    ),
    LocalSignalCommercialDisclosure.ownerOrStaff => lalaCopyMulti(
      language,
      ko: '운영자·직원 관여 고지',
      en: 'Owner/staff disclosure',
      ja: '運営者・従業員関与の表示',
      zhHans: '经营者或员工参与披露',
      zhHant: '經營者或員工參與揭露',
    ),
    LocalSignalCommercialDisclosure.paidOrGifted => lalaCopyMulti(
      language,
      ko: '유료·제공 혜택 고지',
      en: 'Paid or gifted disclosure',
      ja: '有償・提供特典の表示',
      zhHans: '付费或赠礼披露',
      zhHant: '付費或贈禮揭露',
    ),
  };
}

class LocalSignalPublicItem {
  const LocalSignalPublicItem({
    required this.id,
    required this.kind,
    required this.sourceLanguage,
    required this.title,
    required this.body,
    required this.localityLevel,
    required this.localityCode,
    required this.commercialDisclosure,
    required this.observationDate,
    required this.publishedAt,
    required this.placeLinks,
    required this.translationAvailable,
    required this.displayLanguage,
  });

  final String id;
  final LocalSignalKind kind;
  final String sourceLanguage;
  final String title;
  final String body;
  final String? localityLevel;
  final String? localityCode;
  final LocalSignalCommercialDisclosure commercialDisclosure;
  final String? observationDate;
  final String? publishedAt;
  final List<LocalSignalPlaceLink> placeLinks;
  final bool translationAvailable;
  final String? displayLanguage;

  static LocalSignalPublicItem? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry('$key', value));
    final id = _requiredString(json['id']);
    final kind = LocalSignalKind.fromWire(json['kind']);
    final sourceLanguage = _requiredString(json['source_language']);
    final title = _requiredString(json['title']);
    final body = _requiredString(json['body']);
    final commercialDisclosure = LocalSignalCommercialDisclosure.fromWire(
      json['commercial_disclosure'],
    );
    if ([
      id,
      kind,
      sourceLanguage,
      title,
      body,
      commercialDisclosure,
    ].any((value) => value == null)) {
      return null;
    }
    final rawLinks = json['place_links'];
    final links = rawLinks is List
        ? rawLinks
              .map(LocalSignalPlaceLink.fromJson)
              .whereType<LocalSignalPlaceLink>()
              .toList(growable: false)
        : const <LocalSignalPlaceLink>[];
    return LocalSignalPublicItem(
      id: id!,
      kind: kind!,
      sourceLanguage: sourceLanguage!,
      title: title!,
      body: body!,
      localityLevel: _optionalString(json['locality_level']),
      localityCode: _optionalString(json['locality_code']),
      commercialDisclosure: commercialDisclosure!,
      observationDate: _optionalString(json['observation_date']),
      publishedAt: _optionalString(json['published_at']),
      placeLinks: links,
      translationAvailable: json['translation_available'] == true,
      displayLanguage: _optionalString(json['display_language']),
    );
  }
}

class LocalSignalPlaceLink {
  const LocalSignalPlaceLink({required this.placeId, required this.relation});

  final String placeId;
  final String? relation;

  static LocalSignalPlaceLink? fromJson(Object? value) {
    if (value is! Map) return null;
    final placeId = _requiredString(value['place_id']);
    if (placeId == null || placeId.isEmpty) return null;
    return LocalSignalPlaceLink(
      placeId: placeId,
      relation: _optionalString(value['relation']),
    );
  }
}

class LocalSignalsFeed {
  const LocalSignalsFeed({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<LocalSignalPublicItem> items;
  final String? nextCursor;
  final bool hasMore;

  static LocalSignalsFeed fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid Local Signals feed.');
    }
    final rawItems = value['items'];
    final items = rawItems is List
        ? rawItems
              .map(LocalSignalPublicItem.fromJson)
              .whereType<LocalSignalPublicItem>()
              .toList(growable: false)
        : const <LocalSignalPublicItem>[];
    return LocalSignalsFeed(
      items: items,
      nextCursor: _optionalString(value['next_cursor']),
      hasMore: value['has_more'] == true,
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
