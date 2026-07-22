// 미세먼지 등급/상황 라벨 공용 헬퍼 (C3 추출).
// main.dart 의 _dustLabel / _dustGradeLabel / _dustPollutantGradeLabel /
// _compactDustPart / _dustSituationLabel 이 여기로 정식화되었다.
// 의존: isLalaEnglish, singleLanguageText, LalaDust.
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import '../l10n/lala_copy.dart';
import '../l10n/multi_language_text.dart';

String dustLabel(LalaDust dust, String language) {
  return dustGradeLabel(dust.grade, dust.gradeKo, language);
}

String dustGradeLabel(String gradeCode, String gradeKo, String language) {
  if (!isLalaEnglish(language)) {
    final localizedKo = singleLanguageText(gradeKo, language);
    return localizedKo ?? gradeCode;
  }
  return switch (gradeCode.trim()) {
    'good' => 'Good',
    'normal' => 'Normal',
    'bad' => 'Bad',
    'very_bad' => 'Very bad',
    final grade when grade.isEmpty => gradeKo,
    final grade => grade,
  };
}

String dustPollutantGradeLabel(
  LalaDust dust,
  String pollutant,
  String language,
) {
  final isPm10 = pollutant == 'pm10';
  final gradeCode = (isPm10 ? dust.pm10Grade : dust.pm25Grade).trim();
  final gradeKo = (isPm10 ? dust.pm10GradeKo : dust.pm25GradeKo).trim();
  if (gradeCode.isEmpty && gradeKo.isEmpty) {
    return dustLabel(dust, language);
  }
  return dustGradeLabel(gradeCode, gradeKo, language);
}

String compactDustPart({
  required String label,
  required String value,
  required String grade,
}) {
  final cleanedValue = value.trim();
  final cleanedGrade = grade.trim();
  if (cleanedValue.isEmpty) {
    return '$label $cleanedGrade'.trim();
  }
  if (cleanedGrade.isEmpty) {
    return '$label $cleanedValue';
  }
  return '$label $cleanedValue $cleanedGrade';
}

/// 단일 항목 수치 + 등급 결합 라벨(C3 추출 — main.dart 의 _dustPollutantValueLabel).
String dustPollutantValueLabel({
  required String value,
  required String grade,
  required String language,
}) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return grade;
  }
  final unit = isLalaEnglish(language) ? 'ug/m3' : '㎍/m³';
  return '$normalized$unit · $grade';
}

/// 날씨 알림용 미세먼지 요약 라벨(C3 추출 — main.dart 의 _weatherPillDustLabel).
/// PM10/PM2.5 수치+등급이 있으면 "PM10 … · PM2.5 …", 없으면 상황 라벨로 대체.
String weatherPillDustLabel(LalaDust dust, String language) {
  final pm10 = dust.pm10.trim();
  final pm25 = dust.pm25.trim();
  final pm10Grade = dustPollutantGradeLabel(dust, 'pm10', language).trim();
  final pm25Grade = dustPollutantGradeLabel(dust, 'pm25', language).trim();
  final values = [
    if (pm10.isNotEmpty)
      compactDustPart(label: 'PM10', value: pm10, grade: pm10Grade),
    if (pm25.isNotEmpty)
      compactDustPart(label: 'PM2.5', value: pm25, grade: pm25Grade),
  ];
  if (values.isNotEmpty) {
    return values.join(' · ');
  }
  return dustSituationLabel(dust, language, includePrefix: false);
}

String dustSituationLabel(
  LalaDust dust,
  String language, {
  bool includePrefix = true,
}) {
  final grade = dustLabel(dust, language).trim();
  final pm10 = dust.pm10.trim();
  final pm25 = dust.pm25.trim();
  final hasPm10 = pm10.isNotEmpty;
  final hasPm25 = pm25.isNotEmpty;
  final pm10Grade = dustPollutantGradeLabel(dust, 'pm10', language).trim();
  final pm25Grade = dustPollutantGradeLabel(dust, 'pm25', language).trim();
  if (isLalaEnglish(language)) {
    final values = [
      if (hasPm10)
        compactDustPart(label: 'PM10', value: pm10, grade: pm10Grade),
      if (hasPm25)
        compactDustPart(label: 'PM2.5', value: pm25, grade: pm25Grade),
    ];
    if (values.isEmpty) {
      return includePrefix ? 'Dust $grade' : grade;
    }
    return [if (includePrefix) 'Dust', values.join(' · ')].join(' ');
  }
  final values = [
    if (hasPm10) compactDustPart(label: '미세', value: pm10, grade: pm10Grade),
    if (hasPm25) compactDustPart(label: '초미세', value: pm25, grade: pm25Grade),
  ];
  if (values.isEmpty) {
    return includePrefix ? '미세먼지 $grade' : grade;
  }
  return [if (includePrefix) '미세먼지', values.join(' · ')].join(' ');
}
