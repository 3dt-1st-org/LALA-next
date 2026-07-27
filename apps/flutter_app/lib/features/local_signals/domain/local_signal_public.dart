/// Safe client-side representation of the Local Signals public projection.
///
/// This model intentionally has no author identity, moderation state, score,
/// capability token, coordinates, or third-party review fields. Unknown wire
/// fields are ignored so private server-side data cannot enter app state.
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
    LocalSignalKind.placeTip => language == 'en' ? 'Place tip' : '장소 팁',
    LocalSignalKind.routeNote => language == 'en' ? 'Route note' : '동선 메모',
    LocalSignalKind.localQuestion =>
      language == 'en' ? 'Local question' : '로컬 질문',
    LocalSignalKind.accessibilityNote =>
      language == 'en' ? 'Accessibility' : '접근성 메모',
    LocalSignalKind.seasonalUpdate =>
      language == 'en' ? 'Seasonal update' : '계절 업데이트',
    LocalSignalKind.correction => language == 'en' ? 'Correction' : '정정',
    LocalSignalKind.localStory => language == 'en' ? 'Local story' : '로컬 이야기',
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
    LocalSignalCommercialDisclosure.visitor =>
      language == 'en' ? 'Visitor disclosure' : '방문객 경험 기반 고지',
    LocalSignalCommercialDisclosure.ownerOrStaff =>
      language == 'en' ? 'Owner/staff disclosure' : '운영자·직원 관여 고지',
    LocalSignalCommercialDisclosure.paidOrGifted =>
      language == 'en' ? 'Paid or gifted disclosure' : '유료·제공 혜택 고지',
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
