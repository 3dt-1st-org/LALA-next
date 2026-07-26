/// Safe client-side representation of the Local Signals public projection.
///
/// This model intentionally has no author identity, moderation state, score,
/// capability token, coordinates, or third-party review fields. Unknown wire
/// fields are ignored so private server-side data cannot enter app state.
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
  final String kind;
  final String sourceLanguage;
  final String title;
  final String body;
  final String? localityLevel;
  final String? localityCode;
  final bool commercialDisclosure;
  final String? observationDate;
  final String? publishedAt;
  final List<LocalSignalPlaceLink> placeLinks;
  final bool translationAvailable;
  final String? displayLanguage;

  static LocalSignalPublicItem? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry('$key', value));
    final id = _requiredString(json['id']);
    final kind = _requiredString(json['kind']);
    final sourceLanguage = _requiredString(json['source_language']);
    final title = _requiredString(json['title']);
    final body = _requiredString(json['body']);
    if ([id, kind, sourceLanguage, title, body].any((value) => value == null)) {
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
      commercialDisclosure: json['commercial_disclosure'] == true,
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
