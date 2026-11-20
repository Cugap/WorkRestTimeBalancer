import 'package:flutter_test/flutter_test.dart';

import 'suspending_clock.dart';

void main() {
  group('MonotonicClock', () {
    test('идёт вместе с настенными часами, пока сна не было', () {
      final clock = SuspendingClock(DateTime(2026, 3, 4, 9));

      expect(clock.now(), DateTime(2026, 3, 4, 9));

      clock.advance(const Duration(minutes: 25));

      expect(clock.now(), DateTime(2026, 3, 4, 9, 25));
    });

    test('догоняет время, прошедшее при заблокированном экране', () {
      // Android в глубоком сне останавливает Stopwatch: монотонное время
      // стоит, а настенные часы идут. Отставшие часы показывали бы, что
      // рабочего дня осталось больше, чем есть на самом деле.
      final clock = SuspendingClock(DateTime(2026, 3, 4, 9));

      clock.sleep(const Duration(hours: 2));

      expect(clock.now(), DateTime(2026, 3, 4, 11));
    });

    test('перевод настенных часов назад ритм не откатывает', () {
      final clock = SuspendingClock(DateTime(2026, 3, 4, 12));
      clock.advance(const Duration(minutes: 5));

      clock.setWallBack(const Duration(hours: 2));

      expect(clock.now(), DateTime(2026, 3, 4, 12, 5));
    });

    test('перевод часов назад после сна не откатывает показание', () {
      final clock = SuspendingClock(DateTime(2026, 3, 4, 9));
      clock.sleep(const Duration(hours: 2));
      expect(clock.now(), DateTime(2026, 3, 4, 11));

      clock.setWallBack(const Duration(hours: 1));

      expect(clock.now(), DateTime(2026, 3, 4, 11));
    });
  });
}
