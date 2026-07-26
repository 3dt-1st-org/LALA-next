import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/features/local_signals/domain/local_signal_public.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signals_page.dart';
import 'package:lala_next_app/manual_location_options.dart';

void main() {
  setUp(RegionContextStore.clear);
  tearDown(RegionContextStore.clear);

  testWidgets('disabled API shows honest state without demo cards', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_SignalsBackend.disabled()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local-signals-disabled')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('local-signal-demo')), findsNothing);
    expect(find.text('로컬 신호를 준비 중이에요'), findsOneWidget);
  });

  testWidgets('guest can read public signals but has no write or identity UI', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_SignalsBackend.loaded()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('local-signal-signal-1')), findsOneWidget);
    expect(find.text('공개 읽기'), findsOneWidget);
    expect(find.text('작성'), findsNothing);
    expect(find.text('반응'), findsNothing);
    expect(find.text('저장'), findsNothing);
    expect(find.textContaining('issuer'), findsNothing);
    expect(find.textContaining('subject'), findsNothing);
    expect(find.textContaining('37.2636'), findsNothing);
    expect(find.textContaining('Naver'), findsNothing);
  });

  testWidgets('loading uses neutral skeletons and no placeholder copy', (
    tester,
  ) async {
    final backend = _SignalsBackend.pending();
    await tester.pumpWidget(_app(backend));
    await tester.pump();

    expect(find.byKey(const ValueKey('local-signals-loading')), findsOneWidget);
    expect(find.text('Local Signals A'), findsNothing);
    backend.complete(_feed());
    await tester.pumpAndSettle();
  });

  testWidgets('empty, error, and retry states are explicit', (tester) async {
    final empty = _SignalsBackend.loaded(feed: _emptyFeed());
    await tester.pumpWidget(_app(empty));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-signals-empty')), findsOneWidget);

    final error = _SignalsBackend.error();
    await tester.pumpWidget(_app(error));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-signals-error')), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    final unavailable = _SignalsBackend.serverUnavailable();
    await tester.pumpWidget(_app(unavailable));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-signals-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('local-signals-disabled')), findsNothing);
  });

  testWidgets('manual region uses only coarse region id and reloads', (
    tester,
  ) async {
    final backend = _SignalsBackend.loaded();
    RegionContextStore.set(RegionContext.manual(_busanOption));
    await tester.pumpWidget(_app(backend));
    await tester.pumpAndSettle();

    expect(backend.requestedRegions, <String?>['busan-haeundae']);
    expect(find.text('해운대구'), findsOneWidget);
  });

  test('public model ignores private and third-party fields', () {
    final item = LocalSignalPublicItem.fromJson(<String, dynamic>{
      ..._itemJson(),
      'author_issuer': 'private-issuer',
      'author_subject': 'private-subject',
      'precise_latitude': 37.2636,
      'raw_third_party_review': 'must not enter app state',
      'moderation': {'status': 'approved'},
      'score': 0.99,
    });

    expect(item, isNotNull);
    expect(item!.title, 'Local Signals A');
    expect(item.body, 'A dated first-party observation.');
    expect(item.placeLinks.single.placeId, 'place-1');
  });
}

Widget _app(_SignalsBackend backend) {
  return MaterialApp(
    home: Scaffold(
      body: LocalSignalsPage(
        key: ValueKey(backend),
        initialConfig: const LalaAppConfig(baseUri: 'https://api.example.test'),
        backendFactory: (_) => backend,
      ),
    ),
  );
}

final ManualLocationOption _busanOption = const ManualLocationOption(
  id: 'busan-haeundae',
  provinceId: 'busan',
  provinceKo: '부산광역시',
  provinceEn: 'Busan',
  labelKo: '해운대구',
  labelEn: 'Haeundae-gu',
  lat: 35.16,
  lng: 129.16,
);

class _SignalsBackend implements LalaBackend {
  _SignalsBackend._({this.feed, this.error, this.completer});

  factory _SignalsBackend.loaded({LocalSignalsFeed? feed}) =>
      _SignalsBackend._(feed: feed ?? _feed());

  factory _SignalsBackend.disabled() => _SignalsBackend._(
    error: const LalaApiException(
      code: 'LOCAL_SIGNALS_DISABLED',
      message: 'disabled',
      statusCode: 503,
      retryable: false,
    ),
  );

  factory _SignalsBackend.error() => _SignalsBackend._(
    error: const LalaApiException(
      code: 'NETWORK_ERROR',
      message: 'network failure',
      statusCode: 0,
      retryable: true,
    ),
  );

  factory _SignalsBackend.serverUnavailable() => _SignalsBackend._(
    error: const LalaApiException(
      code: 'LOCAL_SIGNALS_DB_UNAVAILABLE',
      message: 'database unavailable',
      statusCode: 503,
      retryable: true,
    ),
  );

  factory _SignalsBackend.pending() {
    final completer = Completer<LalaEnvelope<Map<String, dynamic>>>();
    return _SignalsBackend._(completer: completer);
  }

  final LocalSignalsFeed? feed;
  final Object? error;
  final Completer<LalaEnvelope<Map<String, dynamic>>>? completer;
  final List<String?> requestedRegions = <String?>[];

  void complete(LocalSignalsFeed value) {
    completer!.complete(_envelope(value));
  }

  @override
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignals({
    String? region,
    String? placeId,
    String? kind,
    String sort = 'recent',
    String? cursor,
  }) {
    requestedRegions.add(region);
    final pending = completer;
    if (pending != null) return pending.future;
    if (error != null) {
      return Future<LalaEnvelope<Map<String, dynamic>>>.error(error!);
    }
    return Future<LalaEnvelope<Map<String, dynamic>>>.value(_envelope(feed!));
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in Local Signals test');
}

LalaEnvelope<Map<String, dynamic>> _envelope(LocalSignalsFeed feed) {
  return LalaEnvelope<Map<String, dynamic>>(
    ok: true,
    data: <String, dynamic>{
      'items': feed.items.map(_itemToJson).toList(growable: false),
      'next_cursor': feed.nextCursor,
      'has_more': feed.hasMore,
    },
    meta: const <String, dynamic>{},
    error: null,
    statusCode: 200,
    requestId: null,
  );
}

LocalSignalsFeed _feed() => LocalSignalsFeed(
  items: <LocalSignalPublicItem>[
    LocalSignalPublicItem(
      id: 'signal-1',
      kind: 'tip',
      sourceLanguage: 'en',
      title: 'Local Signals A',
      body: 'A dated first-party observation.',
      localityLevel: 'district',
      localityCode: 'Suwon',
      commercialDisclosure: false,
      observationDate: '2026-07-27',
      publishedAt: '2026-07-27T09:00:00Z',
      placeLinks: const <LocalSignalPlaceLink>[
        LocalSignalPlaceLink(placeId: 'place-1', relation: 'nearby'),
      ],
      translationAvailable: true,
      displayLanguage: 'ko',
    ),
  ],
  nextCursor: null,
  hasMore: false,
);

LocalSignalsFeed _emptyFeed() => const LocalSignalsFeed(
  items: <LocalSignalPublicItem>[],
  nextCursor: null,
  hasMore: false,
);

Map<String, dynamic> _itemJson() => <String, dynamic>{
  'id': 'signal-1',
  'kind': 'tip',
  'source_language': 'en',
  'title': 'Local Signals A',
  'body': 'A dated first-party observation.',
  'locality_level': 'district',
  'locality_code': 'Suwon',
  'commercial_disclosure': false,
  'observation_date': '2026-07-27',
  'published_at': '2026-07-27T09:00:00Z',
  'place_links': [
    {'place_id': 'place-1', 'relation': 'nearby'},
  ],
  'translation_available': true,
  'display_language': 'ko',
};

Map<String, dynamic> _itemToJson(
  LocalSignalPublicItem item,
) => <String, dynamic>{
  'id': item.id,
  'kind': item.kind,
  'source_language': item.sourceLanguage,
  'title': item.title,
  'body': item.body,
  'locality_level': item.localityLevel,
  'locality_code': item.localityCode,
  'commercial_disclosure': item.commercialDisclosure,
  'observation_date': item.observationDate,
  'published_at': item.publishedAt,
  'place_links': item.placeLinks
      .map(
        (link) => <String, dynamic>{
          'place_id': link.placeId,
          'relation': link.relation,
        },
      )
      .toList(growable: false),
  'translation_available': item.translationAvailable,
  'display_language': item.displayLanguage,
};
