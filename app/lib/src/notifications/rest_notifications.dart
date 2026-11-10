import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:work_rest_core/work_rest_core.dart';

import '../labels.dart';
import 'reminder_status.dart';

/// Канал уведомлений одного вида отдыха. Каналы неизменяемы после создания,
/// поэтому их ровно три и они создаются при запуске, а не первым уведомлением.
final class _Channel {
  const _Channel(this.id, this.name, this.description);

  final String id;
  final String name;
  final String description;
}

const _shortChannel = _Channel(
  'rest_short',
  'Короткий отдых',
  'Напоминания о коротком отдыхе',
);
const _longChannel = _Channel(
  'rest_long',
  'Длинный отдых',
  'Напоминания о длинном отдыхе',
);
const _mealChannel = _Channel('rest_meal', 'Обед', 'Напоминания об обеде');

_Channel _channelFor(RestKind kind) => switch (kind) {
  RestKind.short => _shortChannel,
  RestKind.long => _longChannel,
  RestKind.meal => _mealChannel,
};

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
  RestNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Нажатие на напоминание: оболочка открывает экран отдыха.
  VoidCallback? onOpenRequested;

  /// Инициализация плагина: часовой пояс, каналы Android и обработчик
  /// нажатия. Без инициализации планировать напоминания нельзя.
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('app_icon');
    const darwin = DarwinInitializationSettings();
    const windows = WindowsInitializationSettings(
      appName: 'WorkRestTimeBalancer',
      appUserModelId: 'Com.Cugap.WorkRestTimeBalancer',
      // Идентифицирует обработчик нажатия на Windows; менять нельзя.
      guid: 'd49b0314-ee7a-4626-bf79-97cdb8a991bb',
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        windows: windows,
      ),
      onDidReceiveNotificationResponse: (_) => onOpenRequested?.call(),
    );
    await _createAndroidChannels();
  }

  /// Приложение запущено нажатием на напоминание: обработчик ответа для такого
  /// нажатия не вызывается, экран отдыха нужно открыть отдельно.
  Future<bool> launchedFromNotification() => _guarded(() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false;
  }, fallback: false);

  /// Попросить разрешения у системы: показывать уведомления и, если точные
  /// будильники недоступны, разрешение на точные напоминания.
  Future<ReminderStatus> requestPermissions() => _guarded(
    () async {
      final android = _android;
      if (android == null) {
        return await read();
      }
      await android.requestNotificationsPermission();
      if (!(await android.canScheduleExactNotifications() ?? false)) {
        await android.requestExactAlarmsPermission();
      }
      // На Android 14+ полноэкранное намерение требует отдельного согласия;
      // без него остаётся обычное heads-up напоминание.
      await android.requestFullScreenIntentPermission();
      return await read();
    },
    fallback: const ReminderStatus(
      exactAlarms: true,
      notificationsAllowed: true,
    ),
  );

  @override
  Future<ReminderStatus> read() => _guarded(
    () async {
      final android = _android;
      if (android == null) {
        // Вне Android разрешений на точные будильники нет: система планирует
        // уведомления сама.
        return const ReminderStatus(
          exactAlarms: true,
          notificationsAllowed: true,
        );
      }
      return ReminderStatus(
        exactAlarms: await android.canScheduleExactNotifications() ?? false,
        notificationsAllowed: await android.areNotificationsEnabled() ?? true,
      );
    },
    fallback: const ReminderStatus(
      exactAlarms: true,
      notificationsAllowed: true,
    ),
  );

  @override
  Future<ReminderStatus> requestExactAlarms() => _guarded(
    () async {
      await _android?.requestExactAlarmsPermission();
      return await read();
    },
    fallback: const ReminderStatus(
      exactAlarms: true,
      notificationsAllowed: true,
    ),
  );

  @override
  Future<void> schedule(RestReminder reminder) async {
    final channel = _channelFor(reminder.kind);
    final details = NotificationDetails(
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
        presentSound: reminder.playSound,
      ),
    );

    final mode = await _scheduleMode();
    try {
      await _plan(reminder, details, mode);
    } on PlatformException catch (error) {
      // Разрешение могли отозвать между проверкой и планированием: неточное
      // напоминание лучше пропущенного.
      debugPrint('rest reminders: exact schedule failed: $error');
      await _plan(reminder, details, AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  @override
  Future<void> cancelAll() async {
    // Отменяются только ещё не показанные напоминания: доставленное
    // напоминание должно остаться на экране, пока человек на него не
    // отреагирует. Иначе пробуждение приложения в момент срабатывания сразу
    // снимало бы только что показанное уведомление.
    try {
      await _plugin.cancelAllPendingNotifications();
    } on MissingPluginException {
      // Windows-реализация не умеет отменять только запланированные.
      await _ignoreFailures(() => _plugin.cancelAll());
    } on PlatformException {
      await _ignoreFailures(() => _plugin.cancelAll());
    } on UnimplementedError {
      await _ignoreFailures(() => _plugin.cancelAll());
    }
  }

  Future<void> _plan(
    RestReminder reminder,
    NotificationDetails details,
    AndroidScheduleMode mode,
  ) => _plugin.zonedSchedule(
    id: _reminderId(reminder),
    title: 'Пора отдохнуть',
    body:
        '${restKindLabel(reminder.kind)} · '
        '${formatHoursMinutes(reminder.duration)}',
    scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
    notificationDetails: details,
    androidScheduleMode: mode,
    payload: restReminderPayload,
  );

  /// Идентификатор уведомления: минута дня и вид отдыха. Раскладка не выходит
  /// за текущий рабочий день, поэтому совпадений быть не может, а номер
  /// остаётся прежним при повторном планировании той же точки.
  int _reminderId(RestReminder reminder) =>
      (reminder.at.hour * 60 + reminder.at.minute) * 10 + reminder.kind.index;

  Future<AndroidScheduleMode> _scheduleMode() => _guarded(() async {
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }, fallback: AndroidScheduleMode.inexactAllowWhileIdle);

  Future<void> _createAndroidChannels() => _ignoreFailures(() async {
    final android = _android;
    if (android == null) {
      return;
    }
    for (final channel in const [_shortChannel, _longChannel, _mealChannel]) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          channel.id,
          channel.name,
          description: channel.description,
          importance: Importance.high,
          playSound: true,
        ),
      );
    }
  });

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      defaultTargetPlatform == TargetPlatform.android
      ? _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
      : null;

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
