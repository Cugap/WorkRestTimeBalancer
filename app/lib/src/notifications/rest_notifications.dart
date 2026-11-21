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
/// Ядро присылает раскладку целиком, поэтому адаптер заменяет прежнюю
/// планировку новой и снимает напоминание, на которое человек ответил.
/// Раскладка запоминает точность, с которой она фактически записана, чтобы её
/// можно было переписать, когда разрешение на точные будильники выдадут позже.
/// Без разрешения используется неточный режим, а состояние разрешений
/// показывает экран настроек.
final class RestNotifications
    implements RestReminderPort, ReminderStatusSource {
  RestNotifications({RestNotificationPlatform? platform})
    : _platform = platform ?? PluginRestNotificationPlatform();

  final RestNotificationPlatform _platform;

  /// Нажатие на напоминание: оболочка открывает экран отдыха.
  VoidCallback? onOpenRequested;

  /// Инициализация плагина: часовой пояс, настройки платформ и обработчик
  /// нажатия. Без инициализации планировать напоминания нельзя.
  ///
  /// Раскладка прошлого запуска снимается здесь же. Если приложение запущено
  /// напоминанием, показанное уведомление не трогается: оно ещё нужно
  /// человеку и исчезнет, когда он ответит на отдых. Номер этого уведомления
  /// запоминается: после догона предложение может получить другой номер, и
  /// ответ должен снять именно запустившее уведомление.
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    await _platform.initialize(onOpen: () => onOpenRequested?.call());
    final launchedId = await _guarded<int?>(
      _platform.launchedReminderId,
      fallback: null,
    );
    _launchedReminderId = launchedId;
    await _platform.clearPreviousRun(keepId: launchedId);
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

  /// Точность, с которой записана последняя раскладка: её возвращает платформа
  /// при фактической записи, а не отдельное чтение разрешения. Null — раскладки
  /// нет или она ещё не записана этим запуском.
  bool? _plannedExactAlarms;

  /// Текущее разрешение на точные будильники разошлось с той точностью, с
  /// которой записана раскладка. Значит, её нужно переписать в новом режиме.
  Future<bool> planPrecisionChanged() async {
    final planned = _plannedExactAlarms;
    if (planned == null) {
      return false;
    }
    return (await read()).exactAlarms != planned;
  }

  @override
  Future<ReminderStatus> requestExactAlarms() =>
      _guarded(_platform.requestExactAlarms, fallback: _unknownStatus);

  @override
  Future<void> schedule(RestReminder reminder) async {
    final exact = await _guarded<bool?>(
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
      fallback: null,
    );
    if (exact != null) {
      _plannedExactAlarms = exact;
    }
  }

  @override
  Future<void> cancelAll() async {
    // Новая раскладка ещё не записана: её точность станет известна из ответа
    // платформы на schedule.
    _plannedExactAlarms = null;
    await _ignoreFailures(_platform.cancelAll);
  }

  /// Снять напоминание, на которое человек ответил в приложении: платформа
  /// отменяет его по номеру, включая уже показанное уведомление. Если
  /// приложение было запущено напоминанием, снимается и оно — даже когда
  /// после догона у предложения оказался другой номер.
  @override
  Future<void> dismiss(RestReminder reminder) async {
    final offeredId = _reminderId(reminder);
    await _ignoreFailures(() => _platform.cancel(id: offeredId));
    final launchedId = _launchedReminderId;
    _launchedReminderId = null;
    if (launchedId != null && launchedId != offeredId) {
      await _ignoreFailures(() => _platform.cancel(id: launchedId));
    }
  }

  /// Номер уведомления, которым запустили приложение; null — обычный запуск.
  int? _launchedReminderId;

  /// Детали уведомления для Android и Windows. Звук задаётся отдельно на
  /// каждой платформе: на Android он глушится на уровне самого уведомления
  /// (канал создан со звуком), на Windows — элементом `<audio silent="true">`.
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
      windows: WindowsNotificationDetails(
        // Без звука toast молчит; со звуком остаётся звук по умолчанию.
        audio: reminder.playSound ? null : WindowsNotificationAudio.silent(),
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
