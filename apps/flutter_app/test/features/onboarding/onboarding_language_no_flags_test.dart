import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/features/onboarding/onboarding_state.dart';
import 'package:lala_next_app/features/onboarding/presentation/pages/language_page.dart';

void main() {
  testWidgets('language page uses KO/EN text badges and no flag emoji', (
    tester,
  ) async {
    OnboardingState.reset();
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingLanguagePage()),
    );
    await tester.pumpAndSettle();

    // 국기 이모지는 렌더링 일관성을 위해 쓰지 않는다.
    expect(find.text('🇰🇷'), findsNothing);
    expect(find.text('🇺🇸'), findsNothing);

    // 대신 KO/EN 텍스트 배지.
    expect(find.text('KO'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);

    // 언어명 라벨은 유지(ko 모드).
    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('영어'), findsOneWidget);
  });
}
