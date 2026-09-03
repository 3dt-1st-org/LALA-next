import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/features/preferences/data/travel_preferences_remote.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/preference_sync_conflict_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kTravelPreferencesStorageKey: jsonEncode(
        const TravelPreferences(
          interests: <TravelInterest>{TravelInterest.localFood},
          allergens: <Allergen>{Allergen.shellfish},
        ).toJson(),
      ),
      kTravelPreferencesUpdatedAtKey: '2026-09-03T01:02:03Z',
    });
  });

  testWidgets('S-59 compares versions and applies an explicit account choice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final remote = _MemoryRemote(
      const TravelPreferences(
        interests: <TravelInterest>{TravelInterest.history},
        avoidStairs: true,
      ),
    );
    final store = TravelPreferencesStore();
    await store.connectAccount(remote);
    expect(store.syncStatus, TravelPreferencesSyncStatus.conflict);

    await tester.pumpWidget(
      MaterialApp(
        home: PreferenceSyncConflictPage(language: 'ko', store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('preference-sync-conflict-page')),
      findsOneWidget,
    );
    expect(find.text('자동으로 덮어쓰지 않았어요'), findsOneWidget);
    expect(find.text('다른 항목'), findsOneWidget);
    expect(store.deviceUpdatedAt, '2026-09-03T01:02:03Z');
    expect(store.accountUpdatedAt, '2026-09-03T02:03:04Z');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('sync-use-account')));
    await tester.pumpAndSettle();

    expect(store.syncStatus, TravelPreferencesSyncStatus.synced);
    expect(store.value.interests, <TravelInterest>{TravelInterest.history});
    expect(store.value.avoidStairs, isTrue);
    expect(store.deviceUpdatedAt, '2026-09-03T02:03:04Z');
  });
}

class _MemoryRemote implements TravelPreferencesRemote {
  _MemoryRemote(this.preferences);

  final TravelPreferences preferences;

  @override
  Future<TravelPreferencesRemoteDocument?> get() async =>
      TravelPreferencesRemoteDocument(
        preferences: preferences,
        revision: 7,
        updatedAt: '2026-09-03T02:03:04Z',
      );

  @override
  Future<TravelPreferencesRemoteDocument> put({
    required TravelPreferences preferences,
    required int expectedRevision,
  }) async => TravelPreferencesRemoteDocument(
    preferences: preferences,
    revision: expectedRevision + 1,
    updatedAt: '2026-09-03T03:04:05Z',
  );
}
