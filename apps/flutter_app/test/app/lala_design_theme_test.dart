import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_app/app/lala_visual_tokens.dart';

void main() {
  test('home and onboarding palette is shared by the app theme', () {
    final scheme = LalaDesignTheme.colorScheme;

    expect(scheme.primary, LalaVisualColors.primary);
    expect(scheme.surface, LalaVisualColors.surface);
    expect(scheme.onSurface, LalaVisualColors.ink);
    expect(scheme.onSurfaceVariant, LalaVisualColors.muted);
    expect(scheme.outline, LalaVisualColors.line);
  });

  test('Pretendard and CJK fallback reach every semantic text style', () {
    final textTheme = LalaDesignTheme.textTheme(ThemeData().textTheme);

    for (final style in <TextStyle?>[
      textTheme.headlineMedium,
      textTheme.titleLarge,
      textTheme.bodyMedium,
      textTheme.labelLarge,
    ]) {
      expect(style?.fontFamily, LalaDesignTheme.fontFamily);
      expect(style?.fontFamilyFallback, LalaDesignTheme.fontFamilyFallback);
      expect(style?.color, LalaVisualColors.ink);
    }
  });
}
