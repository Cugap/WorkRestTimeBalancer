import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'src/clock.dart';
import 'src/desktop/desktop_shell.dart';
import 'src/file_picker_document_gateway.dart';
import 'src/notifications/reminder_status.dart';
import 'src/notifications/rest_notifications.dart';
import 'src/persistence.dart';
import 'src/preferences_document_store.dart';
import 'src/rest_screen.dart';
import 'src/window_activation.dart';
import 'src/work_day_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Напоминания инициализируются до восстановления сессии: первая же смена
  // состояния передаёт ядру готовый порт.
  final notifications = RestNotifications();
  await notifications.initialize();
  final session = await WorkDaySession.restore(
    SharedPreferencesDocumentStore(),
    reminders: notifications,
  );
  final clock = MonotonicClock();
  // Трей на Windows: окно можно свернуть, а ритм и напоминания продолжатся.
  final desktop = DesktopShell(engine: session.engine, clock: clock);
  await desktop.start();
  // Выход из меню трея: снять напоминания, сохранить день и завершить процесс.
  // При включённом трее это единственный способ закрыть приложение.
  desktop.onExitRequested = () async {
    await notifications.cancelAll();
    await session.save();
    await desktop.dispose();
    exit(0);
  };
  runApp(
    WorkRestApp(
      session: session,
      clock: clock,
      notifications: notifications,
      desktop: desktop,
    ),
  );
}

class WorkRestApp extends StatefulWidget {
  WorkRestApp({
    super.key,
    WorkDayEngine? engine,
    WorkDaySession? session,
    this.clock,
    this.fileGateway,
    this.notifications,
    this.reminderStatus,
    this.desktop,
    this.desktopPreferences,
    TrayMenuRefresher? trayMenu,
  }) : session = session ?? WorkDaySession.inMemory(engine),
       // Меню трея — это тот же объект, что и трей: если вывести его из
       // `desktop`, забыть про обновление меню при сборке приложения нельзя.
       trayMenu = trayMenu ?? desktop;

  final WorkDaySession session;
  final Clock? clock;

  /// Файловый порт экспорта и импорта; тесты подменяют его фейком.
  final DocumentFileGateway? fileGateway;

  /// Напоминания платформы; null — приложение работает без них (тесты,
  /// платформы без плагина).
  final RestNotifications? notifications;

  /// Состояние разрешений напоминаний для экрана настроек; по умолчанию — сам
  /// адаптер напоминаний.
  final ReminderStatusSource? reminderStatus;

  /// Трей и автозапуск на Windows; null — платформа без них (тесты, Android).
  final DesktopShell? desktop;

  /// Возможности Windows для экрана настроек; по умолчанию — сам трей. Тесты
  /// подменяют их фейком, не поднимая ни трей, ни реестр.
  final DesktopPreferences? desktopPreferences;

  /// Меню трея, которое пересобирается после каждой смены состояния дня:
  /// иначе пункт «Завершить рабочий день» остаётся с прежней подписью.
  final TrayMenuRefresher? trayMenu;

  @override
  State<WorkRestApp> createState() => _WorkRestAppState();
}

class _WorkRestAppState extends State<WorkRestApp> {
  final Clock _fallbackClock = MonotonicClock();
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  late final DocumentTransfer _transfer;
  bool _restScreenOpen = false;

  Clock get _clock => widget.clock ?? _fallbackClock;

  @override
  void initState() {
    super.initState();
    _transfer = DocumentTransfer(
      engine: widget.session.engine,
      gateway: widget.fileGateway ?? const FilePickerDocumentGateway(),
    );
    // Уход в фон — последняя точка, где состояние ещё можно записать, а
    // возврат — момент, когда время могло уйти вперёд.
    _lifecycle = AppLifecycleListener(
      onPause: _save,
      onHide: _save,
      onResume: _replanReminders,
    );

    final notifications = widget.notifications;
    if (notifications != null) {
      notifications.onOpenRequested = _openRestScreen;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askPermissions());
    }
    widget.desktop?.onOpenRequested = _openRestScreen;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.notifications?.onOpenRequested = null;
    widget.desktop?.onOpenRequested = null;
    super.dispose();
  }

  void _save() => unawaited(widget.session.save());

  /// Смена состояния: сохранить документ и пересобрать меню трея, чтобы оно
  /// показывало, что можно сделать сейчас.
  void _onStateChanged() {
    _save();
    final trayMenu = widget.trayMenu;
    if (trayMenu != null) {
      unawaited(trayMenu.refresh());
    }
  }

  /// Снимок догоняет время, прошедшее в фоне, и заодно перепланирует
  /// напоминания: пока приложение было свёрнуто, точки отдыха могли сдвинуться,
  /// а разрешение на точные будильники — появиться.
  void _replanReminders() {
    widget.session.engine.snapshot(_clock.now());
    unawaited(_replanIfPrecisionChanged());
  }

  /// Переписать раскладку, если разрешение на точные будильники изменилось:
  /// иначе настройки говорят «точные», а запланированные будильники остаются
  /// неточными до следующей смены состояния.
  Future<void> _replanIfPrecisionChanged() async {
    final notifications = widget.notifications;
    if (notifications == null) {
      return;
    }
    if (!await notifications.planPrecisionChanged()) {
      return;
    }
    widget.session.engine.replanReminders(_clock.now());
  }

  Future<void> _askPermissions() async {
    final notifications = widget.notifications;
    if (notifications == null) {
      return;
    }
    if (await notifications.launchedFromNotification()) {
      _openRestScreen();
    }
    final settings = widget.session.engine.snapshot(_clock.now()).settings;
    if (settings.notificationsEnabled) {
      await notifications.requestPermissions();
      // Разрешение могли выдать прямо сейчас, и записанная в первом кадре
      // раскладка тогда неточная — переписываем её в новом режиме.
      await _replanIfPrecisionChanged();
    }
  }

  /// Нажатие на напоминание открывает экран отдыха — предложения или идущего
  /// отдыха. Если показывать нечего (отдых уже пропущен), экран не открывается.
  void _openRestScreen() {
    final navigator = _navigator.currentState;
    if (navigator == null || _restScreenOpen) {
      return;
    }
    final snapshot = widget.session.engine.snapshot(_clock.now());
    if (snapshot.phase != WorkDayPhase.restOffered &&
        snapshot.phase != WorkDayPhase.resting) {
      return;
    }
    // Окно могло быть свёрнуто: тогда экран отдыха остался бы невидимым.
    activateAppWindow();
    _restScreenOpen = true;
    unawaited(
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => RestScreen(
                engine: widget.session.engine,
                clock: _clock,
                onStateChanged: _onStateChanged,
              ),
            ),
          )
          .whenComplete(() => _restScreenOpen = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkRestTimeBalancer',
      navigatorKey: _navigator,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: WorkDayScreen(
        engine: widget.session.engine,
        clock: _clock,
        transfer: _transfer,
        onStateChanged: _onStateChanged,
        reminderStatus: widget.reminderStatus ?? widget.notifications,
        desktop: widget.desktopPreferences ?? widget.desktop,
      ),
    );
  }
}
