// Wave-1 cold-start persistence: focused unit tests for OnboardingPreferences.
//
// The storage seam (OnboardingPreferencesBackend) lets us prove the on-disk
// contract without the SharedPreferences plugin:
//  - round-trip restore of completed + language + tourist type + valid manual region
//  - a clean first-run snapshot when the store is empty
//  - an invalid/removed persisted manual region id is dropped (and the key cleaned)
//  - storage read failure degrades to a clean first-run snapshot (never throws)
//  - storage write failure propagates so the in-memory layer can stay consistent
//  - clearAll wipes every persisted key
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/core/persistence/onboarding_preferences.dart';

void main() {
  group('OnboardingPreferences.load', () {
    test('empty store yields a clean first-run snapshot', () async {
      final prefs = OnboardingPreferences(_MemoryBackend());
      final snapshot = await prefs.load();
      expect(snapshot.completed, isFalse);
      expect(snapshot.language, 'ko');
      expect(snapshot.touristTypeCode, kTouristTypeCodeLocal);
      expect(snapshot.manualRegionId, isNull);
    });

    test(
      'round-trip restores completed + language + tourist type + valid manual region',
      () async {
        final backend = _MemoryBackend();
        final prefs = OnboardingPreferences(backend);
        await prefs.writeOnboarding(
          completed: true,
          language: 'en',
          touristTypeCode: kTouristTypeCodeForeign,
        );
        await prefs.writeManualRegionId('busan-haeundae');

        // A fresh reader over the same store sees the persisted values.
        final snapshot = await OnboardingPreferences(backend).load();
        expect(snapshot.completed, isTrue);
        expect(snapshot.language, 'en');
        expect(snapshot.touristTypeCode, kTouristTypeCodeForeign);
        expect(snapshot.manualRegionId, 'busan-haeundae');
      },
    );

    test('round-trip keeps the local/korean defaults stable', () async {
      final backend = _MemoryBackend();
      final prefs = OnboardingPreferences(backend);
      await prefs.writeOnboarding(
        completed: true,
        language: 'ko',
        touristTypeCode: kTouristTypeCodeLocal,
      );

      final snapshot = await OnboardingPreferences(backend).load();
      expect(snapshot.language, 'ko');
      expect(snapshot.touristTypeCode, kTouristTypeCodeLocal);
    });

    test(
      'invalid persisted manual region id is dropped and the key is cleared',
      () async {
        final key = '${kOnboardingStoragePrefix}manualRegionId';
        final backend = _MemoryBackend({key: 'this-region-no-longer-exists'});
        final snapshot = await OnboardingPreferences(backend).load();
        // Unknown id must not crash and must not masquerade as a real region.
        expect(snapshot.manualRegionId, isNull);
        // The bad value is removed so the next load is clean.
        expect(backend.store[key], isNull);
      },
    );

    test(
      'storage read failure degrades to a clean first-run snapshot',
      () async {
        final prefs = OnboardingPreferences(_FailingBackend());
        // load() must not throw; it returns a safe default instead.
        final snapshot = await prefs.load();
        expect(snapshot.completed, isFalse);
        expect(snapshot.manualRegionId, isNull);
      },
    );
  });

  group('OnboardingPreferences writes', () {
    test(
      'write failure propagates so the caller can keep the UI consistent',
      () async {
        final prefs = OnboardingPreferences(_FailingBackend());
        await expectLater(
          prefs.writeOnboarding(
            completed: true,
            language: 'en',
            touristTypeCode: kTouristTypeCodeForeign,
          ),
          throwsA(isA<Object>()),
        );
      },
    );

    test('writeManualRegionId(null) removes the manual region key', () async {
      final key = '${kOnboardingStoragePrefix}manualRegionId';
      final backend = _MemoryBackend({key: 'busan-haeundae'});
      final prefs = OnboardingPreferences(backend);
      await prefs.writeManualRegionId(null);
      expect(backend.store[key], isNull);
    });
  });

  group('OnboardingPreferences.clearAll', () {
    test('clears every persisted key', () async {
      final backend = _MemoryBackend();
      final prefs = OnboardingPreferences(backend);
      await prefs.writeOnboarding(
        completed: true,
        language: 'en',
        touristTypeCode: kTouristTypeCodeForeign,
      );
      await prefs.writeManualRegionId('busan-haeundae');

      await prefs.clearAll();

      final snapshot = await OnboardingPreferences(backend).load();
      expect(snapshot.completed, isFalse);
      expect(snapshot.language, 'ko');
      expect(snapshot.touristTypeCode, kTouristTypeCodeLocal);
      expect(snapshot.manualRegionId, isNull);
    });
  });
}

/// In-memory OnboardingPreferencesBackend for deterministic, plugin-free tests.
class _MemoryBackend implements OnboardingPreferencesBackend {
  _MemoryBackend([Map<String, Object?>? seed])
    : store = Map<String, Object?>.from(seed ?? <String, Object?>{});

  final Map<String, Object?> store;

  @override
  Future<bool?> getBool(String key) async => store[key] as bool?;

  @override
  Future<String?> getString(String key) async => store[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async {
    store[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    store.remove(key);
  }
}

/// OnboardingPreferencesBackend whose store is permanently unavailable.
class _FailingBackend implements OnboardingPreferencesBackend {
  Future<Never> _fail() async => throw StateError('storage unavailable');

  @override
  Future<bool?> getBool(String key) => _fail();

  @override
  Future<String?> getString(String key) => _fail();

  @override
  Future<void> setBool(String key, bool value) => _fail();

  @override
  Future<void> setString(String key, String value) => _fail();

  @override
  Future<void> remove(String key) => _fail();
}
