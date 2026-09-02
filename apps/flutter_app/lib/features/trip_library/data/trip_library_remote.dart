import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/trip_library/domain/trip_library_models.dart';

abstract interface class TripLibraryRemote {
  Future<Set<String>> listSavedPlaceIds();

  Future<void> setSavedPlace(String placeId, {required bool saved});

  Future<List<PastTripSummary>> listPastTrips({String? before, int limit = 20});

  Future<LalaDailyPlan?> loadPlan(String planDate);

  Future<void> savePlan(String planDate, Map<String, dynamic> plan);

  Future<void> deletePlan(String planDate);

  Future<TripOverrideDocument?> getOverride(String planDate);

  Future<TripOverrideDocument> putOverride(
    String planDate, {
    required int expectedRevision,
    required TripPreferenceOverride value,
  });

  Future<void> deleteOverride(String planDate);

  Future<Map<String, TripVisitFeedback>> listVisits(String planDate);

  Future<TripVisitFeedback> putVisit(
    String planDate,
    String slotPeriod, {
    required String? placeId,
    required TripVisitFeedback feedback,
  });
}

class LalaTripLibraryRemote implements TripLibraryRemote {
  const LalaTripLibraryRemote(this._client);

  final LalaApiClient _client;

  @override
  Future<Set<String>> listSavedPlaceIds() async {
    final response = await _client.listSavedPlaces();
    final data = response.data;
    if (!response.ok || data == null) {
      throw LalaApiException.fromEnvelope(response);
    }
    return data.items.map((item) => item.placeId).toSet();
  }

  @override
  Future<void> setSavedPlace(String placeId, {required bool saved}) async {
    final response = saved
        ? await _client.savePlace(placeId: placeId, source: 'db')
        : await _client.unsavePlace(placeId: placeId);
    if (!response.ok || response.data == null) {
      throw LalaApiException.fromEnvelope(response);
    }
  }

  @override
  Future<List<PastTripSummary>> listPastTrips({
    String? before,
    int limit = 20,
  }) async {
    final response = await _client.listPersistedPlans(
      before: before,
      limit: limit,
    );
    final data = response.data;
    if (!response.ok || data == null) {
      throw LalaApiException.fromEnvelope(response);
    }
    return data.items
        .map(
          (item) => PastTripSummary(
            planDate: item.planDate,
            region: item.region,
            slotCount: item.slotCount,
            visitedCount: item.visitedCount,
            updatedAt: item.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<LalaDailyPlan?> loadPlan(String planDate) async {
    final response = await _client.loadPersistedPlan(planDate: planDate);
    if (!response.ok) throw LalaApiException.fromEnvelope(response);
    return response.data?.plan;
  }

  @override
  Future<void> savePlan(String planDate, Map<String, dynamic> plan) async {
    final response = await _client.savePersistedPlan(
      planDate: planDate,
      plan: plan,
    );
    if (!response.ok || response.data == null) {
      throw LalaApiException.fromEnvelope(response);
    }
  }

  @override
  Future<void> deletePlan(String planDate) async {
    final response = await _client.deletePersistedPlan(planDate: planDate);
    if (!response.ok || response.data == null) {
      throw LalaApiException.fromEnvelope(response);
    }
  }

  @override
  Future<TripOverrideDocument?> getOverride(String planDate) async {
    final response = await _client.getTripPreferenceOverride(
      planDate: planDate,
    );
    if (!response.ok) throw LalaApiException.fromEnvelope(response);
    final document = response.data;
    if (document == null) return null;
    return TripOverrideDocument(
      value: TripPreferenceOverride.fromJson(document.override),
      revision: document.revision,
      updatedAt: document.updatedAt,
    );
  }

  @override
  Future<TripOverrideDocument> putOverride(
    String planDate, {
    required int expectedRevision,
    required TripPreferenceOverride value,
  }) async {
    final response = await _client.putTripPreferenceOverride(
      planDate: planDate,
      expectedRevision: expectedRevision,
      override: value.toJson(),
    );
    final document = response.data;
    if (!response.ok || document == null) {
      throw LalaApiException.fromEnvelope(response);
    }
    return TripOverrideDocument(
      value: TripPreferenceOverride.fromJson(document.override),
      revision: document.revision,
      updatedAt: document.updatedAt,
    );
  }

  @override
  Future<void> deleteOverride(String planDate) async {
    final response = await _client.deleteTripPreferenceOverride(
      planDate: planDate,
    );
    if (!response.ok || response.data == null) {
      throw LalaApiException.fromEnvelope(response);
    }
  }

  @override
  Future<Map<String, TripVisitFeedback>> listVisits(String planDate) async {
    final response = await _client.listSlotVisits(planDate: planDate);
    final data = response.data;
    if (!response.ok || data == null) {
      throw LalaApiException.fromEnvelope(response);
    }
    return <String, TripVisitFeedback>{
      for (final item in data.items)
        item.slotPeriod: TripVisitFeedback.fromJson(<String, dynamic>{
          'status': item.status,
          'reason_code': item.reasonCode,
          'use_for_recommendations': item.useForRecommendations,
          'confirmed_at': item.confirmedAt,
        }),
    };
  }

  @override
  Future<TripVisitFeedback> putVisit(
    String planDate,
    String slotPeriod, {
    required String? placeId,
    required TripVisitFeedback feedback,
  }) async {
    final response = await _client.checkInSlot(
      planDate: planDate,
      slotPeriod: slotPeriod,
      status: tripVisitStatusWire(feedback.status),
      placeId: placeId,
      reasonCode: tripVisitReasonWire(feedback.reason),
      useForRecommendations: feedback.useForRecommendations,
    );
    final result = response.data;
    if (!response.ok || result == null) {
      throw LalaApiException.fromEnvelope(response);
    }
    return TripVisitFeedback.fromJson(<String, dynamic>{
      'status': result.status,
      'reason_code': result.reasonCode,
      'use_for_recommendations': result.useForRecommendations,
      'confirmed_at': result.confirmedAt,
    });
  }
}
