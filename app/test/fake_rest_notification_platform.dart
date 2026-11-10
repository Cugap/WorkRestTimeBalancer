import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:work_rest_time_balancer/src/notifications/reminder_status.dart';
import 'package:work_rest_time_balancer/src/notifications/rest_notification_platform.dart';

/// Уведомление, дошедшее до платформы: то, что плагин запланировал бы в
/// системе. Тесты проверяют именно его, потому что на машине без iOS и
/// Android системного планировщика нет.
final class SentNotification {
  const SentNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.details,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime at;
  final NotificationDetails details;
  final String payload;
}

/// Платформа напоминаний, которая запоминает вызовы вместо системных
/// уведомлений. Нажатие и холодный запуск моделируются вручную.
final class FakeRestNotificationPlatform implements RestNotificationPlatform {
  DarwinInitializationSettings? darwin;
  VoidCallback? onOpen;
  bool launched = false;
  ReminderStatus status = const ReminderStatus(
    exactAlarms: true,
    notificationsAllowed: true,
  );
  int permissionRequests = 0;
  int exactAlarmRequests = 0;
  int cancelAllCalls = 0;
  final List<SentNotification> scheduled = <SentNotification>[];
  Object? scheduleFailure;
  Object? statusFailure;

  /// Нажатие на уведомление так, как его вызывает система.
  void tap() => onOpen?.call();

  @override
  Future<void> initialize({
    required DarwinInitializationSettings darwin,
    required VoidCallback onOpen,
  }) async {
    this.darwin = darwin;
    this.onOpen = onOpen;
  }

  @override
  Future<bool> launchedFromNotification() async => launched;

  @override
  Future<ReminderStatus> readStatus() async {
    final failure = statusFailure;
    if (failure != null) {
      throw failure;
    }
    return status;
  }

  @override
  Future<ReminderStatus> requestPermissions() async {
    permissionRequests++;
    return readStatus();
  }

  @override
  Future<ReminderStatus> requestExactAlarms() async {
    exactAlarmRequests++;
    return readStatus();
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required NotificationDetails details,
    required String payload,
  }) async {
    final failure = scheduleFailure;
    if (failure != null) {
      throw failure;
    }
    scheduled.add(
      SentNotification(
        id: id,
        title: title,
        body: body,
        at: at,
        details: details,
        payload: payload,
      ),
    );
  }
}
