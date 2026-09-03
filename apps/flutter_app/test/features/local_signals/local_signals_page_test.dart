import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/core/backend/lala_backend.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/location/region_context.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/features/local_signals/domain/local_signal_public.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signal_detail_page.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signals_page.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/manual_location_options.dart';

void main() {
  setUp(() {
    RegionContextStore.clear();
    OnboardingState.selectLanguage('ko');
  });
  tearDown(() {
    RegionContextStore.clear();
    OnboardingState.reset();
  });

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

  testWidgets('governed aggregates render with provenance, period, and count', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _SignalsBackend.loaded(aggregates: _aggregatesPayload()),
        onPlaceAction: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    // Provenance label: aggregated review mentions + aggregation date.
    expect(
      find.byKey(const ValueKey('local-signals-aggregates-provenance')),
      findsOneWidget,
    );
    expect(find.textContaining('리뷰 언급 집계'), findsOneWidget);
    expect(find.textContaining('집계 기준 2026-08-04'), findsOneWidget);
    // Aggregate card with period and mention count.
    expect(
      find.byKey(const ValueKey('local-signal-aggregate-count-수원화성')),
      findsOneWidget,
    );
    expect(find.text('언급 12건'), findsOneWidget);
    expect(find.textContaining('2026-08-03 ~ 2026-08-09'), findsOneWidget);
    // Place/plan actions reuse the shared typed action request.
    expect(
      find.byKey(const ValueKey('local-signal-aggregate-place-place-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('local-signal-aggregate-plan-place-1')),
      findsOneWidget,
    );
  });

  testWidgets('aggregate place action dispatches the typed request', (
    tester,
  ) async {
    final requests = <LocalSignalPlaceActionRequest>[];
    await tester.pumpWidget(
      _app(
        _SignalsBackend.loaded(aggregates: _aggregatesPayload()),
        onPlaceAction: requests.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('local-signal-aggregate-place-place-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('local-signal-aggregate-plan-place-1')),
    );

    expect(requests, <LocalSignalPlaceActionRequest>[
      const LocalSignalPlaceActionRequest(
        placeId: 'place-1',
        action: LocalSignalPlaceAction.viewPlace,
      ),
      const LocalSignalPlaceActionRequest(
        placeId: 'place-1',
        action: LocalSignalPlaceAction.addToPlan,
      ),
    ]);
  });

  testWidgets(
    'aggregate read failure shows honest unavailable, feed unaffected',
    (tester) async {
      // aggregates: null → the fake throws for the aggregate read.
      await tester.pumpWidget(_app(_SignalsBackend.loaded()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('local-signals-aggregates-provenance')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('local-signals-aggregates-unavailable')),
        findsOneWidget,
      );
      // The signal feed still renders normally.
      expect(
        find.byKey(const ValueKey('local-signal-signal-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('available-but-empty aggregates render no aggregate section', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _SignalsBackend.loaded(
          aggregates: _aggregatesPayload(items: const <Map<String, dynamic>>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local-signals-aggregates-provenance')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('local-signals-aggregates-unavailable')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('local-signal-signal-1')), findsOneWidget);
  });

  testWidgets('ja locale renders localized aggregate copy without Korean', (
    tester,
  ) async {
    OnboardingState.selectLanguage('ja');
    await tester.pumpWidget(
      _app(
        _SignalsBackend.loaded(aggregates: _aggregatesPayload()),
        onPlaceAction: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local-signals-aggregates-provenance')),
      findsOneWidget,
    );
    // ja has its own aggregate copy (V6 five-language contract).
    expect(find.textContaining('レビュー言及の集計'), findsOneWidget);
    expect(find.textContaining('言及12件'), findsOneWidget);
    // Visitor locale must not leak Korean aggregate copy.
    expect(find.text('언급 12건'), findsNothing);
    expect(find.text('리뷰 언급 집계'), findsNothing);
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

  testWidgets('non-none commercial disclosure is shown as a real notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _SignalsBackend.loaded(
          feed: _feed(disclosure: LocalSignalCommercialDisclosure.paidOrGifted),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('유료·제공 혜택 고지'), findsOneWidget);
  });

  testWidgets('canonical place links expose map and planner actions', (
    tester,
  ) async {
    final requests = <LocalSignalPlaceActionRequest>[];
    await tester.pumpWidget(
      _app(_SignalsBackend.loaded(), onPlaceAction: requests.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('local-signal-place-action-signal-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('local-signal-plan-action-signal-1')),
    );

    expect(requests, <LocalSignalPlaceActionRequest>[
      const LocalSignalPlaceActionRequest(
        placeId: 'place-1',
        action: LocalSignalPlaceAction.viewPlace,
      ),
      const LocalSignalPlaceActionRequest(
        placeId: 'place-1',
        action: LocalSignalPlaceAction.addToPlan,
      ),
    ]);
  });

  testWidgets('signals without canonical place links expose no action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _SignalsBackend.loaded(feed: _feed(placeLinks: const [])),
        onPlaceAction: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local-signal-place-action-signal-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('local-signal-plan-action-signal-1')),
      findsNothing,
    );
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

  test('public model rejects the legacy boolean disclosure shape', () {
    expect(
      LocalSignalPublicItem.fromJson(<String, dynamic>{
        ..._itemJson(),
        'commercial_disclosure': true,
      }),
      isNull,
    );
  });

  test('schema enum values have exclusive KO and EN labels', () {
    expect(
      LocalSignalKind.values.map((kind) => kind.wireValue).toList(),
      <String>[
        'place_tip',
        'route_note',
        'local_question',
        'accessibility_note',
        'seasonal_update',
        'correction',
        'local_story',
      ],
    );
    for (final kind in LocalSignalKind.values) {
      expect(kind.label('ko'), isNotEmpty);
      expect(kind.label('en'), isNotEmpty);
      expect(kind.label('ko'), isNot(kind.label('en')));
    }
    expect(
      LocalSignalCommercialDisclosure.values
          .map((disclosure) => disclosure.wireValue)
          .toList(),
      <String>['none', 'visitor', 'owner_or_staff', 'paid_or_gifted'],
    );
  });

  testWidgets('a stale region response cannot overwrite the latest region', (
    tester,
  ) async {
    final backend = _RegionRaceBackend();
    RegionContextStore.set(RegionContext.manual(_busanOption));
    await tester.pumpWidget(_app(backend));
    await tester.pump();

    RegionContextStore.set(RegionContext.manual(_seoulOption));
    await tester.pump();
    expect(backend.requestedRegions, <String?>['busan-haeundae', 'seoul-jung']);

    backend.complete('busan-haeundae', _feed(title: 'Old Busan response'));
    await tester.pump();
    expect(find.text('Old Busan response'), findsNothing);

    backend.complete('seoul-jung', _feed(title: 'Latest Seoul response'));
    await tester.pumpAndSettle();
    expect(find.text('Latest Seoul response'), findsOneWidget);
    expect(find.text('Old Busan response'), findsNothing);
  });

  testWidgets('selected language updates Local Signals and its request in EN', (
    tester,
  ) async {
    final backend = _SignalsBackend.loaded();
    final configs = <LalaAppConfig>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalSignalsPage(
            initialConfig: const LalaAppConfig(
              baseUri: 'https://api.example.test',
            ),
            backendFactory: (config) {
              configs.add(config);
              return backend;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('로컬 신호'), findsOneWidget);

    OnboardingState.selectLanguage('en');
    await tester.pumpAndSettle();

    expect(find.text('Local Signals'), findsOneWidget);
    expect(find.text('로컬 신호'), findsNothing);
    expect(configs.last.lang, 'en');
  });

  testWidgets('public and aggregate cards open typed S-32 detail arguments', (
    tester,
  ) async {
    final opened = <LocalSignalDetailArguments>[];
    await tester.pumpWidget(
      _app(
        _SignalsBackend.loaded(aggregates: _aggregatesPayload()),
        onOpenDetail: opened.add,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('local-signal-detail-signal-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('local-signal-aggregate-detail-place-1')),
    );

    expect(opened, hasLength(2));
    expect(opened.first.signal?.id, 'signal-1');
    expect(opened.last.aggregate?.placeId, 'place-1');
    expect(opened.last.aggregateEnvelope?.available, isTrue);
  });
}

Widget _app(
  LalaBackend backend, {
  ValueChanged<LocalSignalPlaceActionRequest>? onPlaceAction,
  ValueChanged<LocalSignalDetailArguments>? onOpenDetail,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LocalSignalsPage(
        key: ValueKey(backend),
        initialConfig: const LalaAppConfig(baseUri: 'https://api.example.test'),
        backendFactory: (_) => backend,
        onPlaceAction: onPlaceAction,
        onOpenDetail: onOpenDetail,
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

final ManualLocationOption _seoulOption = const ManualLocationOption(
  id: 'seoul-jung',
  provinceId: 'seoul',
  provinceKo: '서울특별시',
  provinceEn: 'Seoul',
  labelKo: '중구',
  labelEn: 'Jung-gu',
  lat: 37.56,
  lng: 126.99,
);

class _SignalsBackend implements LalaBackend {
  _SignalsBackend._({this.feed, this.error, this.completer, this.aggregates});

  factory _SignalsBackend.loaded({
    LocalSignalsFeed? feed,
    Map<String, dynamic>? aggregates,
  }) => _SignalsBackend._(feed: feed ?? _feed(), aggregates: aggregates);

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

  /// Governed aggregate payload; null = aggregate read fails (honest
  /// unavailable path), empty-available = honest no-aggregate-data.
  final Map<String, dynamic>? aggregates;
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
  Future<LalaEnvelope<Map<String, dynamic>>> getLocalSignalAggregates({
    int weeks = 4,
    int limit = 20,
    String? placeId,
    String? category,
  }) {
    if (aggregates == null) {
      return Future<LalaEnvelope<Map<String, dynamic>>>.error(
        const LalaApiException(
          code: 'LOCAL_SIGNALS_DISABLED',
          message: 'aggregates disabled',
          statusCode: 503,
          retryable: false,
        ),
      );
    }
    return Future<LalaEnvelope<Map<String, dynamic>>>.value(
      LalaEnvelope<Map<String, dynamic>>(
        ok: true,
        data: aggregates,
        meta: const <String, dynamic>{},
        error: null,
        statusCode: 200,
        requestId: null,
      ),
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in Local Signals test');
}

class _RegionRaceBackend implements LalaBackend {
  final Map<String, Completer<LalaEnvelope<Map<String, dynamic>>>> _pending =
      <String, Completer<LalaEnvelope<Map<String, dynamic>>>>{};
  final List<String?> requestedRegions = <String?>[];

  void complete(String region, LocalSignalsFeed feed) {
    _pending[region]!.complete(_envelope(feed));
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
    final completer = Completer<LalaEnvelope<Map<String, dynamic>>>();
    _pending[region!] = completer;
    return completer.future;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in region race test');
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

LocalSignalsFeed _feed({
  LocalSignalCommercialDisclosure disclosure =
      LocalSignalCommercialDisclosure.none,
  String title = 'Local Signals A',
  List<LocalSignalPlaceLink> placeLinks = const <LocalSignalPlaceLink>[
    LocalSignalPlaceLink(placeId: 'place-1', relation: 'nearby'),
  ],
}) => LocalSignalsFeed(
  items: <LocalSignalPublicItem>[
    LocalSignalPublicItem(
      id: 'signal-1',
      kind: LocalSignalKind.placeTip,
      sourceLanguage: 'en',
      title: title,
      body: 'A dated first-party observation.',
      localityLevel: 'district',
      localityCode: 'Suwon',
      commercialDisclosure: disclosure,
      observationDate: '2026-07-27',
      publishedAt: '2026-07-27T09:00:00Z',
      placeLinks: placeLinks,
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
  'kind': 'place_tip',
  'source_language': 'en',
  'title': 'Local Signals A',
  'body': 'A dated first-party observation.',
  'locality_level': 'district',
  'locality_code': 'Suwon',
  'commercial_disclosure': 'none',
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
  'kind': item.kind.wireValue,
  'source_language': item.sourceLanguage,
  'title': item.title,
  'body': item.body,
  'locality_level': item.localityLevel,
  'locality_code': item.localityCode,
  'commercial_disclosure': item.commercialDisclosure.wireValue,
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

Map<String, dynamic> _aggregatesPayload({
  List<Map<String, dynamic>> items = const <Map<String, dynamic>>[
    <String, dynamic>{
      'kind': 'system_aggregate',
      'place_id': 'place-1',
      'place_name_ko': '수원화성',
      'category': 'attraction',
      'mention_count': 12,
      'organic_mention_count': 9,
      'sentiment_score': 0.62,
      'review_quality_score': 0.71,
      'week_start': '2026-08-03',
      'week_end': '2026-08-09',
      'provider_class': 'aggregated_review_mentions',
    },
  ],
}) => <String, dynamic>{
  'read_model': 'local_signals_place_aggregates',
  'read_model_version': 'v1',
  'source': 'governed_review_mention_aggregation',
  'provider_class': 'aggregated_review_mentions',
  'available': true,
  'items': items,
  'computed_at': '2026-08-04T06:30:00Z',
  'last_refreshed_at': '2026-08-04T06:30:00Z',
};
