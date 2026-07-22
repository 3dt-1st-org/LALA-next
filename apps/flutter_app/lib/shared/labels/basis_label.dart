// 점수 데이터 근거 라벨 공용 헬퍼 (C3 추출).
// main.dart 의 _basisLabel 이 여기로 정식화되었다.
// 의존: isFallbackSourceCode, isLalaEnglish (shared/labels/source_label.dart, shared/l10n/lala_copy.dart).
import '../l10n/lala_copy.dart';
import 'source_label.dart';

/// 점수 dataBasis 코드를 표시 라벨로 변환(C3 추출 — main.dart 의 _basisLabel).
String basisLabel(String value, {String language = 'ko'}) {
  if (isFallbackSourceCode(value)) {
    return isLalaEnglish(language) ? 'Limited offline data' : '제한적 오프라인 데이터';
  }
  if (isLalaEnglish(language)) {
    return switch (value.trim()) {
      'actual_data' => 'Real data',
      'dev_seed' => 'LALA curation',
      'local_fixture' => 'LALA local data',
      'analytics.place_score_snapshots' => 'LALA recommendation score',
      'local_curation' => 'LALA curation',
      final basis when basis.isEmpty => '-',
      final basis => basis,
    };
  }
  return switch (value.trim()) {
    'actual_data' => '실데이터',
    'dev_seed' => '로컬 큐레이션',
    'local_fixture' => '로컬 데이터',
    'analytics.place_score_snapshots' => 'LALA 추천 점수',
    'local_curation' => '로컬 큐레이션',
    final basis when basis.isEmpty => '-',
    final basis => basis,
  };
}
