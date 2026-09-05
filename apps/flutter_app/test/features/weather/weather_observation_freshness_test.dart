// S-14 날씨 관측 시각 헬퍼 단위 검증(완전 결정적 — now 주입).
// - 지원 wire 표현 2종: ISO-8601+오프셋(`...+09:00`), KMA/AirKorea dataTime(`YYYY-MM-DD HH:MM`, KST 해석).
// - freshness 경계: 창 경과 exact → current(경계 포함), 1ms 초과 → stale.
// - null/망가짐/미래 skew → 정직한 unknown(나이 발명 금지).
// - 5개 로케일(ko/en/ja/zh-Hans/zh-Hant) 문구 — 혼합 없음.
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/weather/weather_observation_freshness.dart';

void main() {
  // 고정 기준 시각: 2026-09-05 02:30Z == KST 2026-09-05 11:30.
  final now = DateTime.utc(2026, 9, 5, 2, 30);

  WeatherObservationInfo info(
    String? recordTime, {
    String language = 'ko',
    DateTime? nowOverride,
  }) => weatherObservationInfo(
    recordTime: recordTime,
    now: nowOverride ?? now,
    language: language,
  );

  group('wire 표현 파싱 + timezone truth', () {
    test('ISO-8601 +09:00 오프셋: KST 벽시계 그대로, 같은 날이면 시각만', () {
      final result = info('2026-09-05T11:00:00+09:00');
      expect(result.freshness, WeatherObservationFreshness.current);
      expect(result.label, '관측 시각 11:00');
      expect(result.statusLabel, '최신 관측');
    });

    test('dataTime 비-타임존 형식(`YYYY-MM-DD HH:MM`)은 KST 로 해석', () {
      // 02:00 KST = 2026-09-04 17:00Z → 9시간 30분 전 → stale.
      final result = info('2026-09-05 02:00');
      expect(result.freshness, WeatherObservationFreshness.stale);
      expect(result.label, '관측 시각 02:00');
      expect(result.statusLabel, '이전 관측값');
    });

    test('+00:00 오프셋은 KST 로 변환해 표시(02:00Z → 11:00 KST)', () {
      final result = info('2026-09-05T02:00:00+00:00');
      expect(result.freshness, WeatherObservationFreshness.current);
      expect(result.label, '관측 시각 11:00');
    });

    test('Z 접미사(UTC)도 동일하게 KST 로 변환', () {
      final result = info('2026-09-05T02:00:00Z');
      expect(result.label, '관측 시각 11:00');
      expect(result.freshness, WeatherObservationFreshness.current);
    });

    test('오프셋이 있는 관측의 절대 시각이 정확하다(-05:00 역오프셋)', () {
      // 2026-09-04T09:00 -05:00 == 2026-09-04 14:00Z == KST 2026-09-04 23:00.
      final result = info('2026-09-04T09:00:00-05:00');
      expect(result.freshness, WeatherObservationFreshness.stale);
      expect(result.label, '관측 시각 2026-09-04 23:00');
    });
  });

  group('freshness 창 경계(kWeatherObservationCurrentWindow = 60분)', () {
    test('경과 시각이 창과 정확히 같으면 current(경계 포함)', () {
      final result = info('2026-09-05T10:30:00+09:00');
      expect(result.freshness, WeatherObservationFreshness.current);
      expect(result.statusLabel, '최신 관측');
    });

    test('창을 1ms 초과하면 stale', () {
      final result = info('2026-09-05T10:29:59.999+09:00');
      expect(result.freshness, WeatherObservationFreshness.stale);
      expect(result.statusLabel, '이전 관측값');
    });

    test('명백히 오래된 관측(어제)은 날짜를 포함한 라벨 + stale', () {
      final result = info('2026-09-04T23:00:00+09:00');
      expect(result.freshness, WeatherObservationFreshness.stale);
      expect(result.label, '관측 시각 2026-09-04 23:00');
      expect(result.semanticsLabel, '관측 시각 2026-09-04 23:00, 이전 관측값');
    });
  });

  group('정직한 unknown — 부재/망가짐/미래 skew', () {
    test('null recordTime → unknown', () {
      final result = info(null);
      expect(result.freshness, WeatherObservationFreshness.unknown);
      expect(result.label, '관측 시각 확인 중');
      expect(result.statusLabel, '');
      expect(result.semanticsLabel, '관측 시각 확인 중');
    });

    test('빈 문자열/공백 → unknown', () {
      for (final raw in ['', '   ']) {
        expect(info(raw).freshness, WeatherObservationFreshness.unknown);
      }
    });

    test('망가진 값 → 예외 없이 unknown (나이/시각 발명 금지)', () {
      for (final raw in [
        'not-a-time',
        '2026-13-01T09:00:00+09:00', // 불가능한 월
        '2026-09-05T25:00:00+09:00', // 불가능한 시
        '2026-09-05 11', // 파셜 dataTime
        '2026-09-05T11:00:00+99:00', // 불가능한 오프셋
        '2026-09-05T11:00:00 +09:00', // 오프셋 앞 공백
        '20260905T110000+0900', // 비구분자 형식
      ]) {
        final result = info(raw);
        expect(
          result.freshness,
          WeatherObservationFreshness.unknown,
          reason: raw,
        );
        expect(result.label, '관측 시각 확인 중', reason: raw);
      }
    });

    test('미래 skew(허용치 초과) → unknown, 절대 "방금 전"류 나이를 만들지 않는다', () {
      // 3분 미래 — 2분 허용치 초과.
      final result = info('2026-09-05T11:33:00+09:00');
      expect(result.freshness, WeatherObservationFreshness.unknown);
      expect(result.label, '관측 시각 확인 중');
    });

    test('미래 허용치 경계: 정확히 2분 미래는 current(클램프), 1ms 더 미래는 unknown', () {
      expect(
        info('2026-09-05T11:32:00+09:00').freshness,
        WeatherObservationFreshness.current,
      );
      expect(
        info('2026-09-05T11:32:00.001+09:00').freshness,
        WeatherObservationFreshness.unknown,
      );
    });
  });

  group('5개 로케일 문구(ko/en/ja/zh-Hans/zh-Hant)', () {
    test('current 관측 — 각 로케일 완전 문구', () {
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'ko').label,
        '관측 시각 11:00',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'ko').statusLabel,
        '최신 관측',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'en').label,
        'Observed 11:00',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'en').statusLabel,
        'Current',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'ja').label,
        '観測時刻 11:00',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'ja').statusLabel,
        '最新観測',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'zh-Hans').label,
        '观测时间 11:00',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'zh-Hans').statusLabel,
        '最新观测',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'zh-Hant').label,
        '觀測時間 11:00',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'zh-Hant').statusLabel,
        '最新觀測',
      );
    });

    test('stale 관측 — 각 로케일 상태 문구', () {
      expect(
        info('2026-09-04T23:00:00+09:00', language: 'en').statusLabel,
        'Earlier observation',
      );
      expect(
        info('2026-09-04T23:00:00+09:00', language: 'ja').statusLabel,
        '以前の観測',
      );
      expect(
        info('2026-09-04T23:00:00+09:00', language: 'zh-Hans').statusLabel,
        '较早观测',
      );
      expect(
        info('2026-09-04T23:00:00+09:00', language: 'zh-Hant').statusLabel,
        '較早觀測',
      );
    });

    test('unknown — 각 로케일 정직한 미확인 문구', () {
      expect(info(null, language: 'ko').label, '관측 시각 확인 중');
      expect(info(null, language: 'en').label, 'Observed time unavailable');
      expect(info(null, language: 'ja').label, '観測時刻を確認中');
      expect(info(null, language: 'zh-Hans').label, '观测时间确认中');
      expect(info(null, language: 'zh-Hant').label, '觀測時間確認中');
    });

    test('BCP-47 변형 입력(zh-CN/zh-TW/kor)도 정규화되어 혼합 노출 없음', () {
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'zh-CN').label,
        '观测时间 11:00',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'zh-TW').label,
        '觀測時間 11:00',
      );
      expect(
        info('2026-09-05T11:00:00+09:00', language: 'kor').label,
        '관측 시각 11:00',
      );
    });
  });

  group('now 주입 — 결정성', () {
    test('같은 입력·같은 now → 항상 동일한 결과', () {
      final a = info('2026-09-05T10:30:00+09:00');
      final b = info('2026-09-05T10:30:00+09:00');
      expect(a.label, b.label);
      expect(a.freshness, b.freshness);
      expect(a.semanticsLabel, b.semanticsLabel);
    });

    test('now 가 바뀌면 같은 관측도 경계를 넘을 수 있다(current → stale)', () {
      // 관측: 2026-09-05T10:30:00+09:00 (01:30Z). now +61분 → stale.
      final later = DateTime.utc(
        2026,
        9,
        5,
        2,
        30,
      ).add(const Duration(minutes: 61));
      final result = info('2026-09-05T10:30:00+09:00', nowOverride: later);
      expect(result.freshness, WeatherObservationFreshness.stale);
    });
  });
}
