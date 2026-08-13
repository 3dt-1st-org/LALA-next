// V5-B SPEND (B5): offline category-band estimate is rendered for known
// categories, and an honest-unavailable label is produced for unknown/no-place
// slots — never a fabricated number. No live pricing (BLOCKED_EXTERNAL / V7).
import 'package:flutter_test/flutter_test.dart';
import 'package:lala_next_flutter_client_reference/lala_api_client.dart';

import 'package:lala_next_app/features/planner/spend_band_helpers.dart';

LalaPlanSlot _slot({String? category}) {
  return LalaPlanSlot(
    period: 'morning',
    title: 'stop',
    place: category == null
        ? null
        : LalaPlace(
            placeId: 'p',
            name: 'n',
            category: category,
            lat: 0,
            lng: 0,
            address: '',
            distanceM: 0,
            source: 's',
          ),
  );
}

void main() {
  group('spendBandFor (B5)', () {
    test('known category → band carries the estimate marker', () {
      final band = spendBandFor(_slot(category: 'restaurant'), 'ko');
      expect(band, isNotNull);
      expect(band!.label, contains('예산 구간'));
      expect(band.label, contains('맛집'));
    });

    test('every known category yields a band', () {
      for (final category in <String>['restaurant', 'culture_venue', 'event', 'attraction']) {
        expect(spendBandFor(_slot(category: category), 'en'), isNotNull,
            reason: '$category should have a band');
      }
    });

    test('B5: unknown category → null (honest-unavailable, no fabricated number)',
        () {
      expect(spendBandFor(_slot(category: 'mystery_cat'), 'ko'), isNull);
    });

    test('B5: slot with no place → null (no estimate to fabricate)', () {
      expect(spendBandFor(_slot(category: null), 'ko'), isNull);
    });

    test('band label is KO/EN bilingual via lalaCopy', () {
      final ko = spendBandFor(_slot(category: 'restaurant'), 'ko')!.label;
      final en = spendBandFor(_slot(category: 'restaurant'), 'en')!.label;
      expect(ko, contains('예산 구간'));
      expect(en, contains('budget band'));
      expect(ko == en, isFalse);
    });

    test('unavailable label is bilingual and explicit', () {
      expect(spendBandUnavailableLabel('ko'), '예산 구간 미확정');
      expect(spendBandUnavailableLabel('en'), 'Budget band unavailable');
    });
  });
}
