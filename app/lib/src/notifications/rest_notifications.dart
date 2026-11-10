import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:work_rest_core/work_rest_core.dart';

import '../labels.dart';
import 'reminder_status.dart';
import 'rest_notification_platform.dart';

/// Payload напоминания: нажатие на любое напоминание открывает экран отдыха.
const String restReminderPayload = 'rest:offer';

/// Напоминания средствами платформы: адаптер порта ядра
/// [RestReminderPort] на `flutter_local_notifications`.
///
/// Ядро присылает раскладку целиком, поэтому адаптер только отменяет прежнюю
/// и планирует новую. Точность зависит от разрешения на точные будильники: без
/// него используется неточный режим, а состояние разрешений показывает экран
/// настроек.
final class RestNotifications
    implements RestReminderPort, ReminderStatusSource {
  RestNotifications({RestNotificationPlatform? platform})
    : _platform = platform ?? PluginRestNotificationPlatform();

  final RestNotificationPlatform _platform;

  /// Нажатие на напоминание: оболочка открывает экран отдыха.
  VoidCallback? onOpenRequested;

  /// Настройки iOS. Разрешения здесь не запрашиваются: их просит
  /// [requestPermissions], и только когда напоминания включены в настройках —
  /// иначе приложение спрашивало бы их у того, кто их выключил. Параметры
  /// показа по умолчанию включены, чтобы уведомление было видно и в переднем
  /// плане.
  static const DarwinInitializationSettings darwinSettings =
      DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      );

  /// Инициализация плагина: часовой пояс, настройки платформ и обработчик
  /// нажатия. Без инициализации планировать напоминания нельзя.
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    await _platform.initialize(
      darwin: darwinSettings,
      onOpen: () => onOpenRequested?.call(),
    );
  }

  /// Приложение запущено нажатием на напоминание: обработчик ответа для такого
  /// нажатия не вызывается, экран отдыха нужно открыть отдельно.
  Future<bool> launchedFromNotification() =>
      _guarded(_platform.launchedFromNotification, fallback: false);

  /// Попросить разрешения у системы: показывать уведомления, а на Android —
  /// ещё и точные будильники, если их нет.
  Future<ReminderStatus> requestPermissions() =>
      _guarded(_platform.requestPermissions, fallback: _unknownStatus);

  @override
  Future<ReminderStatus> read() =>
      _guarded(_platform.readStatus, fallback: _unknownStatus);

  @override
  Future<ReminderStatus> requestExactAlarms() =>
      _guarded(_platform.requestExactAlarms, fallback: _unknownStatus);

  @override
  Future<void> schedule(RestReminder reminder) => _ignoreFailures(
    () => _platform.schedule(
      id: _reminderId(reminder),
      title: 'Пора отдохнуть',
      body:
          '${restKindLabel(reminder.kind)} · '
          '${formatHoursMinutes(reminder.duration)}',
      at: reminder.at,
      details: detailsFor(reminder),
      payload: restReminderPayload,
    ),
  );

  @override
  Future<void> cancelAll() => _ignoreFailures(_platform.cancelAll);

  /// Детали уведомления. На iOS каналов нет, поэтому звук — это флаг
  /// [DarwinNotificationDetails.presentSound]: плагин не проставляет звук при
  /// `false`, и уведомление молчит и в фоне, и в переднем плане. Значок на
  /// иконке не нужен: напоминания не копятся.
  @visibleForTesting
  NotificationDetails detailsFor(RestReminder reminder) {
    final channel = restNotificationChannel(reminder.kind);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        // Напоминание должно быть видно и на заблокированном экране, а
        // полноэкранное намерение поднимает экран отдыха поверх замка
        // (спецификация: «уведомление с full-screen intent на Android»).
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        // Канал создан со звуком: «тихое» напоминание глушится на уровне
        // самого уведомления, иначе звук канала не отключить.
        playSound: reminder.playSound,
        enableVibration: reminder.playSound,
        silent: !reminder.playSound,
        autoCancel: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: false,
        presentSound: reminder.playSound,
      ),
    );
  }

  /// Идентификатор уведомления: минута дня и вид отдыха. Раскладка не выходит
  /// за текущий рабочий день, поэтому совпадений быть не может, а номер
  /// остаётся прежним при повторном планировании той же точки.
  int _reminderId(RestReminder reminder) =>
      (reminder.at.hour * 60 + reminder.at.minute) * 10 + reminder.kind.index;

  static const ReminderStatus _unknownStatus = ReminderStatus(
    exactAlarms: true,
    notificationsAllowed: true,
  );

  /// Платформенные ошибки не должны срывать ритм: напоминания — украшение, а
  /// не условие работы приложения.
  Future<T> _guarded<T>(
    Future<T> Function() body, {
    required T fallback,
  }) async {
    try {
      return await body();
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    } on UnimplementedError {
      return fallback;
    }
  }

  Future<void> _ignoreFailures(Future<void> Function() body) async {
    try {
      await body();
    } on PlatformException catch (error) {
      // Платформа не дала отменить или создать: следующая раскладка повторит.
      debugPrint('rest reminders: platform error: $error');
    } on MissingPluginException catch (error) {
      // Плагина нет на этой платформе.
      debugPrint('rest reminders: plugin missing: $error');
    } on UnimplementedError catch (error) {
      // Платформа не поддерживает операцию.
      debugPrint('rest reminders: not implemented: $error');
    }
  }
}
