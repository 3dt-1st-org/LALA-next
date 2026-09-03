import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/auth/auth_controller.dart';
import 'package:lala_next_app/auth/logto_auth_gateway.dart';
import 'package:lala_next_app/core/config/app_config.dart';
import 'package:lala_next_app/features/local_signals/data/local_signal_participation_repository.dart';
import 'package:lala_next_app/features/local_signals/domain/local_signal_public.dart';
import 'package:lala_next_app/features/local_signals/presentation/pages/local_signal_detail_page.dart';
import 'package:lala_next_app/features/local_signals/presentation/widgets/local_signal_contribution_composer.dart';

void main() {
  testWidgets(
    'contribute page shows an honest sign-in gate before any draft field',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _guestController();

      await _pumpContribute(tester, controller: controller);

      expect(
        find.byKey(const ValueKey('local-signal-auth-connect')),
        findsOneWidget,
      );
      expect(find.text('로그인하고 로컬 신호를 남겨 주세요'), findsOneWidget);
      // No authoring surface exists for a guest.
      expect(
        find.byKey(const ValueKey('local-signal-draft-title')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('local-signal-draft-save')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'contribute page gate performs a real sign-in and then shows the composer',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = _GuestThenSignInGateway();
      final controller = await _controllerWith(gateway);

      await _pumpContribute(tester, controller: controller);
      await tester.tap(find.byKey(const ValueKey('local-signal-auth-connect')));
      await tester.pumpAndSettle();

      // Explicit confirm dialog first.
      expect(find.text('로그인이 필요해요'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('local-signal-auth-sign-in')));
      await tester.pumpAndSettle();

      // Signed-in state rebuilds the page into the composer.
      expect(
        find.byKey(const ValueKey('local-signal-draft-title')),
        findsOneWidget,
      );
      expect(gateway.signInCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('contribute page without a usable auth controller stays honest', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpContribute(tester, controller: null);

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('local-signal-auth-connect')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('local-signal-draft-title')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'S-32 guest entry shows the sign-in requirement instead of the composer',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = await _guestController();

      await _pumpDetail(
        tester,
        repository: _MemoryRepository(),
        controller: controller,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('local-signal-share-experience')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('local-signal-share-experience')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('로그인이 필요해요'), findsOneWidget);
      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-signal-draft-title')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'coarse-region contribution sends district locality without coordinates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryRepository();
      final controller = await _authenticatedController();

      await _pumpContribute(
        tester,
        repository: repository,
        controller: controller,
        region: (code: 'busan-haeundae', label: '해운대구'),
      );

      expect(find.text('지역 맥락: 해운대구'), findsOneWidget);
      await _fillAndSave(tester);

      final payload = repository.createDraftInputs.single;
      expect(payload['locality_level'], 'district');
      expect(payload['locality_code'], 'busan-haeundae');
      expect(payload['place_links'], isNull);
      // Precise coordinates must never enter the draft contract.
      expect(payload.containsKey('latitude'), isFalse);
      expect(payload.containsKey('longitude'), isFalse);
      expect(payload.containsKey('lat'), isFalse);
      expect(payload.containsKey('lng'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'place contribution from S-32 sends a primary place link and no locality',
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

      await _fillAndSave(tester);

      final payload = repository.createDraftInputs.single;
      expect(payload['locality_level'], 'place');
      expect(payload['place_links'], <Map<String, String>>[
        <String, String>{'place_id': 'place-1', 'relation': 'primary'},
      ]);
      expect(payload.containsKey('locality_code'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('region-less contribution states the honest no-context truth', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository();
    final controller = await _authenticatedController();

    await _pumpContribute(
      tester,
      repository: repository,
      controller: controller,
    );

    expect(find.text('지역 맥락 없음 · 전국 대상 관찰로 저장돼요'), findsOneWidget);
    await _fillAndSave(tester);

    final payload = repository.createDraftInputs.single;
    expect(payload['locality_level'], 'district');
    expect(payload.containsKey('locality_code'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ja UI submits an English source language and stays KO/EN truthful',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryRepository();
      final controller = await _authenticatedController();

      await _pumpContribute(
        tester,
        repository: repository,
        controller: controller,
        language: 'ja',
        region: (code: 'busan-haeundae', label: 'Haeundae-gu'),
      );

      expect(find.textContaining('原文投稿は韓国語と英語に対応'), findsOneWidget);
      // Visitor locale must not leak Korean composer copy.
      expect(find.text('경험 초안'), findsNothing);
      expect(find.text('지역 맥락: 해운대구'), findsNothing);

      await _fillAndSave(
        tester,
        title: 'Quiet at sunset',
        body: 'Visited last week.',
      );
      expect(repository.createDraftInputs.single['source_language'], 'en');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save with empty fields gives validation feedback without a request',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryRepository();
      final controller = await _authenticatedController();

      await _pumpContribute(
        tester,
        repository: repository,
        controller: controller,
      );

      await tester.tap(find.byKey(const ValueKey('local-signal-draft-save')));
      await tester.pumpAndSettle();

      expect(find.text('제목을 입력해 주세요'), findsOneWidget);
      expect(find.text('본문을 입력해 주세요'), findsOneWidget);
      expect(repository.createDraftCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed save keeps input and a retry succeeds', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository()..failDraftCreate = true;
    final controller = await _authenticatedController();

    await _pumpContribute(
      tester,
      repository: repository,
      controller: controller,
    );

    await _fillAndSave(tester);
    expect(repository.createDraftCalls, 1);
    expect(
      find.byKey(const ValueKey('local-signal-draft-error')),
      findsOneWidget,
    );
    expect(find.text('저장 실패해도 남아 있어야'), findsOneWidget);

    repository.failDraftCreate = false;
    await tester.tap(find.byKey(const ValueKey('local-signal-draft-save')));
    await tester.pumpAndSettle();

    expect(repository.createDraftCalls, 2);
    expect(
      find.byKey(const ValueKey('local-signal-draft-error')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a governed write-disabled rejection renders the honest unavailable copy',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryRepository()
        ..draftCreateError = const LalaApiException(
          code: 'LOCAL_SIGNALS_DISABLED',
          message: 'disabled',
          statusCode: 503,
          retryable: false,
        );
      final controller = await _authenticatedController();

      await _pumpContribute(
        tester,
        repository: repository,
        controller: controller,
      );

      await _fillAndSave(tester);

      expect(
        find.text('지금은 로컬 신호 작성을 받고 있지 않아요. 입력 내용은 화면에 남아 있어요.'),
        findsOneWidget,
      );
      expect(find.text('저장 실패해도 남아 있어야'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'submit shows the governed receipt, then Done finishes the flow',
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

      await _fillAndSave(tester);
      expect(
        find.textContaining('상태: 비공개 초안 · 검수: 검수 전 · 공개 범위: 비공개'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('local-signal-draft-submit')));
      await tester.pumpAndSettle();
      expect(repository.submitDraftCalls, 1);
      // The receipt stays visible for review before the flow closes.
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

  testWidgets('a double submit tap results in exactly one request', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository()..submitGate = Completer<void>();
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
    await _fillAndSave(tester);

    await tester.tap(find.byKey(const ValueKey('local-signal-draft-submit')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('local-signal-draft-submit')),
      warnIfMissed: false,
    );
    await tester.pump();

    repository.submitGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.submitDraftCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete requires explicit confirmation', (tester) async {
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
    await _fillAndSave(tester);

    await tester.tap(find.byKey(const ValueKey('local-signal-draft-delete')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('local-signal-draft-delete-confirm')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('local-signal-draft-delete-cancel')),
    );
    await tester.pumpAndSettle();
    expect(repository.deleteDraftCalls, 0);

    await tester.tap(find.byKey(const ValueKey('local-signal-draft-delete')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('local-signal-draft-delete-action')),
    );
    await tester.pumpAndSettle();

    expect(repository.deleteDraftCalls, 1);
    // No submission snackbar after a delete.
    expect(find.text('검수 요청을 보냈어요. 공개 전까지 원문은 비공개로 유지됩니다.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dirty sheet close demands confirmation and keeps text on keep-editing',
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
        '닫기 전 확인 필요',
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('local-signal-composer-close')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-signal-composer-discard-confirm')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('local-signal-composer-keep-editing')),
      );
      await tester.pumpAndSettle();
      // Text preserved, sheet still open.
      expect(find.text('닫기 전 확인 필요'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('local-signal-draft-title')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('local-signal-composer-close')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('local-signal-composer-discard')),
      );
      await tester.pumpAndSettle();
      // Sheet closed without the submitted snackbar.
      expect(
        find.byKey(const ValueKey('local-signal-draft-title')),
        findsNothing,
      );
      expect(find.text('검수 요청을 보냈어요. 공개 전까지 원문은 비공개로 유지됩니다.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('contribute page back button runs the same dirty-input guard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository();
    final controller = await _authenticatedController();

    await _pumpContributeRoute(
      tester,
      repository: repository,
      controller: controller,
    );
    await tester.enterText(
      find.byKey(const ValueKey('local-signal-draft-title')),
      '뒤로 가기 확인',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('local-signal-detail-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('local-signal-composer-discard-confirm')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('local-signal-composer-keep-editing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('뒤로 가기 확인'), findsOneWidget);
    expect(find.text('내 경험 보내기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('local-signal-detail-back')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('local-signal-composer-discard')),
    );
    await tester.pumpAndSettle();
    expect(find.text('내 경험 보내기'), findsNothing);
    expect(find.text('home-marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contribute page and sheet stay overflow-free at 200% text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryRepository();
    final controller = await _authenticatedController();

    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpContribute(
      tester,
      repository: repository,
      controller: controller,
      region: (code: 'busan-haeundae', label: '해운대구'),
    );
    expect(tester.takeException(), isNull);

    await _fillAndSave(tester);
    // The save must genuinely land at 200% too: the governed receipt line
    // appears (proving the press reached the button) and stays overflow-free.
    expect(
      find.byKey(const ValueKey('local-signal-draft-receipt-status')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _fillAndSave(
  WidgetTester tester, {
  String title = '저장 실패해도 남아 있어야',
  String body = '본문도 남아 있습니다.',
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('local-signal-draft-title')),
    title,
  );
  await tester.enterText(
    find.byKey(const ValueKey('local-signal-draft-body')),
    body,
  );
  await tester.pump();
  // At large text scales the save button sits below the fold of the composer
  // scroll view; scrolling it into view keeps the tap a real press instead
  // of a silently missed off-screen pointer event.
  final saveFinder = find.byKey(const ValueKey('local-signal-draft-save'));
  await tester.ensureVisible(saveFinder);
  await tester.pumpAndSettle();
  await tester.tap(saveFinder, warnIfMissed: true);
  await tester.pumpAndSettle();
}

const LalaAppConfig _config = LalaAppConfig(
  baseUri: 'https://api.example.test',
);

/// Mounts the contribute-mode detail page as the only route.
Future<void> _pumpContribute(
  WidgetTester tester, {
  _MemoryRepository? repository,
  LalaAuthController? controller,
  String language = 'ko',
  LocalSignalRegionContributionContext? region,
}) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) => LocalSignalDetailPage(
              signalId: 'contribute',
              language: language,
              initialConfig: _config,
              arguments: LocalSignalDetailArguments.contribute(region: region),
              authController: controller,
              repository: repository,
            ),
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mounts home + contribute routes so the page-owned back button has a real
/// route to pop.
Future<void> _pumpContributeRoute(
  WidgetTester tester, {
  required _MemoryRepository repository,
  required LalaAuthController controller,
}) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: OutlinedButton(
                  key: const ValueKey('contribute-entry'),
                  onPressed: () => context.push('/contribute'),
                  child: const Text('home-marker'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/contribute',
            builder: (context, state) => LocalSignalDetailPage(
              signalId: 'contribute',
              language: 'ko',
              initialConfig: _config,
              arguments: const LocalSignalDetailArguments.contribute(),
              authController: controller,
              repository: repository,
            ),
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('contribute-entry')));
  await tester.pumpAndSettle();
}

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

const LalaAuthConfig _enabledAuthConfig = LalaAuthConfig(
  endpoint: 'https://auth.example.invalid',
  appId: 'public-test-client',
  apiAudience: 'https://api.example.invalid',
  redirectUri: 'cloud.lalanext.lala://callback',
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

Future<LalaAuthController> _guestController() async {
  final controller = LalaAuthController(
    config: _enabledAuthConfig,
    gateway: _GuestThenSignInGateway(),
    accountApi: const _FakeAccountApi(),
  );
  await controller.initialize();
  return controller;
}

Future<LalaAuthController> _controllerWith(
  _GuestThenSignInGateway gateway,
) async {
  final controller = LalaAuthController(
    config: _enabledAuthConfig,
    gateway: gateway,
    accountApi: const _FakeAccountApi(),
  );
  await controller.initialize();
  return controller;
}

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

/// Guests flip to authenticated only through a real signIn() call, mirroring
/// an actual Logto round trip without simulating one in product code.
class _GuestThenSignInGateway implements LalaAuthGateway {
  bool signedIn = false;
  int signInCalls = 0;

  @override
  Future<String?> accessToken(String resource) async => null;

  @override
  Future<bool> get isAuthenticated async => signedIn;

  @override
  Future<void> signIn() async {
    signInCalls += 1;
    signedIn = true;
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
  }
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
  final List<Map<String, dynamic>> createDraftInputs = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> updateDraftInputs = <Map<String, dynamic>>[];
  int createDraftCalls = 0;
  int submitDraftCalls = 0;
  int deleteDraftCalls = 0;
  bool failDraftCreate = false;
  Object? draftCreateError;

  /// When set, submit waits for this gate before completing (double-submit
  /// guard coverage).
  Completer<void>? submitGate;

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
    items: <LocalSignalPublicComment>[],
    nextCursor: null,
    hasMore: false,
  );

  @override
  Future<void> setUseful(String signalId, bool active) async {}

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
  ) async {
    createDraftCalls += 1;
    if (draftCreateError != null) throw draftCreateError!;
    if (failDraftCreate) throw Exception('draft create failed');
    createDraftInputs.add(input.toJson());
    return _savedReceipt;
  }

  @override
  Future<LocalSignalMutationReceipt> updateDraft(
    String signalId,
    LocalSignalDraftInput input,
  ) async {
    updateDraftInputs.add(input.toJson());
    return _savedReceipt;
  }

  @override
  Future<LocalSignalMutationReceipt> submitDraft(String signalId) async {
    if (submitGate != null) await submitGate!.future;
    submitDraftCalls += 1;
    return _submittedReceipt;
  }

  @override
  Future<void> deleteDraft(String signalId) async {
    deleteDraftCalls += 1;
  }

  @override
  void close() {}
}
