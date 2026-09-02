import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../domain/travel_preferences.dart';

class TravelPreferencesRemoteDocument {
  const TravelPreferencesRemoteDocument({
    required this.preferences,
    required this.revision,
    required this.updatedAt,
  });

  final TravelPreferences preferences;
  final int revision;
  final String updatedAt;
}

abstract interface class TravelPreferencesRemote {
  Future<TravelPreferencesRemoteDocument?> get();

  Future<TravelPreferencesRemoteDocument> put({
    required TravelPreferences preferences,
    required int expectedRevision,
  });
}

class LalaTravelPreferencesRemote implements TravelPreferencesRemote {
  const LalaTravelPreferencesRemote(this._client);

  final LalaApiClient _client;

  @override
  Future<TravelPreferencesRemoteDocument?> get() async {
    final response = await _client.getTravelPreferences();
    if (!response.ok) {
      throw LalaApiException.fromEnvelope(response);
    }
    final document = response.data;
    if (document == null) {
      return null;
    }
    return _fromClientDocument(document);
  }

  @override
  Future<TravelPreferencesRemoteDocument> put({
    required TravelPreferences preferences,
    required int expectedRevision,
  }) async {
    final response = await _client.putTravelPreferences(
      expectedRevision: expectedRevision,
      preferences: Map<String, dynamic>.from(preferences.toJson()),
    );
    final document = response.data;
    if (!response.ok || document == null) {
      throw LalaApiException.fromEnvelope(response);
    }
    return _fromClientDocument(document);
  }

  TravelPreferencesRemoteDocument _fromClientDocument(
    LalaTravelPreferencesDocument document,
  ) {
    return TravelPreferencesRemoteDocument(
      preferences: TravelPreferences.fromJson(document.preferences),
      revision: document.revision,
      updatedAt: document.updatedAt,
    );
  }
}
