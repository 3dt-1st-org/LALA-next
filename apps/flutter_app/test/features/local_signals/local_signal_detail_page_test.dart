import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/core/navigation/local_signal_action.dart';
import 'package:lala_next_app/features/local_signals/data/local_signal_participation_repository.dart';
import 'package:lala_next_app/features/local_signals/domain/local_signal_aggregate.dart';
import 'package:lala_next_app/features/local_signals/domain/local_signal_public.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signal_detail_page.dart';

void main() {
  testWidgets('S-32 renders a reviewed public signal and guest-safe actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository();
    final actions = <LocalSignalPlaceActionRequest>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LocalSignalDetailPage(
          signalId: _signal.id,
          language: 'ko',
          initialConfig: _config,
          arguments: const LocalSignalDetailArguments.public(_signal),
          repository: repository,
          onPlaceAction: actions.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local-signal-detail-page')),
      findsOneWidget,
    );
    expect(find.text('해 질 무렵 한산했어요'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('local-signal-detail-place')),
    );
    expect(find.textContaining('작성자 식별정보'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('local-signal-detail-place')));
    expect(actions.single.action, LocalSignalPlaceAction.viewPlace);
    expect(actions.single.placeId, 'place-1');

    await tester.ensureVisible(
      find.byKey(const ValueKey('local-signal-useful')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('local-signal-comment-field')),
    );
    expect(find.text('댓글 본문'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('local-signal-useful')),
    );
    await tester.tap(find.byKey(const ValueKey('local-signal-useful')));
    await tester.pump();
    expect(find.text('이 빌드에서는 계정 연결을 사용할 수 없어요.'), findsOneWidget);
    expect(repository.usefulCalls, 0);
  });

  testWidgets('S-32 aggregate view exposes only governed summary values', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocalSignalDetailPage(
          signalId: 'aggregate-place-1',
          language: 'en',
          initialConfig: _config,
          arguments: LocalSignalDetailArguments.aggregate(
            _aggregate,
            _aggregateEnvelope,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('System aggregate'), findsOneWidget);
    expect(find.text('Total mentions'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.textContaining('Raw reviews, authors'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const LalaAppConfig _config = LalaAppConfig(
  baseUri: 'https://api.example.test',
);

const LocalSignalPublicItem _signal = LocalSignalPublicItem(
  id: '11111111-1111-4111-8111-111111111111',
  kind: LocalSignalKind.placeTip,
  sourceLanguage: 'ko',
  title: '해 질 무렵 한산했어요',
  body: '평일 저녁에 직접 확인한 공개 경험입니다.',
  localityLevel: 'place',
  localityCode: 'KR-11',
  commercialDisclosure: LocalSignalCommercialDisclosure.none,
  observationDate: '2026-09-02',
  publishedAt: '2026-09-03T00:00:00Z',
  placeLinks: <LocalSignalPlaceLink>[
    LocalSignalPlaceLink(placeId: 'place-1', relation: 'primary'),
  ],
  translationAvailable: false,
  displayLanguage: 'ko',
  reactionCount: 4,
  commentCount: 1,
);

const LocalSignalPlaceAggregate _aggregate = LocalSignalPlaceAggregate(
  placeId: 'place-1',
  placeNameKo: '성수 전시관',
  category: 'culture',
  mentionCount: 18,
  organicMentionCount: 15,
  sentimentScore: 0.7,
  reviewQualityScore: 0.8,
  weekStart: '2026-08-24',
  weekEnd: '2026-08-30',
);

const LocalSignalAggregates _aggregateEnvelope = LocalSignalAggregates(
  available: true,
  items: <LocalSignalPlaceAggregate>[_aggregate],
  computedAt: '2026-08-31T00:00:00Z',
  lastRefreshedAt: '2026-09-01T00:00:00Z',
);

class _MemoryRepository implements LocalSignalParticipationRepository {
  int usefulCalls = 0;

  @override
  Future<LocalSignalPublicItem> getSignal(
    String signalId,
    String language,
  ) async => _signal;

  @override
  Future<LocalSignalCommentFeed> getComments(
    String signalId,
    String language,
  ) async => const LocalSignalCommentFeed(
    items: <LocalSignalPublicComment>[
      LocalSignalPublicComment(
        id: '22222222-2222-4222-8222-222222222222',
        sourceLanguage: 'ko',
        body: '댓글 본문',
        createdAt: '2026-09-03T00:30:00Z',
      ),
    ],
    nextCursor: null,
    hasMore: false,
  );

  @override
  Future<void> setUseful(String signalId, bool active) async {
    usefulCalls += 1;
  }

  @override
  Future<void> setSaved(String signalId, bool active) async {}

  @override
  Future<void> addComment(
    String signalId,
    String sourceLanguage,
    String body,
  ) async {}

  @override
  Future<void> report(String signalId, String reasonCode) async {}

  @override
  Future<LocalSignalMutationReceipt> createDraft(
    LocalSignalDraftInput input,
  ) async => _receipt;

  @override
  Future<LocalSignalMutationReceipt> updateDraft(
    String signalId,
    LocalSignalDraftInput input,
  ) async => _receipt;

  @override
  Future<LocalSignalMutationReceipt> submitDraft(String signalId) async =>
      _receipt;

  @override
  Future<void> deleteDraft(String signalId) async {}

  @override
  void close() {}
}

const LocalSignalMutationReceipt _receipt = LocalSignalMutationReceipt(
  id: '33333333-3333-4333-8333-333333333333',
  status: 'draft',
  moderationState: 'unreviewed',
  visibility: 'private',
  title: 'draft',
  body: 'body',
);
