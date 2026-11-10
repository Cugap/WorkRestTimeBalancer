import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/src/notifications/rest_notifications.dart';

void main() {
  RestReminder reminder({
    RestKind kind = RestKind.short,
    bool playSound = true,
    Duration duration = const Duration(minutes: 3),
    DateTime? at,
  }) => RestReminder(
    at: at ?? DateTime(2026, 11, 10, 9, 25),
    kind: kind,
    duration: duration,
    playSound: playSound,
  );

  group('раскладка напоминания', () {
    test('текст называет вид отдыха и его длительность', () {
      final planned = planNotification(
        reminder(kind: RestKind.long, duration: const Duration(minutes: 10)),
      );

      expect(planned.title, 'Пора отдохнуть');
      expect(planned.body, 'Длинный отдых · 10 мин');
    });

    test('идентификатор различает вид отдыха в одну и ту же минуту', () {
      final at = DateTime(2026, 11, 10, 13, 0);

      final ids = {
        for (final kind in RestKind.values)
          planNotification(reminder(at: at, kind: kind)).id,
      };

      expect(ids, hasLength(RestKind.values.length));
    });

    test(
      'идентификатор не зависит от звука: перепланирование заменяет toast',
      () {
        final loud = planNotification(reminder());
        final silent = planNotification(reminder(playSound: false));

        expect(silent.id, loud.id);
      },
    );
  });

  group('каналы Android', () {
    test('у каждого вида отдыха свой канал', () {
      expect(
        planNotification(reminder(kind: RestKind.short))
            .details
            .android
            ?.channelId,
        'rest_short',
      );
      expect(
        planNotification(reminder(kind: RestKind.long))
            .details
            .android
            ?.channelId,
        'rest_long',
      );
      expect(
        planNotification(reminder(kind: RestKind.meal))
            .details
            .android
            ?.channelId,
        'rest_meal',
      );
    });
  });

  group('звук напоминания', () {
    test('со включённым звуком Windows показывает обычный toast', () {
      final details = planNotification(reminder()).details;

      expect(details.windows?.audio, isNull);
      expect(details.android?.playSound, isTrue);
      expect(details.android?.silent, isFalse);
      expect(details.iOS?.presentSound, isTrue);
    });

    test('с выключенным звуком Windows показывает молчащий toast', () {
      final details = planNotification(reminder(playSound: false)).details;

      expect(details.windows?.audio, isNotNull);
      expect(details.windows?.audio?.isSilent, isTrue);
      expect(details.android?.playSound, isFalse);
      expect(details.android?.silent, isTrue);
      expect(details.iOS?.presentSound, isFalse);
    });
  });
}
