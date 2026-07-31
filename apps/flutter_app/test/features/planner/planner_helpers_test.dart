import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lala_next_app/features/planner/planner_helpers.dart';

void main() {
  group('four-period labels are exclusive and alias-safe', () {
    const cases = <String, (String, String)>{
      'morning': ('아침', 'Morning'),
      'mo': ('아침', 'Morning'),
      'lunch': ('점심', 'Lunch'),
      'lu': ('점심', 'Lunch'),
      'afternoon': ('오후', 'Afternoon'),
      'af': ('오후', 'Afternoon'),
      'dinner': ('저녁', 'Dinner'),
      'di': ('저녁', 'Dinner'),
      'evening': ('저녁', 'Dinner'),
      'night': ('저녁', 'Dinner'),
    };

    for (final entry in cases.entries) {
      test('${entry.key} maps to one KO or EN label', () {
        expect(periodLabel(entry.key, language: 'ko'), entry.value.$1);
        expect(periodLabel(entry.key, language: 'en'), entry.value.$2);
      });
    }
  });

  test('lunch and dinner aliases have intentional, distinct meal icons', () {
    expect(periodIcon('lunch'), Icons.lunch_dining_outlined);
    expect(periodIcon('lu'), Icons.lunch_dining_outlined);
    expect(periodIcon('dinner'), Icons.dinner_dining_outlined);
    expect(periodIcon('di'), Icons.dinner_dining_outlined);
    expect(periodIcon('lunch'), isNot(periodIcon('dinner')));
  });

  test('unknown periods do not leak the opposite language', () {
    expect(periodLabel('저녁식사', language: 'en'), 'Period');
    expect(periodLabel('late supper', language: 'ko'), '시간대');
  });
}
