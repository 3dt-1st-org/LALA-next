import 'package:built_value/serializer.dart';
import 'package:test/test.dart';
import 'package:lala_next_flutter_client_generated/lala_next_flutter_client_generated.dart';

// tests for WeatherData
void main() {
  final instance = WeatherDataBuilder();
  // TODO add properties to the builder and call build()

  group(WeatherData, () {
    // Dust dust
    test('to test the property `dust`', () async {
      // TODO
    });

    // bool force
    test('to test the property `force`', () async {
      // TODO
    });

    // BuiltList<ForecastItem> forecast
    test('to test the property `forecast`', () async {
      // TODO
    });

    // String icon
    test('to test the property `icon`', () async {
      // TODO
    });

    // double lat
    test('to test the property `lat`', () async {
      // TODO
    });

    // double lng
    test('to test the property `lng`', () async {
      // TODO
    });

    // String location
    test('to test the property `location`', () async {
      // TODO
    });

    // bool locationMatch
    test('to test the property `locationMatch`', () async {
      // TODO
    });

    // String outdoorStatus
    test('to test the property `outdoorStatus`', () async {
      // TODO
    });

    // String recordTime
    test('to test the property `recordTime`', () async {
      // TODO
    });

    // String source_
    test('to test the property `source_`', () async {
      // TODO
    });

    // String temp
    test('to test the property `temp`', () async {
      // TODO
    });

    // WeatherDataWeatherOutdoorStatusEnum? weatherOutdoorStatus
    test('to test the property `weatherOutdoorStatus`', () async {
      // TODO
    });

    // WeatherDataAirQualityOutdoorStatusEnum? airQualityOutdoorStatus
    test('to test the property `airQualityOutdoorStatus`', () async {
      // TODO
    });

  });

  // P4 provenance round-trips: the two optional cause fields serialize and
  // deserialize behind the merged outdoor_status, and stay absent (null) for
  // legacy payloads that do not carry them.
  group('WeatherData P4 provenance serialization', () {
    // dart-dio PrimitiveSerializer wire format is a flattened key/value list.
    List<Object?> wireOf(WeatherData weather) => serializers.serialize(weather,
        specifiedType: const FullType(WeatherData)) as List<Object?>;

    Map<String, Object?> wireMapOf(List<Object?> flat) {
      final map = <String, Object?>{};
      for (var i = 0; i < flat.length; i += 2) {
        map[flat[i] as String] = flat[i + 1];
      }
      return map;
    }

    WeatherData buildWeather({
      WeatherDataWeatherOutdoorStatusEnum? weatherOutdoorStatus,
      WeatherDataAirQualityOutdoorStatusEnum? airQualityOutdoorStatus,
    }) {
      return WeatherData((b) => b
        ..lat = 37.2
        ..lng = 127.0
        ..temp = ''
        ..icon = 'unavailable'
        ..dust.replace(Dust((d) => d
          ..pm10 = ''
          ..pm25 = ''
          ..grade = 'unknown'
          ..gradeKo = '확인 중'
          ..pm10Grade = 'unknown'
          ..pm10GradeKo = '확인 중'
          ..pm25Grade = 'unknown'
          ..pm25GradeKo = '확인 중'))
        ..forecast.replace(const <ForecastItem>[])
        ..outdoorStatus = WeatherDataOutdoorStatusEnum.bad
        ..force = false
        ..source_ = WeatherDataSource_Enum.unavailable
        ..weatherOutdoorStatus = weatherOutdoorStatus
        ..airQualityOutdoorStatus = airQualityOutdoorStatus);
    }

    test('optional provenance fields round-trip through the serializers', () {
      final flat = wireOf(buildWeather(
        weatherOutdoorStatus: WeatherDataWeatherOutdoorStatusEnum.good,
        airQualityOutdoorStatus: WeatherDataAirQualityOutdoorStatusEnum.bad,
      ));
      final encoded = wireMapOf(flat);
      expect(encoded['outdoor_status'], 'bad');
      expect(encoded['weather_outdoor_status'], 'good');
      expect(encoded['air_quality_outdoor_status'], 'bad');

      final decoded =
          serializers.deserialize(flat, specifiedType: const FullType(WeatherData))
              as WeatherData;
      expect(decoded.outdoorStatus, WeatherDataOutdoorStatusEnum.bad);
      expect(decoded.weatherOutdoorStatus, WeatherDataWeatherOutdoorStatusEnum.good);
      expect(
          decoded.airQualityOutdoorStatus, WeatherDataAirQualityOutdoorStatusEnum.bad);
    });

    test('legacy payload without provenance keys keeps honest nulls', () {
      final flat = wireOf(buildWeather());
      final encoded = wireMapOf(flat);

      expect(encoded.containsKey('weather_outdoor_status'), isFalse);
      expect(encoded.containsKey('air_quality_outdoor_status'), isFalse);

      final legacyWire = <Object?>[
        for (var i = 0; i < flat.length; i += 2)
          if (flat[i] != 'weather_outdoor_status' && flat[i] != 'air_quality_outdoor_status') ...[flat[i], flat[i + 1]],
      ];
      final decoded = serializers.deserialize(legacyWire,
          specifiedType: const FullType(WeatherData)) as WeatherData;
      expect(decoded.outdoorStatus, WeatherDataOutdoorStatusEnum.bad);
      expect(decoded.weatherOutdoorStatus, isNull);
      expect(decoded.airQualityOutdoorStatus, isNull);
    });

    test('unknown provenance enum value is representable', () {
      final encoded = wireMapOf(wireOf(buildWeather(
        weatherOutdoorStatus: WeatherDataWeatherOutdoorStatusEnum.unknown,
        airQualityOutdoorStatus: WeatherDataAirQualityOutdoorStatusEnum.unknown,
      )));

      expect(encoded['weather_outdoor_status'], 'unknown');
      expect(encoded['air_quality_outdoor_status'], 'unknown');
    });
  });
}
