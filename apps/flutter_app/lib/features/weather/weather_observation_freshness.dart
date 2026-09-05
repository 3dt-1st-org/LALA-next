// S-14 날씨 관측 시각(label + freshness) 순수 헬퍼.
// LalaWeather.recordTime 를 화면 문구로 바꾼다. 절대 시각을 발명하지 않는다:
// null/망가진 값/미래 시계오차는 정직한 unknown 상태로 내보낸다.
//
// 파싱하는 wire 표현(현행 fixtures/tests 기준 두 가지):
//  1. ISO-8601 + 오프셋 — `2026-06-18T23:00:00+09:00`
//     (docs/api/flutter-contract.md, apps/api KMA/DB isoformat 경로)
//  2. KMA/AirKorea dataTime 비-타임존 형식 — `2026-06-21 12:00`
//     (apps/api weather_service.py 의 airkorea 단독 record_time 경로).
//     두 공급자 모두 한국 표준시(KST, +09:00) 벽시계를 보고하므로 KST 로 해석한다.
//     기기 로컬 타임존으로 해석하지 않는다(timezone truth).
import '../../shared/l10n/lala_copy.dart';

/// S-14 UI 신선도 정책: 관측 시각이 이 창 안에 있으면 '최신 관측', 지나면
/// '이전 관측값'으로 표시한다.
///
/// 근거: 기상청 초단기실황(kma_ultra_srt_ncst)은 약 10분, AirKorea 시도 실시간
/// 대기질은 약 1시간 주기로 갱신된다. 60분을 넘었다는 것은 늦어도 공급자 한
/// 사이클 이상 갱신이 지연된 것이므로 실시간처럼 보이게 두는 대신 stale 로
/// 표시한다. Local Signals 의 14일 임계값과는 무관한 날씨 화면 전용 정책이다.
const Duration kWeatherObservationCurrentWindow = Duration(minutes: 60);

/// 관측 시각이 서버/기기 시계 오차로 살짝 미래일 수 있는 허용치. 이보다 많이
/// 미래면(미래 skew) 시각 자체를 신뢰할 수 없어 정직한 unknown 상태가 된다.
const Duration kWeatherObservationClockSkewTolerance = Duration(minutes: 2);

/// KST(UTC+9). 관측 벽시계 표기는 항상 이 타임존을 기준으로 한다.
const Duration kWeatherKstOffset = Duration(hours: 9);

/// 관측 시각 freshness 상태.
enum WeatherObservationFreshness {
  /// 파싱 가능하고 [kWeatherObservationCurrentWindow] 안의 관측.
  current,

  /// 파싱은 가능하나 신선도 창을 지난 관측(나이는 표시용 라벨에만 반영).
  stale,

  /// record_time 부재/망가짐/미래 skew — 나이를 발명하지 않는다.
  unknown,
}

/// 관측 시각 표시 결과.
/// - [label]: '관측 시각 14:30' / '관측 시각 2026-06-21 14:30' / unknown 문구.
/// - [statusLabel]: '최신 관측' / '이전 관측값' / unknown 시 빈 문자열.
/// - [semanticsLabel]: 스크린 리더용 결합 문구(label + 상태).
typedef WeatherObservationInfo = ({
  String label,
  String statusLabel,
  String semanticsLabel,
  WeatherObservationFreshness freshness,
});

final RegExp _recordTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|[+-]\d{2}:?\d{2})?$',
);

/// [recordTime] 을 [now] 기준 관측 라벨 + freshness 로 변환하는 순수 함수.
/// [now] 를 주입받으므로 완전히 결정적이다. 어떤 입력도 예외를 던지지 않는다.
WeatherObservationInfo weatherObservationInfo({
  required String? recordTime,
  required DateTime now,
  required String language,
}) {
  final observed = _parseRecordTime(recordTime);
  if (observed == null) {
    return _unknownInfo(language);
  }

  final nowUtc = now.toUtc();
  final age = nowUtc.difference(observed);
  if (age < -kWeatherObservationClockSkewTolerance) {
    // 미래 skew: 나이를 fabricate 하지 않고 정직하게 unknown.
    return _unknownInfo(language);
  }

  final clampedAge = age.isNegative ? Duration.zero : age;
  final freshness = clampedAge <= kWeatherObservationCurrentWindow
      ? WeatherObservationFreshness.current
      : WeatherObservationFreshness.stale;

  final observedKst = observed.add(kWeatherKstOffset);
  final nowKst = nowUtc.add(kWeatherKstOffset);
  final sameDay =
      observedKst.year == nowKst.year &&
      observedKst.month == nowKst.month &&
      observedKst.day == nowKst.day;
  final clock =
      '${observedKst.hour.toString().padLeft(2, '0')}:'
      '${observedKst.minute.toString().padLeft(2, '0')}';
  final stamped = sameDay
      ? clock
      : '${observedKst.year.toString().padLeft(4, '0')}-'
            '${observedKst.month.toString().padLeft(2, '0')}-'
            '${observedKst.day.toString().padLeft(2, '0')} $clock';

  final labelPrefix = lalaCopyMulti(
    language,
    ko: '관측 시각',
    en: 'Observed',
    ja: '観測時刻',
    zhHans: '观测时间',
    zhHant: '觀測時間',
  );
  final statusLabel = switch (freshness) {
    WeatherObservationFreshness.current => lalaCopyMulti(
      language,
      ko: '최신 관측',
      en: 'Current',
      ja: '最新観測',
      zhHans: '最新观测',
      zhHant: '最新觀測',
    ),
    WeatherObservationFreshness.stale => lalaCopyMulti(
      language,
      ko: '이전 관측값',
      en: 'Earlier observation',
      ja: '以前の観測',
      zhHans: '较早观测',
      zhHant: '較早觀測',
    ),
    WeatherObservationFreshness.unknown => '',
  };

  final label = '$labelPrefix $stamped';
  return (
    label: label,
    statusLabel: statusLabel,
    semanticsLabel: statusLabel.isEmpty ? label : '$label, $statusLabel',
    freshness: freshness,
  );
}

WeatherObservationInfo _unknownInfo(String language) {
  final label = lalaCopyMulti(
    language,
    ko: '관측 시각 확인 중',
    en: 'Observed time unavailable',
    ja: '観測時刻を確認中',
    zhHans: '观测时间确认中',
    zhHant: '觀測時間確認中',
  );
  return (
    label: label,
    statusLabel: '',
    semanticsLabel: label,
    freshness: WeatherObservationFreshness.unknown,
  );
}

/// wire 표현을 절대 시각(UTC 기반 DateTime)으로 파싱. 실패 시 null.
DateTime? _parseRecordTime(String? raw) {
  if (raw == null) return null;
  final match = _recordTimePattern.firstMatch(raw.trim());
  if (match == null) return null;

  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  final hour = int.tryParse(match.group(4)!);
  final minute = int.tryParse(match.group(5)!);
  final second = int.tryParse(match.group(6) ?? '0')!;
  final micros = int.tryParse((match.group(7) ?? '0').padRight(6, '0'));
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null ||
      micros == null) {
    return null;
  }

  final zone = match.group(8);
  final wall = DateTime.tryParse(
    '${year.toString().padLeft(4, '0')}-'
    '${month.toString().padLeft(2, '0')}-'
    '${day.toString().padLeft(2, '0')}T'
    '${hour.toString().padLeft(2, '0')}:'
    '${minute.toString().padLeft(2, '0')}:'
    '${second.toString().padLeft(2, '0')}.${micros.toString().padLeft(6, '0')}Z',
  );
  if (wall == null) return null;

  if (zone == null) {
    // 비-타임존 dataTime 형식은 KST 벽시계로 해석한다(timezone truth).
    return wall.subtract(kWeatherKstOffset);
  }
  if (zone == 'Z') {
    return wall;
  }

  final sign = zone.startsWith('-') ? -1 : 1;
  final digits = zone.substring(1).replaceAll(':', '');
  final zoneHour = int.tryParse(digits.substring(0, 2));
  final zoneMinute = int.tryParse(digits.substring(2, 4));
  if (zoneHour == null || zoneMinute == null) return null;
  // ISO-8601 오프셋 범위(±23:59) 밖이면 망가진 값으로 취급.
  if (zoneHour > 23 || zoneMinute > 59) return null;
  return wall.subtract(Duration(hours: sign * zoneHour, minutes: zoneMinute));
}
