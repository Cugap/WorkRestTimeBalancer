import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';
import 'package:work_rest_time_balancer/src/notifications/reminder_status.dart';
import 'package:work_rest_time_balancer/src/notifications/rest_notifications.dart';
import 'package:work_rest_time_balancer/src/persistence.dart';

import 'fake_clock.dart';
import 'fake_rest_notification_platform.dart';

/// Вернуться в приложение после системных настроек.
void resumeApp(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  testWidgets(
    'выданное разрешение на точные будильники переписывает раскладку',
    (tester) async {
      final clock = FakeClock(DateTime(2026, 3, 4, 9));
      final platform = FakeRestNotificationPlatform()
        ..status = const ReminderStatus(
          exactAlarms: false,
          notificationsAllowed: true,
        );
      final notifications = RestNotifications(platform: platform);
      final engine = WorkDayEngine(reminders: notifications);
      engine.startWorkDay(clock.now());

      await notifications.initialize();
      await tester.pumpWidget(
        WorkRestApp(
          session: WorkDaySession.inMemory(engine),
          clock: clock,
          notifications: notifications,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(await notifications.planPrecisionChanged(), isFalse);
      final cancelsBefore = platform.cancelAllCalls;

      // Человек выдал разрешение в системных настройках и вернулся.
      platform.status = const ReminderStatus(
        exactAlarms: true,
        notificationsAllowed: true,
      );
      resumeApp(tester);
      await tester.pump();
      await tester.pump();

      expect(platform.cancelAllCalls, greaterThan(cancelsBefore));
      expect(platform.scheduled, isNotEmpty);
      expect(await notifications.planPrecisionChanged(), isFalse);

      // Возврат без изменения разрешения раскладку не трогает.
      final stableWrites = platform.cancelAllCalls;
      resumeApp(tester);
      await tester.pump();
      await tester.pump();
      expect(platform.cancelAllCalls, stableWrites);
    },
  );
}
