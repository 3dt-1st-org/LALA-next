/// LALA 공용 다국어(ko/en) 헬퍼 — C3 shared 레이어의 첫 모듈.
/// main.dart 의 _copy / _isEnglish 는 여기로 위임(forwarder)하여 SSOT 를 하나로 둔다.
bool isLalaEnglish(String language) => language == 'en';

String lalaCopy(String language, {required String ko, required String en}) =>
    isLalaEnglish(language) ? en : ko;
