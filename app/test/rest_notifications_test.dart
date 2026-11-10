import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
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
    test(
      'инициализация не просит разрешения раньше включённых настроек',
      () async {
        await notifications.initialize();

        final darwin = platform.darwin;
        expect(darwin, isNotNull);
        // Разрешения спрашивает requestPermissions, когда напоминания включены:
        // иначе приложение просило бы их у того, кто их выключил.
        expect(darwin!.requestAlertPermission, isFalse);
        expect(darwin.requestSoundPermission, isFalse);
        expect(darwin.requestBadgePermission, isFalse);
        // Показ в переднем плане включён: напоминание видно и при открытом
        // приложении.
        expect(darwin.defaultPresentAlert, isTrue);
        expect(darwin.defaultPresentBanner, isTrue);
        expect(darwin.defaultPresentList, isTrue);
      },
    );

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

    test('звук и показ передаются в детали iOS', () async {
      await notifications.schedule(_short(_at(9, 25)));

      final sent = platform.scheduled.single;
      expect(sent.title, 'Пора отдохнуть');
      expect(sent.body, 'Короткий отдых · 3 мин');
      expect(sent.payload, restReminderPayload);
      expect(sent.at, _at(9, 25));

      final ios = sent.details.iOS!;
      expect(ios.presentAlert, isTrue);
      expect(ios.presentBanner, isTrue);
      expect(ios.presentList, isTrue);
      // Значок на иконке не нужен: напоминания не копятся.
      expect(ios.presentBadge, isFalse);
      expect(ios.presentSound, isTrue);
      // Имя файла не задано — плагин подставит системный звук.
      expect(ios.sound, isNull);
    });

    test('выключенный звук делает уведомление iOS тихим', () async {
      await notifications.schedule(_short(_at(9, 25), playSound: false));

      final ios = platform.scheduled.single.details.iOS!;
      expect(ios.presentSound, isFalse);
      // Плагин ставит звук только при presentSound: уведомление молчит и в
      // фоне, и в переднем плане.
      expect(ios.sound, isNull);
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
      expect(notifications.onOpenRequested, isNull);
    });

    test('разрешения просит и отдаёт та же платформа', () async {
      platform.status = const ReminderStatus(
        exactAlarms: true,
        notificationsAllowed: false,
        exactAlarmsApplicable: false,
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
