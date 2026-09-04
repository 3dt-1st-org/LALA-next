import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lala_next_app/core/persistence/cross_tab_preferences.dart';
import 'package:lala_next_app/core/state/plan_context_store.dart';
import 'package:lala_next_app/core/state/saved_place_store.dart';
import 'package:lala_next_app/core/state/slot_visit_store.dart';
import 'package:lala_next_app/features/preferences/domain/travel_preferences.dart';
import 'package:lala_next_app/features/trip_library/data/trip_library_remote.dart';
import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';

const String kTripLibraryStorageKey = 'lala.trip_library.v1';

typedef TripLibraryPreferencesFactory = Future<SharedPreferences> Function();

enum TripLibrarySyncStatus { localOnly, syncing, synced, conflict, error }

/// Device-first trip state with optional account reconciliation.
///
/// Local writes always complete first. Account failures are visible and
/// retryable, but cannot erase the device copy. Only soft date overrides and
/// bounded visit feedback are stored here; hard safety preferences stay in
/// [TravelPreferences].
class TripLibraryStore extends ChangeNotifier {
  TripLibraryStore({TripLibraryPreferencesFactory? preferencesFactory})
    : _preferencesFactory = preferencesFactory ?? SharedPreferences.getInstance;

  static final TripLibraryStore instance = TripLibraryStore();

  final TripLibraryPreferencesFactory _preferencesFactory;
  final Map<String, TripOverrideDocument> _overrides =
      <String, TripOverrideDocument>{};
  final Map<String, TripVisitFeedback> _visits = <String, TripVisitFeedback>{};

  /// Place id per visit key, session memory only — device storage deliberately
  /// keeps no place ids, so a retry after a cold start pushes without one
  /// (the check-in contract allows a null place_id).
  final Map<String, String> _visitPlaceIds = <String, String>{};

  Future<void>? _loadFuture;
  Future<void> _savedWriteQueue = Future<void>.value();
  bool _loaded = false;
  TripLibraryRemote? _remote;
  TripLibrarySyncStatus _syncStatus = TripLibrarySyncStatus.localOnly;
  List<PastTripSummary> _pastTrips = const <PastTripSummary>[];
  Set<String> _lastSavedIds = const <String>{};
  int _syncEpoch = 0;
  bool _suppressSavedListener = false;

  TripLibrarySyncStatus get syncStatus => _syncStatus;
  bool get isLoaded => _loaded;
  bool get accountConnected => _remote != null;
  List<PastTripSummary> get pastTrips =>
      List<PastTripSummary>.unmodifiable(_pastTrips);

  /// Zone-safe load gate (CP1). When already loaded, hand out a *fresh*
  /// completed future created in the caller's zone — awaiting a future that
  /// completed inside an earlier Flutter test zone can hang that later zone's
  /// fake async (the cached `_loadFuture` belongs to a dead zone). Concurrent
  /// first-load deduplication (`_loadFuture ??=`) is unchanged.
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loadFuture ??= _load();
  }

  TripOverrideDocument? overrideDocumentFor(String planDate) =>
      _overrides[planDate];

  TripPreferenceOverride overrideFor(String planDate) =>
      _overrides[planDate]?.value ?? const TripPreferenceOverride();

  TravelPreferences effectivePreferences(
    String planDate,
    TravelPreferences defaults,
  ) => overrideFor(planDate).applyTo(defaults);

  TripVisitFeedback visitFor(String planDate, String slotPeriod) =>
      _visits[tripVisitKey(planDate, slotPeriod)] ?? const TripVisitFeedback();

  Future<void> _load() async {
    try {
      final preferences = await _preferencesFactory();
      final raw = preferences.getString(kTripLibraryStorageKey);
      if (raw != null) _decodeLocal(raw);
    } on Object {
      _overrides.clear();
      _visits.clear();
      _visitPlaceIds.clear();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> connectAccount(TripLibraryRemote remote) async {
    await ensureLoaded();
    final epoch = ++_syncEpoch;
    _detachListeners();
    _remote = remote;
    _syncStatus = TripLibrarySyncStatus.syncing;
    notifyListeners();
    try {
      final remoteSaved = await remote.listSavedPlaceIds();
      if (epoch != _syncEpoch) return;
      final localSaved = SavedPlaceStore.current;
      for (final placeId in localSaved.difference(remoteSaved)) {
        await remote.setSavedPlace(placeId, saved: true);
      }
      if (epoch != _syncEpoch) return;
      final merged = <String>{...remoteSaved, ...localSaved};
      _suppressSavedListener = true;
      SavedPlaceStore.restore(merged);
      _suppressSavedListener = false;
      _lastSavedIds = Set<String>.of(merged);

      await _reconcileDate(tripLibraryDateKey(), epoch: epoch);
      if (epoch != _syncEpoch) return;
      final plan = PlanContextStore.current;
      if (plan != null) {
        await remote.savePlan(tripLibraryDateKey(), encodeLalaDailyPlan(plan));
      }
      if (epoch != _syncEpoch) return;
      _pastTrips = await remote.listPastTrips();
      if (epoch != _syncEpoch) return;
      _attachListeners();
      if (_syncStatus != TripLibrarySyncStatus.conflict) {
        _syncStatus = TripLibrarySyncStatus.synced;
      }
      await _persistLocal();
    } on Object {
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.error;
      _attachListeners();
    }
    if (epoch == _syncEpoch) notifyListeners();
  }

  void disconnectAccount() {
    _syncEpoch += 1;
    _detachListeners();
    _remote = null;
    _pastTrips = const <PastTripSummary>[];
    _syncStatus = TripLibrarySyncStatus.localOnly;
    notifyListeners();
  }

  /// Clears device-only trip overrides and visit feedback.
  ///
  /// Account-backed data must be managed through the account controls instead;
  /// refusing while connected prevents a local privacy action from looking like
  /// a server deletion.
  Future<void> clearDeviceData() async {
    await ensureLoaded();
    if (_remote != null) {
      throw StateError('Disconnect the account before clearing device data.');
    }
    _overrides.clear();
    _visits.clear();
    _visitPlaceIds.clear();
    _pastTrips = const <PastTripSummary>[];
    _syncStatus = TripLibrarySyncStatus.localOnly;
    try {
      final preferences = await _preferencesFactory();
      await preferences.remove(kTripLibraryStorageKey);
    } on Object {
      // The in-memory reset remains effective for this session.
    }
    notifyListeners();
  }

  Future<void> retryAccountSync() async {
    final remote = _remote;
    if (remote == null || _syncStatus == TripLibrarySyncStatus.syncing) return;
    await connectAccount(remote);
  }

  Future<void> saveOverride(
    String planDate,
    TripPreferenceOverride value,
  ) async {
    await ensureLoaded();
    final current = _overrides[planDate];
    _overrides[planDate] = TripOverrideDocument(
      value: value,
      revision: current?.revision ?? 0,
      updatedAt: current?.updatedAt,
      dirty: true,
    );
    await _persistLocal();
    notifyListeners();
    final remote = _remote;
    if (remote == null) return;
    // Late-response guard: a disconnect/reconnect during the PUT invalidates
    // this result; the dirty device copy stays for the next reconciliation.
    final epoch = _syncEpoch;
    _syncStatus = TripLibrarySyncStatus.syncing;
    notifyListeners();
    try {
      final saved = await remote.putOverride(
        planDate,
        expectedRevision: current?.revision ?? 0,
        value: value,
      );
      if (epoch != _syncEpoch) return;
      _overrides[planDate] = saved;
      _syncStatus = TripLibrarySyncStatus.synced;
      await _persistLocal();
    } on LalaApiException catch (error) {
      if (epoch != _syncEpoch) return;
      _syncStatus = error.code == 'TRIP_PREFERENCES_REVISION_CONFLICT'
          ? TripLibrarySyncStatus.conflict
          : TripLibrarySyncStatus.error;
    } on Object {
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.error;
    }
    notifyListeners();
  }

  Future<void> reloadOverrideFromAccount(String planDate) async {
    final remote = _remote;
    if (remote == null) return;
    final epoch = _syncEpoch;
    _syncStatus = TripLibrarySyncStatus.syncing;
    notifyListeners();
    try {
      final server = await remote.getOverride(planDate);
      if (epoch != _syncEpoch) return;
      if (server == null) {
        _overrides.remove(planDate);
      } else {
        _overrides[planDate] = server;
      }
      _syncStatus = TripLibrarySyncStatus.synced;
      await _persistLocal();
    } on Object {
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.error;
    }
    notifyListeners();
  }

  Future<void> resetOverride(String planDate) async {
    await ensureLoaded();
    _overrides.remove(planDate);
    await _persistLocal();
    notifyListeners();
    final remote = _remote;
    if (remote == null) return;
    final epoch = _syncEpoch;
    _syncStatus = TripLibrarySyncStatus.syncing;
    notifyListeners();
    try {
      await remote.deleteOverride(planDate);
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.synced;
    } on Object {
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.error;
    }
    notifyListeners();
  }

  Future<void> saveVisit(
    String planDate,
    String slotPeriod, {
    required String? placeId,
    required TripVisitFeedback feedback,
  }) async {
    await ensureLoaded();
    final key = tripVisitKey(planDate, slotPeriod);
    if (feedback.status == TripVisitStatus.planned) {
      _visits.remove(key);
      _visitPlaceIds.remove(key);
    } else {
      _visits[key] = feedback;
      if (placeId == null) {
        _visitPlaceIds.remove(key);
      } else {
        _visitPlaceIds[key] = placeId;
      }
    }
    SlotVisitStore.setStatus(
      planDate,
      slotPeriod,
      tripVisitStatusWire(feedback.status),
    );
    await _persistLocal();
    notifyListeners();
    final remote = _remote;
    if (remote == null) return;
    final epoch = _syncEpoch;
    _syncStatus = TripLibrarySyncStatus.syncing;
    notifyListeners();
    try {
      final saved = await remote.putVisit(
        planDate,
        slotPeriod,
        placeId: placeId ?? _visitPlaceIds[key],
        feedback: feedback,
      );
      if (epoch != _syncEpoch) return;
      if (saved.status == TripVisitStatus.planned) {
        _visits.remove(key);
      } else {
        _visits[key] = saved;
      }
      _syncStatus = TripLibrarySyncStatus.synced;
      await _persistLocal();
    } on Object {
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.error;
    }
    notifyListeners();
  }

  Future<void> refreshPastTrips({String? before, bool append = false}) async {
    final remote = _remote;
    if (remote == null) return;
    final epoch = _syncEpoch;
    _syncStatus = TripLibrarySyncStatus.syncing;
    notifyListeners();
    try {
      final loaded = await remote.listPastTrips(before: before);
      if (epoch != _syncEpoch) return;
      _pastTrips = append
          ? <PastTripSummary>[..._pastTrips, ...loaded]
          : loaded;
      _syncStatus = TripLibrarySyncStatus.synced;
    } on Object {
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.error;
    }
    notifyListeners();
  }

  Future<LalaDailyPlan?> loadPastPlan(String planDate) async {
    final remote = _remote;
    if (remote == null) return null;
    final plan = await remote.loadPlan(planDate);
    if (plan != null) PlanContextStore.set(plan);
    return plan;
  }

  Future<bool> reusePastPlan(String sourceDate, String targetDate) async {
    final remote = _remote;
    if (remote == null) return false;
    try {
      final plan = await remote.loadPlan(sourceDate);
      if (plan == null) return false;
      await remote.savePlan(targetDate, encodeLalaDailyPlan(plan));
      PlanContextStore.set(plan);
      await refreshPastTrips();
      return true;
    } on Object {
      _syncStatus = TripLibrarySyncStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> deletePastPlan(String planDate) async {
    final remote = _remote;
    if (remote == null) return;
    final epoch = _syncEpoch;
    _syncStatus = TripLibrarySyncStatus.syncing;
    notifyListeners();
    try {
      await remote.deletePlan(planDate);
      if (epoch != _syncEpoch) return;
      _pastTrips = _pastTrips
          .where((trip) => trip.planDate != planDate)
          .toList(growable: false);
      _overrides.remove(planDate);
      _visits.removeWhere((key, _) => key.startsWith('$planDate:'));
      _visitPlaceIds.removeWhere((key, _) => key.startsWith('$planDate:'));
      _syncStatus = TripLibrarySyncStatus.synced;
      await _persistLocal();
    } on Object {
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.error;
    }
    notifyListeners();
  }

  Future<void> _reconcileDate(String planDate, {required int epoch}) async {
    final remote = _remote;
    if (remote == null) return;
    final serverOverride = await remote.getOverride(planDate);
    if (epoch != _syncEpoch) return;
    final localOverride = _overrides[planDate];
    if (localOverride == null && serverOverride != null) {
      _overrides[planDate] = serverOverride;
    } else if (localOverride != null && serverOverride == null) {
      final saved = await remote.putOverride(
        planDate,
        expectedRevision: 0,
        value: localOverride.value,
      );
      // Late-response guard: a disconnect/reconnect during the PUT invalidates
      // this result; assigning it would clobber the newer epoch's state.
      if (epoch != _syncEpoch) return;
      _overrides[planDate] = saved;
    } else if (localOverride != null && serverOverride != null) {
      if (localOverride.value == serverOverride.value && !localOverride.dirty) {
        _overrides[planDate] = serverOverride;
      } else if (localOverride.value != serverOverride.value) {
        _overrides[planDate] = TripOverrideDocument(
          value: localOverride.value,
          revision: serverOverride.revision,
          updatedAt: localOverride.updatedAt,
          dirty: true,
        );
        _syncStatus = TripLibrarySyncStatus.conflict;
      } else {
        final saved = await remote.putOverride(
          planDate,
          expectedRevision: serverOverride.revision,
          value: localOverride.value,
        );
        // Late-response guard, same as the server-null branch above.
        if (epoch != _syncEpoch) return;
        _overrides[planDate] = saved;
      }
    }

    final serverVisits = await remote.listVisits(planDate);
    if (epoch != _syncEpoch) return;
    for (final entry in serverVisits.entries) {
      final key = tripVisitKey(planDate, entry.key);
      _visits.putIfAbsent(key, () => entry.value);
      SlotVisitStore.setStatus(
        planDate,
        entry.key,
        tripVisitStatusWire(_visits[key]!.status),
      );
    }
    // Retry leg: device-first visit writes that never reached the account (a
    // failed putVisit) are re-pushed here so "sync can be retried later" is a
    // real action. The device copy stays authoritative (putIfAbsent above), so
    // keys missing on the server or diverging from it converge to the device.
    final prefix = '$planDate:';
    for (final entry in _visits.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      if (serverVisits[entry.key.substring(prefix.length)] == entry.value) {
        continue;
      }
      final saved = await remote.putVisit(
        planDate,
        entry.key.substring(prefix.length),
        placeId: _visitPlaceIds[entry.key],
        feedback: entry.value,
      );
      if (epoch != _syncEpoch) return;
      if (saved.status != TripVisitStatus.planned) {
        _visits[entry.key] = saved;
      }
    }
  }

  void _attachListeners() {
    SavedPlaceStore.listenable.addListener(_handleSavedPlacesChanged);
    PlanContextStore.listenable.addListener(_handlePlanChanged);
  }

  void _detachListeners() {
    SavedPlaceStore.listenable.removeListener(_handleSavedPlacesChanged);
    PlanContextStore.listenable.removeListener(_handlePlanChanged);
  }

  void _handleSavedPlacesChanged() {
    if (_suppressSavedListener) return;
    final remote = _remote;
    if (remote == null) return;
    final next = SavedPlaceStore.current;
    final added = next.difference(_lastSavedIds);
    final removed = _lastSavedIds.difference(next);
    _lastSavedIds = Set<String>.of(next);
    if (added.isEmpty && removed.isEmpty) return;
    _savedWriteQueue = _savedWriteQueue.then((_) async {
      // Late-response guard: a disconnect while the queued writes are in
      // flight must not report an account-synced state afterwards.
      final epoch = _syncEpoch;
      _syncStatus = TripLibrarySyncStatus.syncing;
      notifyListeners();
      try {
        for (final placeId in added) {
          await remote.setSavedPlace(placeId, saved: true);
        }
        for (final placeId in removed) {
          await remote.setSavedPlace(placeId, saved: false);
        }
        if (epoch != _syncEpoch) return;
        _syncStatus = TripLibrarySyncStatus.synced;
      } on Object {
        if (epoch != _syncEpoch) return;
        _syncStatus = TripLibrarySyncStatus.error;
      }
      notifyListeners();
    });
  }

  void _handlePlanChanged() {
    final remote = _remote;
    final plan = PlanContextStore.current;
    if (remote == null || plan == null) return;
    unawaited(_savePlanToAccount(remote, plan));
  }

  Future<void> _savePlanToAccount(
    TripLibraryRemote remote,
    LalaDailyPlan plan,
  ) async {
    final epoch = _syncEpoch;
    try {
      await remote.savePlan(tripLibraryDateKey(), encodeLalaDailyPlan(plan));
      // Late-response guard: ignore the completion when the account context it
      // wrote under is no longer active.
      if (epoch != _syncEpoch) return;
      await refreshPastTrips();
    } on Object {
      if (epoch != _syncEpoch) return;
      _syncStatus = TripLibrarySyncStatus.error;
      notifyListeners();
    }
  }

  void _decodeLocal(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['v'] != 1) return;
    final overrideMap = decoded['overrides'];
    if (overrideMap is Map) {
      for (final entry in overrideMap.entries) {
        if (entry.key is String) {
          _overrides[entry.key as String] = TripOverrideDocument.fromLocalJson(
            entry.value,
          );
        }
      }
    }
    final visitMap = decoded['visits'];
    if (visitMap is Map) {
      for (final entry in visitMap.entries) {
        if (entry.key is String) {
          final feedback = TripVisitFeedback.fromJson(entry.value);
          if (feedback.status != TripVisitStatus.planned) {
            final key = entry.key as String;
            _visits[key] = feedback;
            final separator = key.indexOf(':');
            if (separator > 0 && separator < key.length - 1) {
              SlotVisitStore.setStatus(
                key.substring(0, separator),
                key.substring(separator + 1),
                tripVisitStatusWire(feedback.status),
              );
            }
          }
        }
      }
    }
  }

  Future<void> _persistLocal() async {
    final preferences = await _preferencesFactory();
    final value = jsonEncode(<String, dynamic>{
      'v': 1,
      'overrides': <String, dynamic>{
        for (final entry in _overrides.entries)
          entry.key: entry.value.toLocalJson(),
      },
      'visits': <String, dynamic>{
        for (final entry in _visits.entries) entry.key: entry.value.toJson(),
      },
    });
    await preferences.setString(kTripLibraryStorageKey, value);
  }
}
