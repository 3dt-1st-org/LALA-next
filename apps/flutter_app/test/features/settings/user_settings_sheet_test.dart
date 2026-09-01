import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/features/settings/widgets/user_settings_sheet.dart';

void main() {
  test('compact language labels stay concise and distinct', () {
    expect(compactLanguageOptionLabel('ko'), 'KO');
    expect(compactLanguageOptionLabel('en'), 'EN');
    expect(compactLanguageOptionLabel('ja'), '日本');
    expect(compactLanguageOptionLabel('zh-Hans'), '简中');
    expect(compactLanguageOptionLabel('zh-Hant'), '繁中');
  });
}
