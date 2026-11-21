import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';
import 'package:work_rest_time_balancer/src/notifications/rest_notifications.dart';
import 'package:work_rest_time_balancer/src/persistence.dart';
import 'package:work_rest_time_balancer/src/rest_screen.dart';

import 'fake_clock.dart';
import 'fake_rest_notification_platform.dart';

void main() {
  late FakeClock clock;
  late WorkDayEngine engine;
  late FakeRestNotificationPlatform platform;
  late RestNotifications notifications;

  setUp(() {
    clock = FakeClock(DateTime(2026, 3, 4, 9));
    platform = FakeRestNotificationPlatform();
    notifications = RestNotifications(platform: platform);
    // Как в main: ядро получает тот же порт напоминаний, что и оболочка,
    // иначе раскладка никуда не планируется и тест проверял бы пустоту.
    engine = WorkDayEngine(reminders: notifications);
  });

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> pumpApp(WidgetTester tester) async {
    await notifications.initialize();
    await tester.pumpWidget(
      WorkRestApp(
        session: WorkDaySession.inMemory(engine),
        clock: clock,
        notifications: notifications,
      ),
    );
    // После первого кадра оболочка читает разрешения и холодный запуск.
    await tester.pump();
    await tester.pump();
  }

  /// Начать день и дождаться предложения отдыха без единого фонового тика:
  /// ровно так выглядит возврат в приложение, которое было свёрнуто.
  void offerRestWithoutTicks() {
    engine.startWorkDay(clock.now());
    clock.advance(const Duration(minutes: 25));
    expect(engine.snapshot(clock.now()).phase, WorkDayPhase.restOffered);
  }

  testWidgets('нажатие на уведомление открывает экран отдыха', (tester) async {
    offerRestWithoutTicks();
    await pumpApp(tester);

    expect(find.byType(RestScreen), findsNothing);

    platform.tap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RestScreen), findsOneWidget);
    expect(key('rest-command-startRest'), findsOneWidget);
  });

  testWidgets('запуск нажатием на уведомление сразу открывает отдых', (
    tester,
  ) async {
    // Холодный запуск: система отдаёт нажатие через launch details, а не через
    // обработчик ответа.
    platform.launched = true;
    offerRestWithoutTicks();

    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RestScreen), findsOneWidget);
    // Разрешения спрашиваются после открытия экрана и только при включённых
    // напоминаниях.
    expect(platform.permissionRequests, 1);
  });

  testWidgets('нажатие без предложенного отдыха не открывает экран', (
    tester,
  ) async {
    // Свёрнутое приложение не могло перепланировать уведомление, а отдых уже
    // пропущен: нажатие не должно показывать неверный экран.
    engine.startWorkDay(clock.now());
    await pumpApp(tester);

    platform.tap();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RestScreen), findsNothing);
  });

  testWidgets('ответ на отдых в приложении снимает показанное напоминание', (
    tester,
  ) async {
    // Движок создаётся внутри тела теста: цепочка записей раскладки заводится
    // в той же зоне, что и поддельные часы теста.
    engine = WorkDayEngine(reminders: notifications);
    await pumpApp(tester);
    await tester.tap(key('command-start'));
    await tester.pump();
    final offered = platform.scheduled.firstWhere(
      (notification) => notification.at == DateTime(2026, 3, 4, 9, 25),
    );

    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('phase-restOffered')), findsOneWidget);

    await tester.tap(key('command-startRest'));
    await tester.pump();

    // Уведомление о предложении уже показано; нажатие «Начать отдых» в
    // приложении должно снять его, иначе оно остаётся в шторке устаревшим.
    expect(platform.cancelled, contains(offered.id));
  });

  testWidgets('выключенные напоминания не просят разрешений', (tester) async {
    final now = clock.now();
    engine.updateSettings(
      now,
      engine.snapshot(now).settings.copyWith(notificationsEnabled: false),
    );

    await pumpApp(tester);

    expect(platform.permissionRequests, 0);
  });
}
