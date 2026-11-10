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

  @override
  Future<void> initialize({
    required DarwinInitializationSettings darwin,
    required VoidCallback onOpen,
  }) async {
    const windows = WindowsInitializationSettings(
      appName: 'WorkRestTimeBalancer',
      appUserModelId: 'Com.Cugap.WorkRestTimeBalancer',
      // Идентифицирует обработчик нажатия на Windows; менять нельзя.
      guid: 'd49b0314-ee7a-4626-bf79-97cdb8a991bb',
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('app_icon'),
        iOS: darwin,
        windows: windows,
      ),
      onDidReceiveNotificationResponse: (_) => onOpen(),
    );
    await _createAndroidChannels();
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

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required NotificationDetails details,
    required String payload,
  }) async {
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
