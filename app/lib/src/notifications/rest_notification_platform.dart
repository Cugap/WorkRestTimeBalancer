import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:work_rest_core/work_rest_core.dart';

import 'reminder_status.dart';

/// Канал уведомлений одного вида отдыха. Каналы неизменяемы после создания,
/// поэтому их ровно три и они создаются при запуске, а не первым уведомлением.
/// На iOS каналов нет: там вид отдыха живёт только в тексте уведомления.
final class RestNotificationChannel {
  const RestNotificationChannel(this.id, this.name, this.description);

  final String id;
  final String name;
  final String description;
}

const shortRestChannel = RestNotificationChannel(
  'rest_short',
  'Короткий отдых',
  'Напоминания о коротком отдыхе',
);
const longRestChannel = RestNotificationChannel(
  'rest_long',
  'Длинный отдых',
  'Напоминания о длинном отдыхе',
);
const mealRestChannel = RestNotificationChannel(
  'rest_meal',
  'Обед',
  'Напоминания об обеде',
);

RestNotificationChannel restNotificationChannel(RestKind kind) =>
    switch (kind) {
      RestKind.short => shortRestChannel,
      RestKind.long => longRestChannel,
      RestKind.meal => mealRestChannel,
    };

/// Платформенные операции, которые нужны напоминаниям: инициализация плагина,
/// планирование и отмена, разрешения, нажатие на уведомление.
///
/// Отдельный шов: на iOS и Android разрешения и нажатия устроены по-разному, а
/// на машине без устройства проверить их можно только подменой платформы.
abstract interface class RestNotificationPlatform {
  /// Инициализировать плагин с настройками Darwin и обработчиком нажатия.
  Future<void> initialize({
    required DarwinInitializationSettings darwin,
    required VoidCallback onOpen,
  });

  /// Приложение запущено нажатием на уведомление: обработчик такого нажатия
  /// не вызывается, экран отдыха открывается отдельно.
  Future<bool> launchedFromNotification();

  Future<ReminderStatus> readStatus();

  Future<ReminderStatus> requestPermissions();

  Future<ReminderStatus> requestExactAlarms();

  Future<void> cancelAll();

  /// Запланировать одно напоминание. На Android режим точности выбирается
  /// здесь же: без разрешения на точные будильники напоминание планируется
  /// неточным.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required NotificationDetails details,
    required String payload,
  });
}

/// Настоящая платформа: `flutter_local_notifications`.
final class PluginRestNotificationPlatform implements RestNotificationPlatform {
  PluginRestNotificationPlatform({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Плагин инициализирован и готов планировать. На Windows `initialize`
  /// возвращает `false`, если не удалось зарегистрировать AUMID: без этого
  /// планирование бросает `StateError`, а приложение должно работать без
  /// напоминаний.
  bool _ready = false;

  /// Запланированные этим запуском напоминания: идентификатор и срок. Нужны,
  /// чтобы на Windows отменять по одному и не снимать toast, который вот-вот
  /// покажется.
  final Map<int, DateTime> _scheduled = <int, DateTime>{};

  /// Напоминание с таким запасом до срока считается показывающимся: Windows
  /// доставляет запланированный toast в свою секунду, а раскладка пустеет в
  /// момент предложения отдыха.
  static const Duration _dueWindow = Duration(seconds: 1);

  @override
  Future<void> initialize({
    required DarwinInitializationSettings darwin,
    required VoidCallback onOpen,
  }) async {
    const windows = WindowsInitializationSettings(
      appName: 'WorkRestTimeBalancer',
      // AUMID — учётное имя приложения в центре уведомлений Windows. Плагин
      // регистрирует его в HKCU; для показа toast MSIX-идентичность не нужна,
      // но запланированный toast без ярлыка в меню «Пуск» система теряет —
      // ярлык создаёт раннер (app/windows/runner/notification_shortcut.cpp).
      appUserModelId: 'Com.Cugap.WorkRestTimeBalancer',
      // Идентифицирует обработчик нажатия на Windows; менять нельзя.
      guid: 'd49b0314-ee7a-4626-bf79-97cdb8a991bb',
    );
    _ready =
        await _initializePlugin(
          InitializationSettings(
            android: const AndroidInitializationSettings('app_icon'),
            iOS: darwin,
            windows: windows,
          ),
          onOpen,
        ) ??
        false;
    if (!_ready) {
      debugPrint('rest reminders: platform did not initialize');
      return;
    }
    // Напоминания прошлого запуска переживают перезапуск (Android и Windows):
    // снимаем их до того, как ядро пришлёт актуальную раскладку.
    await _cancelEverything();
    await _createAndroidChannels();
  }

  Future<bool?> _initializePlugin(
    InitializationSettings settings,
    VoidCallback onOpen,
  ) async {
    try {
      return await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (_) => onOpen(),
      );
    } on PlatformException catch (error) {
      debugPrint('rest reminders: initialize failed: $error');
      return false;
    } on MissingPluginException catch (error) {
      debugPrint('rest reminders: plugin missing: $error');
      return false;
    } on UnimplementedError catch (error) {
      debugPrint('rest reminders: not implemented: $error');
      return false;
    }
  }

  /// Снять всё, включая уже показанные напоминания: используется при запуске,
  /// чтобы не унаследовать расписание прошлого запуска.
  Future<void> _cancelEverything() async {
    try {
      await _plugin.cancelAll();
    } on PlatformException catch (error) {
      debugPrint('rest reminders: platform error: $error');
    } on MissingPluginException catch (error) {
      debugPrint('rest reminders: plugin missing: $error');
    } on UnimplementedError catch (error) {
      debugPrint('rest reminders: not implemented: $error');
    }
  }

  @override
  Future<bool> launchedFromNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false;
  }

  @override
  Future<ReminderStatus> readStatus() async {
    final android = _android;
    if (android != null) {
      return ReminderStatus(
        exactAlarms: await android.canScheduleExactNotifications() ?? false,
        notificationsAllowed: await android.areNotificationsEnabled() ?? true,
      );
    }
    final ios = _ios;
    if (ios != null) {
      // На iOS точных будильников нет: локальное уведомление доставляет
      // система, точность зависит только от разрешения на уведомления.
      final options = await ios.checkPermissions();
      return ReminderStatus(
        exactAlarms: true,
        notificationsAllowed: options?.isEnabled ?? true,
        exactAlarmsApplicable: false,
      );
    }
    return const ReminderStatus(exactAlarms: true, notificationsAllowed: true);
  }

  @override
  Future<ReminderStatus> requestPermissions() async {
    final android = _android;
    if (android != null) {
      await android.requestNotificationsPermission();
      if (!(await android.canScheduleExactNotifications() ?? false)) {
        await android.requestExactAlarmsPermission();
      }
      // На Android 14+ полноэкранное намерение требует отдельного согласия;
      // без него остаётся обычное heads-up напоминание.
      await android.requestFullScreenIntentPermission();
      return readStatus();
    }
    final ios = _ios;
    if (ios != null) {
      // Звук запрашивается вместе с показом: без разрешения на звук
      // отключённый в приложении звук был бы неотличим от разрешённого.
      await ios.requestPermissions(alert: true, sound: true);
      return readStatus();
    }
    return readStatus();
  }

  @override
  Future<ReminderStatus> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
    return readStatus();
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) {
      return;
    }
    final scheduled = Map<int, DateTime>.of(_scheduled);
    _scheduled.clear();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _cancelWindows(scheduled);
      return;
    }
    // Отменяются только ещё не показанные напоминания: доставленное
    // напоминание должно остаться на экране, пока человек на него не
    // отреагирует. Иначе пробуждение приложения в момент срабатывания сразу
    // снимало бы только что показанное уведомление.
    try {
      await _plugin.cancelAllPendingNotifications();
    } on MissingPluginException {
      // Не все платформы умеют отменять только запланированные.
      await _plugin.cancelAll();
    } on PlatformException {
      await _plugin.cancelAll();
    } on UnimplementedError {
      await _plugin.cancelAll();
    }
  }

  /// Windows: отменить свои напоминания по одному.
  ///
  /// `cancelAll` на Windows снимает и запланированные, и уже доставленные
  /// toast'ы, а раскладка пустеет в тот же миг, когда отдых предлагается, то
  /// есть ровно в момент доставки. Общий `cancelAll` успевал снять toast из
  /// расписания до того, как система его покажет, и напоминание не видел никто.
  /// Поэтому toast с наступившим сроком не отменяется: система покажет его и
  /// оставит в центре уведомлений.
  Future<void> _cancelWindows(Map<int, DateTime> scheduled) async {
    final now = DateTime.now();
    try {
      for (final entry in scheduled.entries) {
        if (!entry.value.isAfter(now.add(_dueWindow))) {
          continue;
        }
        await _plugin.cancel(id: entry.key);
      }
    } on PlatformException catch (error) {
      debugPrint('rest reminders: platform error: $error');
    } on MissingPluginException catch (error) {
      debugPrint('rest reminders: plugin missing: $error');
    } on UnimplementedError catch (error) {
      debugPrint('rest reminders: not implemented: $error');
    }
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
    if (!_ready) {
      return;
    }
    // Точка отдыха могла наступить между расчётом раскладки и записью в порт:
    // плагин не планирует в прошлое, а прошедшее напоминание уже не нужно.
    if (!at.isAfter(DateTime.now())) {
      return;
    }
    final mode = await _scheduleMode();
    try {
      await _plan(
        id: id,
        title: title,
        body: body,
        at: at,
        details: details,
        payload: payload,
        mode: mode,
      );
      _scheduled[id] = at;
    } on PlatformException catch (error) {
      // Разрешение могли отозвать между проверкой и планированием: неточное
      // напоминание лучше пропущенного.
      debugPrint('rest reminders: exact schedule failed: $error');
      await _plan(
        id: id,
        title: title,
        body: body,
        at: at,
        details: details,
        payload: payload,
        mode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      _scheduled[id] = at;
    } on ArgumentError catch (error) {
      debugPrint('rest reminders: schedule rejected: $error');
    }
  }

  Future<void> _plan({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required NotificationDetails details,
    required String payload,
    required AndroidScheduleMode mode,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    // `TZDateTime.from` сохраняет момент времени: время срабатывания не
    // зависит от того, совпадает ли `tz.local` с часовым поясом устройства.
    scheduledDate: tz.TZDateTime.from(at, tz.local),
    notificationDetails: details,
    androidScheduleMode: mode,
    payload: payload,
  );

  Future<AndroidScheduleMode> _scheduleMode() async {
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<void> _createAndroidChannels() async {
    final android = _android;
    if (android == null) {
      return;
    }
    for (final channel in const [
      shortRestChannel,
      longRestChannel,
      mealRestChannel,
    ]) {
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
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      defaultTargetPlatform == TargetPlatform.android
      ? _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
      : null;

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
      : null;
}
