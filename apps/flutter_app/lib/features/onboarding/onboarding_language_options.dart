/// 온보딩에서 지원하는 언어 선택지의 단일 정의.
///
/// 배지는 국기 이모지 대신 짧은 텍스트를 사용하고, 이름은 각 언어의 고유명으로
/// 표시한다. 첫 질문의 빠른 선택 메뉴와 S2 확인 화면이 이 목록을 공유한다.
class OnboardingLanguageChoice {
  const OnboardingLanguageChoice(this.code, this.badge, this.endonym);

  final String code;
  final String badge;
  final String endonym;
}

const List<OnboardingLanguageChoice> onboardingLanguageChoices =
    <OnboardingLanguageChoice>[
      OnboardingLanguageChoice('ko', 'KO', '한국어'),
      OnboardingLanguageChoice('en', 'EN', 'English'),
      OnboardingLanguageChoice('ja', 'JA', '日本語'),
      OnboardingLanguageChoice('zh-Hans', '简', '简体中文'),
      OnboardingLanguageChoice('zh-Hant', '繁', '繁體中文'),
    ];
