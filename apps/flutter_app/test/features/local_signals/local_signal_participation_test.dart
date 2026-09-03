import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/local_signals/data/local_signal_participation_repository.dart';
import 'package:lala_next_app/features/local_signals/domain/local_signal_public.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signal_detail_page.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

void main() {
  testWidgets(
    'S-32 authenticated reactions, saves, and reports hit the repository',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryRepository();
      final controller = await _authenticatedController();

      await _pumpDetail(tester, repository: repository, controller: controller);

      await tester.ensureVisible(
        find.byKey(const ValueKey('local-signal-useful')),
      );
      await tester.tap(find.byKey(const ValueKey('local-signal-useful')));
      await tester.pumpAndSettle();
      expect(repository.usefulCalls, <bool>[true]);

      await tester.ensureVisible(
        find.byKey(const ValueKey('local-signal-save')),
      );
      await tester.tap(find.byKey(const ValueKey('local-signal-save')));
      await tester.pumpAndSettle();
      expect(repository.savedCalls, <bool>[true]);

      await tester.ensureVisible(
        find.byKey(const ValueKey('local-signal-report')),
      );
      await tester.tap(find.byKey(const ValueKey('local-signal-report')));
      await tester.pumpAndSettle();
      expect(find.text('신고 사유'), findsOneWidget);
      await tester.tap(find.text('광고 고지 누락'));
      await tester.pumpAndSettle();
      expect(repository.reportCalls, <String>['promotion_not_disclosed']);
      expect(find.text('신고를 접수했어요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-32 comment success clears the field and reloads public comments',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryRepository();
      final controller = await _authenticatedController();

      await _pumpDetail(tester, repository: repository, controller: controller);

      await tester.enterText(
        find.byKey(const ValueKey('local-signal-comment-field')),
        '같은 시간에 방문해 확인했어요.',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('local-signal-comment-submit')),
      );
      await tester.pumpAndSettle();

      expect(repository.commentBodies, <String>['같은 시간에 방문해 확인했어요.']);
      expect(find.widgetWithText(TextField, '같은 시간에 방문해 확인했어요.'), findsNothing);
      expect(find.text('같은 시간에 방문해 확인했어요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('S-32 comment failure keeps the typed text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository()..failCommentSubmission = true;
    final controller = await _authenticatedController();

    await _pumpDetail(tester, repository: repository, controller: controller);

    await tester.enterText(
      find.byKey(const ValueKey('local-signal-comment-field')),
      '다시 보낼 내용',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('local-signal-comment-submit')));
    await tester.pumpAndSettle();

    expect(repository.commentBodies, isEmpty);
    expect(find.text('다시 보낼 내용'), findsOneWidget);
    expect(find.text('요청을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'S-32 comment load failure is explicit and recoverable, not an empty list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryRepository()..failCommentsLoad = true;

      await _pumpDetail(tester, repository: repository);

      expect(find.text('댓글을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('아직 공개된 댓글이 없어요.'), findsNothing);

      repository.failCommentsLoad = false;
      await tester.tap(
        find.byKey(const ValueKey('local-signal-comments-retry')),
      );
      await tester.pumpAndSettle();
      expect(find.text('댓글 본문'), findsOneWidget);
      expect(find.text('댓글을 불러오지 못했어요.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'S-32 draft composer save and submit expose governed moderation labels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryRepository();
      final controller = await _authenticatedController();

      await _pumpDetail(tester, repository: repository, controller: controller);

      await tester.ensureVisible(
        find.byKey(const ValueKey('local-signal-share-experience')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('local-signal-share-experience')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('local-signal-draft-title')),
        '공사 중 입구 변경',
      );
      await tester.enterText(
        find.byKey(const ValueKey('local-signal-draft-body')),
        '지난주에 직접 확인했습니다.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('local-signal-draft-save')));
      await tester.pumpAndSettle();

      expect(repository.createDraftCalls, 1);
      expect(
        find.byKey(const ValueKey('local-signal-draft-receipt-status')),
        findsOneWidget,
      );
      expect(
        find.textContaining('상태: 비공개 초안 · 검수: 검수 전 · 공개 범위: 비공개'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('local-signal-draft-submit')));
      await tester.pumpAndSettle();
      expect(repository.submitDraftCalls, 1);
      // The governed receipt stays readable before the flow closes.
      expect(
        find.textContaining('상태: 검수 요청됨 · 검수: 검수 중 · 공개 범위: 검수 후 공개 예정'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('local-signal-draft-done')));
      await tester.pumpAndSettle();
      expect(find.text('검수 요청을 보냈어요. 공개 전까지 원문은 비공개로 유지됩니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('S-32 draft save failure preserves the typed input', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository()..failDraftCreate = true;
    final controller = await _authenticatedController();

    await _pumpDetail(tester, repository: repository, controller: controller);

    await tester.ensureVisible(
      find.byKey(const ValueKey('local-signal-share-experience')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('local-signal-share-experience')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('local-signal-draft-title')),
      '저장 실패해도 남아 있어야',
    );
    await tester.enterText(
      find.byKey(const ValueKey('local-signal-draft-body')),
      '본문도 남아 있습니다.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('local-signal-draft-save')));
    await tester.pumpAndSettle();

    expect(repository.createDraftCalls, 1);
    expect(find.text('요청을 완료하지 못했어요. 입력 내용은 화면에 남아 있어요.'), findsOneWidget);
    expect(find.text('저장 실패해도 남아 있어야'), findsOneWidget);
    expect(find.text('본문도 남아 있습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'receipt labels localize known contract values and echo unknown ones',
    () {
      const draft = LocalSignalMutationReceipt(
        id: 'id',
        status: 'submitted',
        moderationState: 'pending',
        visibility: 'pending_review',
        title: 't',
        body: 'b',
      );
      expect(draft.statusLabel('ko'), '검수 요청됨');
      expect(draft.moderationStateLabel('en'), 'Under review');
      expect(draft.visibilityLabel('ja'), '公開前の審査待ち');
      expect(draft.statusLabel('zh-Hans'), '已提交审核');
      expect(draft.visibilityLabel('zh-Hant'), '待審核後公開');

      // Unknown wire values must render as the raw contract value, never an
      // invented moderation label.
      const unknown = LocalSignalMutationReceipt(
        id: 'id',
        status: 'quarantined',
        moderationState: 'escalated',
        visibility: 'redacted',
        title: 't',
        body: 'b',
      );
      expect(unknown.statusLabel('ko'), 'quarantined');
      expect(unknown.moderationStateLabel('en'), 'escalated');
      expect(unknown.visibilityLabel('ja'), 'redacted');
    },
  );
}

/// The detail page pops sheets through go_router, so the harness mounts it
/// inside a minimal router instead of a bare MaterialApp.
Future<void> _pumpDetail(
  WidgetTester tester, {
  required _MemoryRepository repository,
  LalaAuthController? controller,
}) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) => LocalSignalDetailPage(
              signalId: _signal.id,
              language: 'ko',
              initialConfig: _config,
              arguments: const LocalSignalDetailArguments.public(_signal),
              repository: repository,
              authController: controller,
            ),
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
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

const LocalSignalMutationReceipt _savedReceipt = LocalSignalMutationReceipt(
  id: '33333333-3333-4333-8333-333333333333',
  status: 'draft',
  moderationState: 'unreviewed',
  visibility: 'private',
  title: 'draft',
  body: 'body',
);

const LocalSignalMutationReceipt _submittedReceipt = LocalSignalMutationReceipt(
  id: '33333333-3333-4333-8333-333333333333',
  status: 'submitted',
  moderationState: 'pending',
  visibility: 'pending_review',
  title: 'draft',
  body: 'body',
);

Future<LalaAuthController> _authenticatedController() async {
  final controller = LalaAuthController(
    config: _enabledAuthConfig,
    gateway: _AuthenticatedGateway(),
    accountApi: const _FakeAccountApi(),
  );
  await controller.initialize();
  return controller;
}

const LalaAuthConfig _enabledAuthConfig = LalaAuthConfig(
  endpoint: 'https://auth.example.invalid',
  appId: 'public-test-client',
  apiAudience: 'https://api.example.invalid',
  redirectUri: 'cloud.lalanext.lala://callback',
);

class _AuthenticatedGateway implements LalaAuthGateway {
  @override
  Future<String?> accessToken(String resource) async => null;

  @override
  Future<bool> get isAuthenticated async => true;

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
}

class _FakeAccountApi implements LalaAccountApi {
  const _FakeAccountApi();

  @override
  Future<void> deleteMe({required String confirmation}) async {}

  @override
  Future<LalaMe> getMe() async => const LalaMe(
    userId: 'test-user',
    createdAt: '2026-09-03T00:00:00Z',
    authenticated: true,
  );
}

class _MemoryRepository implements LocalSignalParticipationRepository {
  final List<bool> usefulCalls = <bool>[];
  final List<bool> savedCalls = <bool>[];
  final List<String> reportCalls = <String>[];
  final List<String> commentBodies = <String>[];
  int createDraftCalls = 0;
  int submitDraftCalls = 0;
  bool failCommentsLoad = false;
  bool failCommentSubmission = false;
  bool failDraftCreate = false;

  @override
  Future<LocalSignalPublicItem> getSignal(
    String signalId,
    String language,
  ) async => _signal;

  @override
  Future<LocalSignalCommentFeed> getComments(
    String signalId,
    String language,
  ) async {
    if (failCommentsLoad) {
      throw Exception('comments unavailable');
    }
    return LocalSignalCommentFeed(
      items: <LocalSignalPublicComment>[
        const LocalSignalPublicComment(
          id: '22222222-2222-4222-8222-222222222222',
          sourceLanguage: 'ko',
          body: '댓글 본문',
          createdAt: '2026-09-03T00:30:00Z',
        ),
        if (commentBodies.isNotEmpty)
          LocalSignalPublicComment(
            id: '44444444-4444-4444-8444-444444444444',
            sourceLanguage: 'ko',
            body: commentBodies.last,
            createdAt: '2026-09-04T00:30:00Z',
          ),
      ],
      nextCursor: null,
      hasMore: false,
    );
  }

  @override
  Future<void> setUseful(String signalId, bool active) async {
    usefulCalls.add(active);
  }

  @override
  Future<void> setSaved(String signalId, bool active) async {
    savedCalls.add(active);
  }

  @override
  Future<void> addComment(
    String signalId,
    String sourceLanguage,
    String body,
  ) async {
    if (failCommentSubmission) {
      throw Exception('comment rejected');
    }
    commentBodies.add(body);
  }

  @override
  Future<void> report(String signalId, String reasonCode) async {
    reportCalls.add(reasonCode);
  }

  @override
  Future<LocalSignalMutationReceipt> createDraft(
    LocalSignalDraftInput input,
  ) async {
    createDraftCalls += 1;
    if (failDraftCreate) {
      throw Exception('draft create failed');
    }
    return _savedReceipt;
  }

  @override
  Future<LocalSignalMutationReceipt> updateDraft(
    String signalId,
    LocalSignalDraftInput input,
  ) async => _savedReceipt;

  @override
  Future<LocalSignalMutationReceipt> submitDraft(String signalId) async {
    submitDraftCalls += 1;
    return _submittedReceipt;
  }

  @override
  Future<void> deleteDraft(String signalId) async {}

  @override
  void close() {}
}
