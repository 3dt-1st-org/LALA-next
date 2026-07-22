// 추천/날씨 데이터 소스 라벨 공용 헬퍼 (C3 추출).
// main.dart 의 _sourceLabel / _weatherSourceLabel /
// _isPlaceholderWeatherSource / _isFallbackSourceCode 가 여기로 정식화되었다.
// 의존: isLalaEnglish (shared/l10n/lala_copy.dart).
import '../l10n/lala_copy.dart';

bool isFallbackSourceCode(String? value) {
  final normalized = (value ?? '').trim();
  return normalized == 'public_mvp_snapshot' ||
      normalized == 'fallback' ||
      normalized.endsWith('_fallback') ||
      normalized.contains('snapshot_fallback');
}

bool isPlaceholderWeatherSource(String? source) {
  final normalized = (source ?? '').trim();
  return normalized.isEmpty ||
      normalized == 'skeleton' ||
      normalized == 'fallback' ||
      normalized == 'unavailable' ||
      normalized.endsWith('_fallback');
}

String sourceLabel(String? value, {String language = 'ko'}) {
  if (isFallbackSourceCode(value)) {
    return isLalaEnglish(language) ? 'Limited offline data' : '제한적 오프라인 데이터';
  }
  if (isLalaEnglish(language)) {
    return switch ((value ?? '').trim()) {
      'db' => 'Live recommendations',
      'mixed' => 'Live + official data',
      'skeleton' => 'LALA curation',
      '' => '-',
      final source => source,
    };
  }
  return switch ((value ?? '').trim()) {
    'db' => '실시간 추천',
    'mixed' => '실시간·공식 데이터',
    'skeleton' => '로컬 큐레이션',
    '' => '-',
    final source => source,
  };
}

String weatherSourceLabel(String? value, {String language = 'ko'}) {
  if (isPlaceholderWeatherSource(value) || isFallbackSourceCode(value)) {
    return isLalaEnglish(language) ? 'Weather pending' : '날씨 준비 중';
  }
  if (isLalaEnglish(language)) {
    return switch ((value ?? '').trim()) {
      'db' => 'Live weather',
      'db+airkorea_sido_realtime' => 'Live weather + AirKorea air quality',
      'kma_ultra_srt_ncst' => 'KMA live weather',
      'airkorea_sido_realtime' => 'AirKorea live air quality',
      'kma_ultra_srt_ncst+airkorea_sido_realtime' =>
        'KMA weather + AirKorea air quality',
      'mixed' => 'Live + official weather',
      '' => '-',
      final source => sourceLabel(source, language: language),
    };
  }
  return switch ((value ?? '').trim()) {
    'db' => '실시간 날씨',
    'db+airkorea_sido_realtime' => '실시간 날씨·AirKorea 대기질',
    'kma_ultra_srt_ncst' => '기상청 실황',
    'airkorea_sido_realtime' => 'AirKorea 대기질',
    'kma_ultra_srt_ncst+airkorea_sido_realtime' => '기상청·AirKorea 실황',
    'mixed' => '실시간·공식 날씨',
    '' => '-',
    final source => sourceLabel(source, language: language),
  };
}
