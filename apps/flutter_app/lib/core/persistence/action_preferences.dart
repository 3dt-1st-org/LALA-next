// V5-B action cold-start persistence: the saved-place SET + per-slot VISIT map
// (§V5-B D1/D2), under the namespaced key prefix `lala.v5.*`.
//
// This module is a structural mirror of cross_tab_preferences.dart (V1 Lane 2):
// app-owned encoder, versioned envelope, failure-safe read → a store error, corrupt
// JSON, or version mismatch degrades to a clean empty snapshot so the app always
// starts. A `*Backend` interface backed by SharedPreferences makes it unit-testable
// without the plugin. The store owns serialization — the generated client has no
// toJson and V5-B adds none (contract B6).
//
// Privacy contract: ONLY opaque place-id Strings and the slot-period → status map
// are persisted. No coordinates, no PII (contract A2/A8 privacy scope: place-id only).
//
// Offline contract: the store is the authority for SAVE/VISIT on the normal path.
// No network call is made here or by its listeners (contract hard invariant #1).
// The V5-A backend methods (listSavedPlaces/checkInSlot/…) are a V7 live-sync seam,
// NOT invoked by V5-B (§3 BLOCKED_EXTERNAL).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/slot_visit_store.dart';

/// Versioned key prefix so V5 action keys never collide with onboarding's
/// `lala.onboarding.v1.*`, cross-tab's `lala.crosstab.v1.*`, or any future schema.
const String kActionStoragePrefix = 'lala.v5.';

const String _kSavedPlaces = '${kActionStoragePrefix}savedPlaces';
const String _kSlotVisits = '${kActionStoragePrefix}slotVisits';

/// Envelope version. Bumping makes every older persisted envelope read as
/// "version mismatch → null" (the sanctioned stale-discard path, B3).
const int kActionEnvelopeVersion = 1;

/// Immutable snapshot of the persisted V5 action state.
@immutable
class ActionSnapshot {
  const ActionSnapshot({
    this.savedPlaceIds = const <String>{},
    this.slotVisits = const <String, String>{},
  });

  final Set<String> savedPlaceIds;

  /// `"$planDate:$slotPeriod" → "visited"`. Only non-default entries are stored
  /// (planned is the implicit default — contract A9 honest empty).
  final Map<String, String> slotVisits;
}

/// Storage seam so persistence is unit-testable without the SharedPreferences
/// plugin, mirroring [CrossTabPreferencesBackend]. An in-memory fake that
/// implements this interface satisfies the tests.
abstract interface class ActionPreferencesBackend {
  Future<String?> getString(String key);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

/// [ActionPreferencesBackend] backed by SharedPreferences (production).
class SharedPreferencesActionBackend implements ActionPreferencesBackend {
  SharedPreferencesActionBackend(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// Reads + writes the cold-start V5 action snapshot.
///
/// All reads are failure-safe: a store error, corrupt JSON, or a version mismatch
/// degrades to a clean [ActionSnapshot] (the app still starts). Writes propagate
/// errors to the caller so the in-memory holder stays the authority regardless of
/// durability.
class ActionPreferences {
  ActionPreferences(this._backend);

  final ActionPreferencesBackend _backend;

  /// Production instance backed by SharedPreferences. Shares the same singleton
  /// as onboarding/cross-tab so every store lives in one process-local file.
  static Future<ActionPreferences> createDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return ActionPreferences(SharedPreferencesActionBackend(prefs));
  }

  /// Loads the persisted snapshot. Never throws — a store failure, corrupt JSON,
  /// or version mismatch degrades to a clean empty snapshot (B2/B3).
  Future<ActionSnapshot> load() async {
    String? savedRaw;
    String? visitsRaw;
    try {
      savedRaw = await _backend.getString(_kSavedPlaces);
      visitsRaw = await _backend.getString(_kSlotVisits);
    } on Object {
      return const ActionSnapshot();
    }
    return ActionSnapshot(
      savedPlaceIds: _decodeSavedPlaces(savedRaw),
      slotVisits: _decodeSlotVisits(visitsRaw),
    );
  }

  /// Persists (or clears, when [ids] is empty) the saved-place set as a versioned
  /// JSON envelope. Encoding is app-owned (the generated client has no toJson).
  Future<void> writeSavedPlaces(Set<String> ids) async {
    if (ids.isEmpty) {
      await _backend.remove(_kSavedPlaces);
    } else {
      await _backend.setString(_kSavedPlaces, _encodeSavedPlacesEnvelope(ids));
    }
  }

  /// Persists (or clears, when [visits] is empty) the slot-visit map as a
  /// versioned JSON envelope.
  Future<void> writeSlotVisits(Map<String, String> visits) async {
    if (visits.isEmpty) {
      await _backend.remove(_kSlotVisits);
    } else {
      await _backend.setString(_kSlotVisits, _encodeSlotVisitsEnvelope(visits));
    }
  }

  /// Clears every persisted V5 action key (re-onboarding / reset).
  Future<void> clearAll() async {
    await _backend.remove(_kSavedPlaces);
    await _backend.remove(_kSlotVisits);
  }

  static Set<String> _decodeSavedPlaces(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <String>{};
      }
      if (decoded['v'] != kActionEnvelopeVersion) {
        // Stale schema → ignore (B3 epoch guard).
        return const <String>{};
      }
      final ids = decoded['ids'];
      if (ids is! List) {
        return const <String>{};
      }
      return ids.whereType<String>().where((id) => id.isNotEmpty).toSet();
    } on Object {
      // Corrupt JSON → empty, no crash (B2).
      return const <String>{};
    }
  }

  static Map<String, String> _decodeSlotVisits(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <String, String>{};
      }
      if (decoded['v'] != kActionEnvelopeVersion) {
        return const <String, String>{};
      }
      final visits = decoded['visits'];
      if (visits is! Map) {
        return const <String, String>{};
      }
      final result = <String, String>{};
      visits.forEach((key, value) {
        if (key is String && value is String && value.isNotEmpty) {
          result[key] = value;
        }
      });
      return result;
    } on Object {
      return const <String, String>{};
    }
  }

  static String _encodeSavedPlacesEnvelope(Set<String> ids) {
    return jsonEncode(<String, dynamic>{
      'v': kActionEnvelopeVersion,
      'ids': ids.toList()..sort(),
    });
  }

  static String _encodeSlotVisitsEnvelope(Map<String, String> visits) {
    return jsonEncode(<String, dynamic>{
      'v': kActionEnvelopeVersion,
      'visits': visits,
    });
  }
}

// ---------------------------------------------------------------------------
// Cold-start hydration gateway: write-through listeners + epoch guard.
//
// The holders (SavedPlaceStore / SlotVisitStore) own no persistence, so this
// module attaches its OWN listeners to the holders' listentables and restores via
// their public restore() API on cold start. An epoch guard suppresses stale
// hydration: if a fresh change lands during the load window, the persisted value
// must NOT clobber it. Structural mirror of CrossTabPersistence.
// ---------------------------------------------------------------------------

/// Attaches V5 write-through persistence and performs cold-start hydration of
/// [SavedPlaceStore] and [SlotVisitStore].
class ActionPersistence {
  ActionPersistence._();

  /// Monotonic counter incremented on every holder change. Captured at
  /// load-start; if it advanced by the time load resolves, a fresh value appeared
  /// and the stale persisted value is suppressed.
  static int _epoch = 0;

  static VoidCallback? _savedPlacesDisposer;
  static VoidCallback? _slotVisitsDisposer;
  static bool _attached = false;
  static ActionPreferences? _preferences;

  /// Attaches write-through listeners and hydrates the holders from [prefs].
  static Future<void> attachAndHydrate(ActionPreferences prefs) async {
    detach();
    _attached = true;
    _preferences = prefs;
    final epochAtLoadStart = _epoch;

    _savedPlacesDisposer = _listen(
      SavedPlaceStore.listenable,
      () => unawaited(
        _safeWrite(prefs.writeSavedPlaces(SavedPlaceStore.current)),
      ),
    );
    _slotVisitsDisposer = _listen(
      SlotVisitStore.listenable,
      () =>
          unawaited(_safeWrite(prefs.writeSlotVisits(SlotVisitStore.current))),
    );

    final snapshot = await prefs.load();

    // Detached during the load window — nothing to apply.
    if (!_attached) {
      return;
    }
    // A fresh value appeared during the load window — do not clobber it.
    if (_epoch != epochAtLoadStart) {
      return;
    }
    SavedPlaceStore.restore(snapshot.savedPlaceIds);
    SlotVisitStore.restore(snapshot.slotVisits);
  }

  /// Detaches the write-through listeners (test isolation / failure path).
  static void detach() {
    _savedPlacesDisposer?.call();
    _slotVisitsDisposer?.call();
    _savedPlacesDisposer = null;
    _slotVisitsDisposer = null;
    _attached = false;
    _preferences = null;
  }

  /// Clears the persisted and process-local guest action state.
  static Future<void> clearAndFlush() async {
    SavedPlaceStore.clear();
    SlotVisitStore.clear();
    await _preferences?.clearAll();
  }

  static VoidCallback _listen(
    ValueListenable<dynamic> listenable,
    void Function() body,
  ) {
    void listener() {
      _epoch++;
      body();
    }

    listenable.addListener(listener);
    return () => listenable.removeListener(listener);
  }

  static Future<void> _safeWrite(Future<void> future) async {
    try {
      await future;
    } on Object {
      // Best-effort persistence; the in-memory holder stays authoritative.
    }
  }
}
