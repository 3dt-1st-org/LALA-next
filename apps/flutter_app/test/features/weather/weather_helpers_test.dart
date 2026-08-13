// P1: 온도 라벨 포맷터 단위 검증.
// - 빈/공백/단독 '-' → null (caller 가 '-' 를 사용자 정보로 렌더하지 않게).
// - 숫자/C/°C 포맷은 기존 동작 유지.
// - 하위 호환 temperatureLabel 빈 값 → '-'.
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/weather/weather_helpers.dart';
import 'package:lala_next_app/shared/labels/source_label.dart';

void main() {
  group('temperatureLabelOrNull', () {
    test('빈/공백/단독 대시는 null', () {
      expect(temperatureLabelOrNull(''), isNull);
      expect(temperatureLabelOrNull('   '), isNull);
      expect(temperatureLabelOrNull('-'), isNull);
      expect(temperatureLabelOrNull('  -  '), isNull);
    });

    test('숫자는 °C 포맷', () {
      expect(temperatureLabelOrNull('14'), '14°C');
      expect(temperatureLabelOrNull('14.5'), '14.5°C');
      expect(temperatureLabelOrNull('-5'), '-5°C');
    });

    test('숫자+C 접미사는 °C 로 정규화', () {
      expect(temperatureLabelOrNull('22C'), '22°C');
      expect(temperatureLabelOrNull('-3C'), '-3°C');
    });

    test('이미 °C 인 값과 기타 문자열은 그대로', () {
      expect(temperatureLabelOrNull('14°C'), '14°C');
      expect(temperatureLabelOrNull('맑음'), '맑음');
    });
  });

  group('temperatureLabel (하위 호환 폴백)', () {
    test('빈 값은 대시 폴백, 그 외는 temperatureLabelOrNull 과 동일', () {
      expect(temperatureLabel(''), '-');
      expect(temperatureLabel('14'), '14°C');
      expect(temperatureLabel('22C'), '22°C');
    });
  });

  // Wave-1: weather/air stays at the official server-side boundary. Placeholder
  // sources (skeleton/fallback/unavailable) must be suppressed to the truthful
  // unavailable card; only real, timestamped snapshots reach the UI.
  group('isPlaceholderWeatherSource (honest weather data states)', () {
    test('placeholder/empty/fallback sources are suppressed', () {
      expect(isPlaceholderWeatherSource(null), isTrue);
      expect(isPlaceholderWeatherSource(''), isTrue);
      expect(isPlaceholderWeatherSource('skeleton'), isTrue);
      expect(isPlaceholderWeatherSource('fallback'), isTrue);
      expect(isPlaceholderWeatherSource('unavailable'), isTrue);
      expect(isPlaceholderWeatherSource('db_fallback'), isTrue);
    });

    test('real server-side sources pass through', () {
      expect(isPlaceholderWeatherSource('db'), isFalse);
      expect(isPlaceholderWeatherSource('kma_ultra_srt_ncst'), isFalse);
      expect(isPlaceholderWeatherSource('airkorea_sido_realtime'), isFalse);
    });
  });

  // V1-RC3: 독·상세가 공유하는 날씨 요약 SSOT. 조작된 수치/등급/소스가 없어야 하고,
  // placeholder/fallback 은 정직하게 생략된다. summary 와 source 는 항상 한 쌍.
  group('publicWeatherSummary (V1-RC3 SSOT)', () {
    test('실측 날씨: outdoor · temp · dust 요약 + weather source 한 쌍', () {
      final result = publicWeatherSummary(
        _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        'ko',
      );
      expect(result.summary, '보통 · 23°C · PM10 30 보통 · PM2.5 25 좋음');
      expect(result.source, '기상청 실황');
    });

    test('null 날씨: 정직한 생략 — summary·source 모두 null', () {
      final result = publicWeatherSummary(null, 'ko');
      expect(result.summary, isNull);
      expect(result.source, isNull);
    });

    test('placeholder/fallback 소스: gate 통과 못함 → null 쌍 (조작 없음)', () {
      final result = publicWeatherSummary(
        _weather(temp: '23', source: 'fallback'),
        'ko',
      );
      expect(result.summary, isNull);
      expect(result.source, isNull);
    });

    test('dust 수치 누락(등급 있음): PM 숫자는 빠지고 등급 폴백 — 조작 수치 없음', () {
      final result = publicWeatherSummary(
        _weather(
          temp: '20',
          source: 'airkorea_sido_realtime',
          outdoorStatus: 'good',
          dust: _dust(pm10: '', pm25: '', grade: 'normal', gradeKo: '보통'),
        ),
        'ko',
      );
      expect(result.summary, '좋음 · 20°C · 보통');
      expect(result.source, 'AirKorea 대기질');
    });

    test('dust 전부 누락(등급도 없음): dust 파트 완전 생략 → outdoor · temp', () {
      final result = publicWeatherSummary(
        _weather(
          temp: '20',
          source: 'kma_ultra_srt_ncst',
          outdoorStatus: 'good',
          dust: _dust(pm10: '', pm25: '', grade: '', gradeKo: ''),
        ),
        'ko',
      );
      expect(result.summary, '좋음 · 20°C');
      expect(result.source, '기상청 실황');
    });

    test('온도 누락(dust 있음): 온도 파트 생략 — 조작된 온도 없음', () {
      final result = publicWeatherSummary(
        _weather(temp: '', source: 'kma_ultra_srt_ncst'),
        'ko',
      );
      expect(result.summary, '보통 · PM10 30 보통 · PM2.5 25 좋음');
      expect(result.source, '기상청 실황');
    });

    test('source pairing: summary 있으면 source 도 있고, 없으면 같이 생략', () {
      // 정상: summary 와 source 가 항상 쌍으로 존재.
      final ok = publicWeatherSummary(
        _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        'ko',
      );
      expect(ok.summary, isNotNull);
      expect(ok.source, isNotNull);

      // gate 에서 걸리면 둘 다 null — 귀속(weather source)만 남지 않는다.
      final omitted = publicWeatherSummary(
        _weather(temp: '23', source: 'skeleton'),
        'ko',
      );
      expect(omitted.summary, isNull);
      expect(omitted.source, isNull);
    });

    test('language 인자로 ko/en 전환 — 한 결과 안에 언어 혼합 없음', () {
      final result = publicWeatherSummary(
        _weather(temp: '23', source: 'kma_ultra_srt_ncst'),
        'en',
      );
      // 모든 파트가 en 으로 전환됨 (KO 단어/등급이 섞이지 않는다).
      expect(result.summary, 'Normal · 23°C · PM10 30 Normal · PM2.5 25 Good');
      expect(result.source, 'KMA live weather');
    });
  });
}

LalaWeather _weather({
  required String temp,
  required String source,
  String outdoorStatus = 'normal',
  LalaDust? dust,
}) {
  return LalaWeather(
    lat: 37.2636,
    lng: 127.0286,
    temp: temp,
    icon: 'partly-cloudy',
    dust: dust ?? _dust(),
    forecast: const <LalaForecastItem>[],
    outdoorStatus: outdoorStatus,
    force: false,
    source: source,
    location: 'Suwon',
    recordTime: '2026-07-24T09:00:00+09:00',
    locationMatch: true,
  );
}

LalaDust _dust({
  String pm10 = '30',
  String pm25 = '25',
  String grade = 'normal',
  String gradeKo = '보통',
  String pm10Grade = 'normal',
  String pm10GradeKo = '보통',
  String pm25Grade = 'good',
  String pm25GradeKo = '좋음',
}) {
  return LalaDust(
    pm10: pm10,
    pm25: pm25,
    grade: grade,
    gradeKo: gradeKo,
    pm10Grade: pm10Grade,
    pm10GradeKo: pm10GradeKo,
    pm25Grade: pm25Grade,
    pm25GradeKo: pm25GradeKo,
  );
}
