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

    test('분이 0이 아닌 음수 오프셋(-05:30): 부호가 시·분 모두에 적용된다', () {
      // 2026-09-04T09:00 -05:30 == 2026-09-04 14:30Z == KST 2026-09-04 23:30.
      // 부호를 시에만 적용하면 -04:30 으로 잘못 계산된다(회귀 방지).
      final result = info('2026-09-04T09:00:00-05:30');
      expect(result.freshness, WeatherObservationFreshness.stale);
      expect(result.label, '관측 시각 2026-09-04 23:30');
    });

    test('분이 0이 아닌 양수 오프셋(+05:30)도 정확히 환산된다', () {
      // 2026-09-05T08:00 +05:30 == 2026-09-05 02:30Z == now → age 0, KST 11:30.
      final result = info('2026-09-05T08:00:00+05:30');
      expect(result.freshness, WeatherObservationFreshness.current);
      expect(result.label, '관측 시각 11:30');
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

    test('정규화로 넘어가는 무효 성분은 명시적으로 거부(2월 30일 등)', () {
      // DateTime 은 범위 밖 성분을 이월 계산한다(2/30→3/2). 정규화 결과를
      // 관측 시각으로 fabricate 하지 않도록 왕복 검사로 거부한다.
      for (final raw in [
        '2026-02-30T09:00:00+09:00', // 존재하지 않는 날짜(2월 30일)
        '2026-09-31 09:00', // 존재하지 않는 날짜(9월 31일, dataTime 형식)
        '2026-02-29T09:00:00+09:00', // 평년 2월 29일(2026은 평년)
        '2026-09-05T24:00:00+09:00', // 불가능한 시(24시 → 다음날 0시 정규화)
        '2026-09-05T09:60:00+09:00', // 불가능한 분(60분 → +1시간 정규화)
        '2026-09-05T09:00:60+09:00', // 불가능한 초(60초 → +1분 정규화)
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

    test('윤년 2월 29일은 유효하게 통과한다(거부 과잉 없음)', () {
      // 2024-02-29 23:00 KST == 2024-02-29 14:00Z — 아주 오래전 관측(stale).
      final result = info('2024-02-29T23:00:00+09:00');
      expect(result.freshness, WeatherObservationFreshness.stale);
      expect(result.label, '관측 시각 2024-02-29 23:00');
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
