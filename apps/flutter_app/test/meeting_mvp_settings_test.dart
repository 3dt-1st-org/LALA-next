import 'package:go_router/go_router.dart';
import 'package:lala_next_app/features/trip_library/presentation/pages/trip_settings_page.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lala_next_app/app/lala_product_scope.dart';
import 'package:lala_next_app/features/profile/presentation/pages/profile_page.dart';
import 'package:lala_next_app/features/preferences/data/travel_preferences_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/preferences/presentation/travel_preferences_page.dart';

class FailingTripStore extends TripLibraryStore {
  @override
  Future<void> saveOverride(String planDate, dynamic value) async {
    throw StateError('storage unavailable');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('failed condition save remains open and can be retried', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LalaProductScope(
          meetingMvp: true,
          child: TripSettingsPage(
            planDate: '2026-10-01',
            tripStore: FailingTripStore(),
            preferencesStore: TravelPreferencesStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trip-settings-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trip-settings-page')), findsOneWidget);
    expect(find.text('설정을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('trip-settings-save')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'plan conditions expose supported controls and return apply result',
    (tester) async {
      final store = TripLibraryStore();
      final prefs = TravelPreferencesStore();
      bool? applied;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  applied = await context.push<bool>('/conditions');
                },
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: '/conditions',
            builder: (_, state) => TripSettingsPage(
              planDate: '2026-10-01',
              tripStore: store,
              preferencesStore: prefs,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              LalaProductScope(meetingMvp: true, child: child!),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('도보 범위'), findsOneWidget);
      expect(find.text('날씨 민감도'), findsOneWidget);
      expect(find.text('실내·야외 선호'), findsOneWidget);
      expect(find.text('예산'), findsNothing);
      expect(find.text('여행 속도'), findsNothing);
      await tester.ensureVisible(find.text('높음'));
      await tester.tap(find.text('높음'));
      await tester.tap(find.byKey(const ValueKey('trip-settings-save')));
      await tester.pumpAndSettle();
      expect(applied, isTrue);
      expect(
        store.overrideFor('2026-10-01').weatherSensitivity,
        WeatherSensitivity.high,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings saves audio preferences without duplicate trip controls',
    (tester) async {
      final store = TravelPreferencesStore();
      await store.ensureLoaded();
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              LalaProductScope(meetingMvp: true, child: child!),
          home: ProfilePage(preferencesStore: store, settingsOnly: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-saved-places-entry')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('profile-past-trips-entry')),
        findsNothing,
      );
      expect(find.byType(FilterChip), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-docent-entry')));
      await tester.pumpAndSettle();
      final chip = find.text('1.2x');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(store.value.narrationSpeed, 1.2);
      final restored = TravelPreferencesStore();
      await restored.ensureLoaded();
      expect(restored.value.narrationSpeed, 1.2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'MVP keeps dietary safety controls and hides restaurant assistance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              LalaProductScope(meetingMvp: true, child: child!),
          home: const FoodPreferencesPage(
            language: 'ko',
            initialValue: TravelPreferences(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('알레르기·민감 식품'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('알레르기·민감 식품'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('avoid-ingredients-field')),
        150,
        scrollable: scrollable,
      );
      expect(
        find.byKey(const ValueKey('restaurant-communication-card')),
        findsNothing,
      );
      expect(find.text('주문 요청'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
