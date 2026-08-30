// 데이터셋 신선도(data_as_of) 라벨 공용 헬퍼.
// map_bottom_dock 의 private _freshnessLabel 을 정식화했다(search 카드도 동일
// 문구/파싱 규칙을 공유). 절대 fabricate/placeholder timestamp 를 넣지 않는다.
import '../l10n/lala_copy.dart';

final RegExp _freshnessDateOnly = RegExp(r'^(\d{4}-\d{2}-\d{2})');

/// 정직한 신선도 라벨: 실제 snapshot generated_at 의 날짜(YYYY-MM-DD) 부분만 사용.
/// [dataAsOf] 가 없거나 날짜 파식 불가 → null(honest absence, 라벨 미표시).
String? datasetFreshnessLabel(String? dataAsOf, String language) {
  if (dataAsOf == null) return null;
  final match = _freshnessDateOnly.firstMatch(dataAsOf);
  if (match == null) return null;
  final date = match.group(1)!;
  return lalaCopyMulti(
    language,
    ko: '데이터 기준: $date',
    en: 'Data as of: $date',
    ja: 'データ基準: $date',
    zhHans: '数据截至：$date',
    zhHant: '數據截至：$date',
  );
}
