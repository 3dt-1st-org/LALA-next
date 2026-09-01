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
    return lalaCopyMulti(
      language,
      ko: '제한적 오프라인 데이터',
      en: 'Limited offline data',
      ja: '制限付きオフラインデータ',
      zhHans: '有限离线数据',
      zhHant: '有限離線資料',
    );
  }
  return switch ((value ?? '').trim()) {
    'db' => lalaCopyMulti(
      language,
      ko: '실시간 추천',
      en: 'Live recommendations',
      ja: 'リアルタイムのおすすめ',
      zhHans: '实时推荐',
      zhHant: '即時推薦',
    ),
    'mixed' => lalaCopyMulti(
      language,
      ko: '실시간·공식 데이터',
      en: 'Live + official data',
      ja: 'リアルタイム＋公式データ',
      zhHans: '实时＋官方数据',
      zhHant: '即時＋官方資料',
    ),
    'skeleton' => lalaCopyMulti(
      language,
      ko: '로컬 큐레이션',
      en: 'LALA curation',
      ja: 'LALAセレクション',
      zhHans: 'LALA精选',
      zhHant: 'LALA精選',
    ),
    '' => '-',
    final source => source,
  };
}

String weatherSourceLabel(String? value, {String language = 'ko'}) {
  if (isPlaceholderWeatherSource(value) || isFallbackSourceCode(value)) {
    return lalaCopyMulti(
      language,
      ko: '날씨 준비 중',
      en: 'Weather pending',
      ja: '天気情報を準備中',
      zhHans: '天气信息准备中',
      zhHant: '天氣資訊準備中',
    );
  }
  return switch ((value ?? '').trim()) {
    'db' => lalaCopyMulti(
      language,
      ko: '실시간 날씨',
      en: 'Live weather',
      ja: 'リアルタイム天気',
      zhHans: '实时天气',
      zhHant: '即時天氣',
    ),
    'db+airkorea_sido_realtime' => lalaCopyMulti(
      language,
      ko: '실시간 날씨·AirKorea 대기질',
      en: 'Live weather + AirKorea air quality',
      ja: 'リアルタイム天気＋AirKorea大気質',
      zhHans: '实时天气＋AirKorea空气质量',
      zhHant: '即時天氣＋AirKorea空氣品質',
    ),
    'kma_ultra_srt_ncst' => lalaCopyMulti(
      language,
      ko: '기상청 실황',
      en: 'KMA live weather',
      ja: '韓国気象庁の実況',
      zhHans: '韩国气象厅实况',
      zhHant: '韓國氣象廳實況',
    ),
    'airkorea_sido_realtime' => lalaCopyMulti(
      language,
      ko: 'AirKorea 대기질',
      en: 'AirKorea live air quality',
      ja: 'AirKorea大気質',
      zhHans: 'AirKorea空气质量',
      zhHant: 'AirKorea空氣品質',
    ),
    'kma_ultra_srt_ncst+airkorea_sido_realtime' => lalaCopyMulti(
      language,
      ko: '기상청·AirKorea 실황',
      en: 'KMA weather + AirKorea air quality',
      ja: '韓国気象庁＋AirKorea実況',
      zhHans: '韩国气象厅＋AirKorea实况',
      zhHant: '韓國氣象廳＋AirKorea實況',
    ),
    'mixed' => lalaCopyMulti(
      language,
      ko: '실시간·공식 날씨',
      en: 'Live + official weather',
      ja: 'リアルタイム＋公式天気',
      zhHans: '实时＋官方天气',
      zhHant: '即時＋官方天氣',
    ),
    '' => '-',
    final source => sourceLabel(source, language: language),
  };
}
