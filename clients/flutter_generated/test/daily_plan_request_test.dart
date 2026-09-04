import 'package:test/test.dart';
import 'package:built_value/serializer.dart';
import 'package:lala_next_flutter_client_generated/lala_next_flutter_client_generated.dart';

// tests for DailyPlanRequest
void main() {
  group(DailyPlanRequest, () {
    DailyPlanRequest buildRequest() => (DailyPlanRequestBuilder()
          ..lat = 37.2
          ..lng = 127.0)
        .build();

    // String language (default value: 'ko')
    test('to test the property `language`', () async {
      expect(buildRequest().language, 'ko');
    });

    // num lat
    test('to test the property `lat`', () async {
      expect(buildRequest().lat, 37.2);
    });

    // num lng
    test('to test the property `lng`', () async {
      expect(buildRequest().lng, 127.0);
    });

    // int radiusM (default value: 3000)
    test('to test the property `radiusM`', () async {
      expect(buildRequest().radiusM, 3000);
    });

    // String? selectedPlaceId — D-1: omitted from the wire when null.
    test('omits selected_place_id and preference_context when null', () {
      final request = DailyPlanRequestBuilder()
        ..lat = 37.2
        ..lng = 127.0
        ..radiusM = 1200
        ..language = 'ko';

      final wire = standardSerializers.serialize(
        request.build(),
        specifiedType: const FullType(DailyPlanRequest),
      ) as Map<String, Object?>;

      expect(wire, {
        r'language': 'ko',
        r'lat': 37.2,
        r'lng': 127.0,
        r'radius_m': 1200,
      });
      expect(wire, isNot(contains(r'selected_place_id')));
      expect(wire, isNot(contains(r'preference_context')));
    });

    // PlanPreferenceContext? preferenceContext — CP1: sent when supplied.
    test('embeds preference_context with snake_case keys when supplied', () {
      final context = PlanPreferenceContextBuilder()
        ..indoorOutdoor = PlanPreferenceContextIndoorOutdoorEnum.indoor
        ..maxOneWayMinutes = PlanPreferenceContextMaxOneWayMinutesEnum.number15;
      final request = DailyPlanRequestBuilder()
        ..lat = 37.2
        ..lng = 127.0
        ..radiusM = 5000
        ..language = 'ko'
        ..selectedPlaceId = 'p2'
        ..preferenceContext = context;

      final wire = standardSerializers.serialize(
        request.build(),
        specifiedType: const FullType(DailyPlanRequest),
      ) as Map<String, Object?>;

      expect(wire[r'selected_place_id'], 'p2');
      final contextWire = wire[r'preference_context'] as Map<String, Object?>;
      expect(contextWire[r'indoor_outdoor'], 'indoor');
      expect(contextWire[r'max_one_way_minutes'], 15);
    });
  });
}
