import 'package:test/test.dart';
import 'package:lala_next_flutter_client_generated/lala_next_flutter_client_generated.dart';


/// tests for V1Api
void main() {
  final instance = LalaNextFlutterClientGenerated().getV1Api();

  group(V1Api, () {
    // Daily Plan
    //
    //Future<DailyPlanSuccessEnvelope> dailyPlanApiV1PlansDailyPost(DailyPlanRequest dailyPlanRequest, { String xAPIKey, String authorization }) async
    test('test dailyPlanApiV1PlansDailyPost', () async {
      // TODO
    });

    // Delete Me
    //
    // Deletes the account for an OAuth identity issued by the current configured LOGTO_ENDPOINT. Legacy OAUTH issuers are not accepted.
    //
    //Future deleteMeApiV1MeDelete(AccountDeletionRequest accountDeletionRequest) async
    test('test deleteMeApiV1MeDelete', () async {
      // TODO
    });

    // Docent Audio
    //
    //Future<Uint8List> docentAudioApiV1DocentsAudioPost(DocentAudioRequest docentAudioRequest, { String xAPIKey, String authorization }) async
    test('test docentAudioApiV1DocentsAudioPost', () async {
      // TODO
    });

    // Docent Script
    //
    //Future<DocentScriptSuccessEnvelope> docentScriptApiV1DocentsScriptPost(DocentScriptRequest docentScriptRequest, { String xAPIKey, String authorization }) async
    test('test docentScriptApiV1DocentsScriptPost', () async {
      // TODO
    });

    // Intervention
    //
    //Future<InterventionSuccessEnvelope> interventionApiV1PlansInterventionGet(num lat, num lng, { int radiusM, String xAPIKey, String authorization }) async
    test('test interventionApiV1PlansInterventionGet', () async {
      // TODO
    });

    // Me
    //
    // Returns the local account for an OAuth identity issued by the current configured LOGTO_ENDPOINT. Legacy OAUTH issuers are not accepted.
    //
    //Future<MeSuccessEnvelope> meApiV1MeGet() async
    test('test meApiV1MeGet', () async {
      // TODO
    });

    // Places
    //
    //Future<PlacesSuccessEnvelope> placesApiV1PlacesGet(num lat, num lng, { int radiusM, String category, String lang, String language, bool includeScores, int limit, String xAPIKey, String authorization }) async
    test('test placesApiV1PlacesGet', () async {
      // TODO
    });

    // Weather
    //
    //Future<WeatherSuccessEnvelope> weatherApiV1WeatherGet(num lat, num lng, { bool force, String xAPIKey, String authorization }) async
    test('test weatherApiV1WeatherGet', () async {
      // TODO
    });

  });
}
