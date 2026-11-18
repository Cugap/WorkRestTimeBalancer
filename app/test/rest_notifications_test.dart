import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/src/labels.dart';
import 'package:work_rest_time_balancer/src/notifications/reminder_status.dart';
import 'package:work_rest_time_balancer/src/notifications/rest_notifications.dart';

import 'fake_rest_notification_platform.dart';

DateTime _at(int hour, int minute) => DateTime(2026, 3, 4, hour, minute);

RestReminder _short(DateTime at, {bool playSound = true}) => RestReminder(
  at: at,
  kind: RestKind.short,
  duration: const Duration(minutes: 3),
  playSound: playSound,
);

void main() {
  late FakeRestNotificationPlatform platform;
  late RestNotifications notifications;

  setUp(() {
    platform = FakeRestNotificationPlatform();
    notifications = RestNotifications(platform: platform);
  });

  group('напоминания через платформу', () {
    test('нажатие на уведомление доходит до оболочки', () async {
      var opened = 0;
      notifications.onOpenRequested = () => opened++;
      await notifications.initialize();

      platform.tap();

      expect(opened, 1);
    });

    test('холодный запуск нажатием виден оболочке', () async {
      platform.launched = true;

      expect(await notifications.launchedFromNotification(), isTrue);
    });

    test('текст напоминания собран из вида и длительности отдыха', () async {
      await notifications.schedule(_short(_at(9, 25)));

      final sent = platform.scheduled.single;
      // Текст напоминания — данные, а не поведение: проверяем, что он собран
      // из вида и длительности отдыха, а не конкретную формулировку.
      expect(sent.title, isNotEmpty);
      expect(sent.body, contains(restKindLabel(RestKind.short)));
      expect(sent.body, contains(formatHoursMinutes(const Duration(minutes: 3))));
      expect(sent.payload, restReminderPayload);
      expect(sent.at, _at(9, 25));
    });

    test('включённый звук оставляет Windows звук по умолчанию', () async {
      await notifications.schedule(_short(_at(9, 25)));

      final details = platform.scheduled.single.details;
      // Без элемента <audio> toast звучит системным звуком по умолчанию.
      expect(details.windows?.audio, isNull);
      expect(details.android?.playSound, isTrue);
      expect(details.android?.silent, isFalse);
    });

    test('выключенный звук делает toast Windows тихим', () async {
      await notifications.schedule(_short(_at(9, 25), playSound: false));

      final details = platform.scheduled.single.details;
      // <audio silent="true"> — иначе Windows играет звук всегда.
      expect(details.windows?.audio, isNotNull);
      expect(details.windows?.audio?.isSilent, isTrue);
      expect(details.android?.silent, isTrue);
    });

    test('повторное планирование той же точки сохраняет номер', () async {
      await notifications.schedule(_short(_at(9, 25)));
      await notifications.schedule(_short(_at(9, 25)));

      expect(platform.scheduled, hasLength(2));
      expect(platform.scheduled[0].id, platform.scheduled[1].id);
    });

    test(
      'отмена снимает и показанные, и запланированные напоминания',
      () async {
        await notifications.schedule(_short(_at(9, 25)));

        await notifications.cancelAll();

        expect(platform.cancelAllCalls, 1);
        expect(platform.scheduled, isEmpty);
      },
    );

    test('сбой платформы при планировании не срывает ритм', () async {
      platform.scheduleFailure = PlatformException(code: 'unavailable');

      await notifications.schedule(_short(_at(9, 25)));

      expect(platform.scheduled, isEmpty);
    });

    test('разрешения просит и отдаёт та же платформа', () async {
      platform.status = const ReminderStatus(
        exactAlarms: true,
        notificationsAllowed: false,
      );

      final status = await notifications.requestPermissions();

      expect(platform.permissionRequests, 1);
      expect(status, platform.status);
    });

    test('сбой чтения разрешений не пугает настройки', () async {
      platform.statusFailure = PlatformException(code: 'unavailable');

      expect(
        await notifications.read(),
        const ReminderStatus(exactAlarms: true, notificationsAllowed: true),
      );
    });

    test('разрешение на точные будильники просится через платформу', () async {
      await notifications.requestExactAlarms();

      expect(platform.exactAlarmRequests, 1);
    });
  });
}
