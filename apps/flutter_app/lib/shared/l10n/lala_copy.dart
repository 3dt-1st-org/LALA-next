/// LALA 공용 다국어(ko/en) 헬퍼 — C3 shared 레이어의 첫 모듈.
/// main.dart 의 _copy / _isEnglish 는 여기로 위임(forwarder)하여 SSOT 를 하나로 둔다.
///
/// V6: 외국인 관광객 UX. 지원 언어를 ko/en 에 ja/zh-Hans/zh-Hant 로 확장한다.
///
/// 두 진입점의 역할 분담(계약 I1/I5):
/// - [lalaCopy] — 레거시 ko/en 2-문구 시그니처. ko 로 정규화되는 언어에서만 KO 를
///   반환하고, 방문객 로케일(ja/zh-Hans/zh-Hant)은 **정직한 EN 폴백**을 반환한다.
///   즉 아직 이관되지 않은 호출점도 방문객 화면에 한국어를 노출하지 않는다.
///   ko/en 호출자의 출력은 바이트 단위로 기존과 동일하다(계약 I2).
/// - [lalaCopyMulti] — 실제 번역문을 가진 진입점. 핵심 방문객 플로우는 이쪽을 쓴다.
library;

/// V6 지원 언어 코드(정규형). 이 목록 외 값은 ko 로 정규화된다.
const List<String> kLalaLanguages = <String>[
  'ko',
  'en',
  'ja',
  'zh-Hans',
  'zh-Hant',
];

/// 입력 언어 코드를 V6 정규형으로 변환한다. 알 수 없는 값은 'ko'(기존 동작).
String normalizeLalaLanguage(String? language) {
  switch (language) {
    case 'en':
      return 'en';
    case 'ja':
      return 'ja';
    case 'zh-Hans':
    // BCP-47 접두어 정규화: 'zh-CN'/'zh-SG' 등도简体로.
    case 'zh':
    case 'zh-CN':
    case 'zh-SG':
    case 'zh-Hans-CN':
      return 'zh-Hans';
    case 'zh-Hant':
    case 'zh-TW':
    case 'zh-HK':
    case 'zh-MO':
    case 'zh-Hant-TW':
      return 'zh-Hant';
    case 'ko':
    case 'kor':
    case 'korean':
      return 'ko';
  }
  return 'ko';
}

bool isLalaEnglish(String language) => language == 'en';

/// 확장 로케일(ja/zh-Hans/zh-Hant) 여부. 정규화 후 판정한다.
bool isLalaVisitorLocale(String language) {
  final normalized = normalizeLalaLanguage(language);
  return normalized == 'ja' || normalized == 'zh-Hans' ||
      normalized == 'zh-Hant';
}

/// V6 호환 시맨틱(계약 I1/I5): `ko` 로 정규화되는 언어에서만 KO 문구를 반환하고,
/// 그 외 모든 로케일(en/ja/zh-Hans/zh-Hant)은 EN 문구를 반환한다.
/// Why: 아직 lalaCopyMulti 로 이관되지 않은 기존 호출점들이 방문객 로케일에서
/// 한국어를 새어 나가게 두는 대신, SSOT 자체에서 정직한 EN 폴백을 보장한다.
/// ko/en 호출자의 출력은 바이트 단위로 동일하다(계약 I2).
String lalaCopy(String language, {required String ko, required String en}) =>
    normalizeLalaLanguage(language) == 'ko' ? ko : en;

/// V6 확장 copy. ko/en 는 [lalaCopy] 와 동일하게 반환하고, ja/zh-Hans/zh-Hant 는
/// 전달된 번역문을 사용한다(번역이 없으면 en — 계약 §6 정직 폴백: 확장 로케일에서
/// 영어 문장은 정직, 한국어 노출은 금지).
String lalaCopyMulti(
  String language, {
  required String ko,
  required String en,
  String? ja,
  String? zhHans,
  String? zhHant,
}) {
  switch (normalizeLalaLanguage(language)) {
    case 'en':
      return en;
    case 'ja':
      return ja ?? en;
    case 'zh-Hans':
      return zhHans ?? en;
    case 'zh-Hant':
      return zhHant ?? en;
    case 'ko':
      return ko;
  }
  return ko;
}

/// 서버 데이터 언어(§10): API 는 ko/en 만 이해하므로 확장 로케일은 en 로 요청한다.
String apiRequestLanguage(String language) {
  final normalized = normalizeLalaLanguage(language);
  return normalized == 'ko' ? 'ko' : 'en';
}
