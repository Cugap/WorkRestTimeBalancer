import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';
import 'package:work_rest_time_balancer/src/notifications/reminder_status.dart';
import 'package:work_rest_time_balancer/src/settings_screen.dart';

import 'fake_clock.dart';

void main() {
  late FakeClock clock;
  late WorkDayEngine engine;

  setUp(() {
    clock = FakeClock(DateTime(2026, 3, 4, 9));
    engine = WorkDayEngine();
  });

  Finder key(String value) => find.byKey(ValueKey(value));
  Finder field(String name) => key('settings-$name');
  Finder error(String name) => key('settings-error-$name');

  String fieldText(WidgetTester tester, String name) =>
      tester.widget<TextField>(field(name)).controller!.text;

  RhythmSettings settings() => engine.snapshot(clock.now()).settings;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(WorkRestApp(engine: engine, clock: clock));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    // Завершаем анимацию перехода и даём тику экрана обновить снимок.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openSettings(WidgetTester tester) =>
      tap(tester, key('open-settings-screen'));

  Future<void> enter(WidgetTester tester, String name, String text) async {
    await tester.enterText(field(name), text);
    await tester.pump();
  }

  testWidgets('недопустимые настройки в ядре объяснены и исправимы', (
    tester,
  ) async {
    // Так выглядит приложение, в которое попал файл с настройками вне
    // диапазонов: сохранение формы отклоняется, пока значение не исправлено.
    engine = WorkDayEngine(
      settings: RhythmSettings.defaults.copyWith(
        shortRestInterval: const Duration(minutes: 10),
      ),
    );
    await pumpApp(tester);
    await openSettings(tester);

    expect(key('settings-current-invalid'), findsOneWidget);
    expect(find.textContaining('от 20 до 30 минут'), findsOneWidget);

    await enter(tester, 'short-rest-interval', '25');
    await tap(tester, key('settings-save'));

    expect(settings().shortRestInterval, const Duration(minutes: 25));
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('экран настроек открывается из главного и показывает ядро', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(fieldText(tester, 'work-start'), '09:00');
    expect(fieldText(tester, 'work-end'), '18:00');
    expect(fieldText(tester, 'short-rest-interval'), '25');
    // Длительность короткого отдыха вводится в секундах: 3 минуты = 180.
    expect(fieldText(tester, 'short-rest-duration'), '180');
    expect(fieldText(tester, 'long-rest-interval'), '90');
    expect(fieldText(tester, 'long-rest-duration'), '10');
    expect(fieldText(tester, 'meal-start'), '13:00');
    expect(fieldText(tester, 'meal-duration'), '60');
  });

  testWidgets('у полей настроек видны единицы измерения', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    // Минуты и секунды подписаны прямо в поле: иначе 20 и 300 не отличить от
    // минут.
    expect(find.text('Короткий отдых, интервал, мин'), findsOneWidget);
    expect(find.text('Короткий отдых, длительность, с'), findsOneWidget);
    expect(find.text('Длинный отдых, интервал, мин'), findsOneWidget);
    expect(find.text('Длинный отдых, длительность, мин'), findsOneWidget);
    expect(find.text('Обед, длительность, мин'), findsOneWidget);
    // Значение по умолчанию — 3 минуты — показано в секундах.
    expect(fieldText(tester, 'short-rest-duration'), '180');
    expect(fieldText(tester, 'short-rest-interval'), '25');
  });

  testWidgets('сохранение отправляет новые значения в ядро', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);

    await enter(tester, 'work-end', '20:00');
    await enter(tester, 'short-rest-interval', '30');
    await enter(tester, 'short-rest-duration', '240');
    await enter(tester, 'long-rest-interval', '120');
    await enter(tester, 'long-rest-duration', '15');
    await enter(tester, 'meal-start', '14:00');
    await enter(tester, 'meal-duration', '45');
    await tap(tester, key('settings-save'));

    expect(
      settings(),
      const RhythmSettings(
        workStart: ClockTime(9, 0),
        workEnd: ClockTime(20, 0),
        shortRestInterval: Duration(minutes: 30),
        shortRestDuration: Duration(minutes: 4),
        longRestInterval: Duration(minutes: 120),
        longRestDuration: Duration(minutes: 15),
        mealStart: ClockTime(14, 0),
        mealDuration: Duration(minutes: 45),
      ),
    );
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('недопустимое значение показывает ошибку и не меняет ядро', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);

    await enter(tester, 'short-rest-interval', '10');
    await tap(tester, key('settings-save'));

    expect(error('short-rest-interval'), findsOneWidget);
    expect(field('short-rest-interval'), findsOneWidget);
    expect(settings(), RhythmSettings.defaults);
  });

  testWidgets('неразбираемое значение показывает ошибку формата', (
    tester,
  ) async {
    await pumpApp(tester);
    await openSettings(tester);

    await enter(tester, 'short-rest-interval', 'abc');
    await tap(tester, key('settings-save'));

    expect(error('short-rest-interval'), findsOneWidget);
    expect(settings(), RhythmSettings.defaults);
  });

  testWidgets('кнопка по умолчанию возвращает настройки ядра к исходным', (
    tester,
  ) async {
    engine = WorkDayEngine(
      settings: const RhythmSettings(
        shortRestInterval: Duration(minutes: 30),
        shortRestDuration: Duration(minutes: 5),
      ),
    );
    await pumpApp(tester);
    await openSettings(tester);

    expect(fieldText(tester, 'short-rest-interval'), '30');

    await tap(tester, key('settings-defaults'));

    expect(settings(), RhythmSettings.defaults);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('изменение настроек во время отдыха не обрывает отдых', (
    tester,
  ) async {
    await pumpApp(tester);
    await tap(tester, key('command-start'));
    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, key('command-startRest'));

    expect(engine.snapshot(clock.now()).phase, WorkDayPhase.resting);

    await openSettings(tester);
    await enter(tester, 'short-rest-duration', '300');
    await enter(tester, 'short-rest-interval', '30');
    await tap(tester, key('settings-save'));

    final snapshot = engine.snapshot(clock.now());
    expect(snapshot.phase, WorkDayPhase.resting);
    expect(snapshot.restDuration, const Duration(minutes: 3));
    expect(snapshot.remainingRest, const Duration(minutes: 3));
    expect(snapshot.settings.shortRestDuration, const Duration(minutes: 5));
  });

  testWidgets('переключатели напоминаний действуют сразу', (tester) async {
    final reminders = RecordingReminders();
    engine = WorkDayEngine(reminders: reminders);
    engine.startWorkDay(clock.now());
    await tester.pump();
    expect(reminders.planned, isNotEmpty);

    await pumpApp(tester);
    await openSettings(tester);

    await tap(tester, key('settings-notifications'));
    expect(settings().notificationsEnabled, isFalse);
    await tester.pump();
    expect(reminders.planned, isEmpty);

    await tap(tester, key('settings-notifications'));
    expect(settings().notificationsEnabled, isTrue);
    await tester.pump();
    expect(reminders.planned, isNotEmpty);

    await tap(tester, key('settings-sound'));
    expect(settings().soundEnabled, isFalse);
    await tester.pump();
    expect(reminders.planned.every((r) => !r.playSound), isTrue);
  });

  testWidgets('без точных будильников настройки честно говорят об этом', (
    tester,
  ) async {
    final status = FakeReminderStatus(
      const ReminderStatus(exactAlarms: false, notificationsAllowed: true),
    );
    await tester.pumpWidget(
      WorkRestApp(engine: engine, clock: clock, reminderStatus: status),
    );
    await openSettings(tester);

    expect(key('settings-exact-alarms'), findsOneWidget);
    expect(find.textContaining('неточные'), findsOneWidget);

    await tap(tester, key('settings-request-exact-alarms'));

    expect(status.exactAlarmRequests, 1);
    expect(key('settings-request-exact-alarms'), findsNothing);
    expect(find.textContaining('точные'), findsOneWidget);
  });

  testWidgets('запрет уведомлений в системе виден в настройках', (
    tester,
  ) async {
    final status = FakeReminderStatus(
      const ReminderStatus(exactAlarms: true, notificationsAllowed: false),
    );
    await tester.pumpWidget(
      WorkRestApp(engine: engine, clock: clock, reminderStatus: status),
    );
    await openSettings(tester);

    // Точные напоминания выданы, а показ уведомлений запрещён в системе:
    // экран говорит именно об этом и не предлагает разрешение на точность.
    expect(key('settings-notifications-blocked'), findsOneWidget);
    expect(key('settings-request-exact-alarms'), findsNothing);
  });
}

/// Порт напоминаний, который запоминает последнюю раскладку.
final class RecordingReminders implements RestReminderPort {
  final List<RestReminder> planned = <RestReminder>[];

  @override
  Future<void> cancelAll() async => planned.clear();

  @override
  Future<void> dismiss(RestReminder reminder) async => planned.remove(reminder);

  @override
  Future<void> schedule(RestReminder reminder) async => planned.add(reminder);
}

/// Разрешения напоминаний, которыми управляет тест: сначала точных будильников
/// нет, после запроса они выдаются.
final class FakeReminderStatus implements ReminderStatusSource {
  FakeReminderStatus(this._status);

  ReminderStatus _status;
  int exactAlarmRequests = 0;

  @override
  Future<ReminderStatus> read() async => _status;

  @override
  Future<ReminderStatus> requestExactAlarms() async {
    exactAlarmRequests++;
    _status = const ReminderStatus(
      exactAlarms: true,
      notificationsAllowed: true,
    );
    return _status;
  }
}
