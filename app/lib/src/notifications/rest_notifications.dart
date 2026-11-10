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

/// Заголовок напоминания: одинаков для всех видов отдыха.
const String restReminderTitle = 'Пора отдохнуть';

/// Напоминание, переведённое в термины плагина: идентификатор, текст и
/// платформенные детали. Отделено от адаптера, чтобы звук и раскладку можно
/// было проверить тестами без настоящей платформы.
@immutable
final class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.details,
  });

  final int id;
  final String title;
  final String body;
  final NotificationDetails details;

  /// Идентификатор уведомления: минута дня и вид отдыха. Раскладка не выходит
  /// за текущий рабочий день, поэтому совпадений быть не может, а номер
  /// остаётся прежним при повторном планировании той же точки.
  static int idFor(RestReminder reminder) =>
      (reminder.at.hour * 60 + reminder.at.minute) * 10 + reminder.kind.index;
}

/// Перевести напоминание ядра в детали плагина.
///
/// На Windows звук задаётся элементом `<audio silent="true">`: без него toast
/// всегда звучит, а настройка звука должна действовать на всех платформах.
PlannedNotification planNotification(RestReminder reminder) {
  final channel = _channelFor(reminder.kind);
  return PlannedNotification(
    id: PlannedNotification.idFor(reminder),
    title: restReminderTitle,
    body:
        '${restKindLabel(reminder.kind)} · '
        '${formatHoursMinutes(reminder.duration)}',
    details: NotificationDetails(
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
      windows: WindowsNotificationDetails(
        // Без звука toast молчит; со звуком остаётся звук по умолчанию.
        audio: reminder.playSound ? null : WindowsNotificationAudio.silent(),
      ),
    ),
  );
}

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

  /// Плагин инициализирован и готов планировать. На Windows `initialize`
  /// возвращает `false`, если не удалось зарегистрировать AUMID: без этого
  /// планирование бросает `StateError`, а приложение должно работать без
  /// напоминаний.
  bool _ready = false;

  /// Нажатие на напоминание: оболочка открывает экран отдыха.
  VoidCallback? onOpenRequested;

  /// Запланированные этим запуском напоминания: идентификатор и срок. Нужны,
  /// чтобы на Windows отменять по одному и не снимать toast, который вот-вот
  /// покажется.
  final Map<int, DateTime> _scheduled = <int, DateTime>{};

  /// Напоминание с таким запасом до срока считается показывающимся: Windows
  /// доставляет запланированный toast в свою секунду, а раскладка пустеет в
  /// момент предложения отдыха.
  static const Duration _dueWindow = Duration(seconds: 1);

  /// Инициализация плагина: часовой пояс, каналы Android и обработчик
  /// нажатия. Без инициализации планировать напоминания нельзя.
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('app_icon');
    const darwin = DarwinInitializationSettings();
    const windows = WindowsInitializationSettings(
      appName: 'WorkRestTimeBalancer',
      // AUMID — учётное имя приложения в центре уведомлений Windows. На время
      // разработки плагин регистрирует его в HKCU, MSIX-идентичность для
      // показа toast не нужна (см. комментарий в тикете 12).
      appUserModelId: 'Com.Cugap.WorkRestTimeBalancer',
      // Идентифицирует обработчик нажатия на Windows; менять нельзя.
      guid: 'd49b0314-ee7a-4626-bf79-97cdb8a991bb',
    );
    _ready =
        await _guarded(
          () => _plugin.initialize(
            settings: const InitializationSettings(
              android: android,
              iOS: darwin,
              windows: windows,
            ),
            onDidReceiveNotificationResponse: (_) => onOpenRequested?.call(),
          ),
          fallback: false,
        ) ??
        false;
    if (!_ready) {
      debugPrint('rest reminders: platform did not initialize');
      return;
    }
    // Напоминания прошлого запуска переживают перезапуск (Android и Windows):
    // снимаем их до того, как ядро пришлёт актуальную раскладку.
    await _ignoreFailures(_plugin.cancelAll);
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
    if (!_ready) {
      return;
    }
    // Точка отдыха могла наступить между расчётом раскладки и записью в порт:
    // плагин не планирует в прошлое, а прошедшее напоминание уже не нужно.
    if (!reminder.at.isAfter(DateTime.now())) {
      return;
    }
    final planned = planNotification(reminder);
    final mode = await _scheduleMode();
    try {
      await _plan(planned, reminder.at, mode);
      _scheduled[planned.id] = reminder.at;
    } on PlatformException catch (error) {
      // Разрешение могли отозвать между проверкой и планированием: неточное
      // напоминание лучше пропущенного.
      debugPrint('rest reminders: exact schedule failed: $error');
      await _plan(
        planned,
        reminder.at,
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
      _scheduled[planned.id] = reminder.at;
    } on ArgumentError catch (error) {
      debugPrint('rest reminders: schedule rejected: $error');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) {
      return;
    }
    final scheduled = Map<int, DateTime>.of(_scheduled);
    _scheduled.clear();
    await _ignoreFailures(() async {
      if (defaultTargetPlatform != TargetPlatform.windows) {
        // На Android и iOS отменяет и запланированные, и уже показанные
        // напоминания.
        await _plugin.cancelAll();
        return;
      }
      // На Windows раскладка пустеет в тот же миг, когда отдых предлагается,
      // то есть ровно тогда, когда toast должен показаться. `cancelAll`
      // успевал снять его из расписания до доставки, и напоминание не видел
      // никто. Поэтому toast с наступившим сроком не отменяется: система
      // покажет его и оставит в центре уведомлений.
      final now = DateTime.now();
      for (final entry in scheduled.entries) {
        if (!entry.value.isAfter(now.add(_dueWindow))) {
          continue;
        }
        await _plugin.cancel(id: entry.key);
      }
    });
  }

  Future<void> _plan(
    PlannedNotification notification,
    DateTime at,
    AndroidScheduleMode mode,
  ) => _plugin.zonedSchedule(
    id: notification.id,
    title: notification.title,
    body: notification.body,
    scheduledDate: tz.TZDateTime.from(at, tz.local),
    notificationDetails: notification.details,
    androidScheduleMode: mode,
    payload: restReminderPayload,
  );

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
