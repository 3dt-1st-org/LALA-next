// P1: 온도 라벨 포맷터 단위 검증.
// - 빈/공백/단독 '-' → null (caller 가 '-' 를 사용자 정보로 렌더하지 않게).
// - 숫자/C/°C 포맷은 기존 동작 유지.
// - 하위 호환 temperatureLabel 빈 값 → '-'.
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/weather/weather_helpers.dart';

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
}
