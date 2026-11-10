import 'dart:async';

import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'src/clock.dart';
import 'src/notifications/reminder_status.dart';
import 'src/notifications/rest_notifications.dart';
import 'src/persistence.dart';
import 'src/preferences_document_store.dart';
import 'src/rest_screen.dart';
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
  runApp(
    WorkRestApp(
      session: session,
      clock: MonotonicClock(),
      notifications: notifications,
    ),
  );
}

class WorkRestApp extends StatefulWidget {
  WorkRestApp({
    super.key,
    WorkDayEngine? engine,
    WorkDaySession? session,
    this.clock,
    this.notifications,
    this.reminderStatus,
  }) : session = session ?? WorkDaySession.inMemory(engine);

  final WorkDaySession session;
  final Clock? clock;

  /// Напоминания платформы; null — приложение работает без них (тесты,
  /// платформы без плагина).
  final RestNotifications? notifications;

  /// Состояние разрешений напоминаний для экрана настроек; по умолчанию — сам
  /// адаптер напоминаний.
  final ReminderStatusSource? reminderStatus;

  @override
  State<WorkRestApp> createState() => _WorkRestAppState();
}

class _WorkRestAppState extends State<WorkRestApp> {
  final Clock _fallbackClock = MonotonicClock();
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  bool _restScreenOpen = false;

  Clock get _clock => widget.clock ?? _fallbackClock;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.notifications?.onOpenRequested = null;
    super.dispose();
  }

  void _save() => unawaited(widget.session.save());

  /// Снимок догоняет время, прошедшее в фоне, и заодно перепланирует
  /// напоминания: пока приложение было свёрнуто, точки отдыха могли сдвинуться.
  void _replanReminders() {
    widget.session.engine.snapshot(_clock.now());
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
    _restScreenOpen = true;
    unawaited(
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => RestScreen(
                engine: widget.session.engine,
                clock: _clock,
                onStateChanged: _save,
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
        onStateChanged: _save,
        reminderStatus: widget.reminderStatus ?? widget.notifications,
      ),
    );
  }
}
