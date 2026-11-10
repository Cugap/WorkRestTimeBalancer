import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

/// Порт, который запоминает ровно то, что ядро ему передало: после каждого
/// планирования список равен последней раскладке.
final class RecordingReminderPort implements RestReminderPort {
  final List<RestReminder> planned = <RestReminder>[];
  int cancelAllCalls = 0;

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    planned.clear();
  }

  @override
  Future<void> schedule(RestReminder reminder) async {
    planned.add(reminder);
  }
}

/// Порт, который сначала падает: проверяет, что ядро не считает раскладку
/// переданной и повторит её при следующей смене состояния.
final class FlakyReminderPort implements RestReminderPort {
  final List<RestReminder> planned = <RestReminder>[];
  bool failing = true;

  @override
  Future<void> cancelAll() async {
    if (failing) {
      throw StateError('platform is unavailable');
    }
    planned.clear();
  }

  @override
  Future<void> schedule(RestReminder reminder) async {
    if (failing) {
      throw StateError('platform is unavailable');
    }
    planned.add(reminder);
  }
}

/// Движок с записывающим портом: шаг сценария — команда или просто ход
/// времени, после шага — проверка раскладки напоминаний.
final class ReminderDesk {
  ReminderDesk._(this.port, this.engine);

  factory ReminderDesk({
    int reminderLimit = 6,
    RhythmSettings settings = RhythmSettings.defaults,
  }) {
    final port = RecordingReminderPort();
    return ReminderDesk._(
      port,
      WorkDayEngine(
        settings: settings,
        reminderLimit: reminderLimit,
        reminders: port,
      ),
    );
  }

  final RecordingReminderPort port;
  final WorkDayEngine engine;

  /// Выполнить команду (null — только запрос снимка) и вернуть раскладку,
  /// которая оказалась в порте.
  Future<List<RestReminder>> at(DateTime now, [WorkDayCommand? command]) async {
    switch (command) {
      case WorkDayCommand.start:
        engine.startWorkDay(now);
      case WorkDayCommand.pause:
        engine.pause(now);
      case WorkDayCommand.resume:
        engine.resume(now);
      case WorkDayCommand.finish:
        engine.finishWorkDay(now);
      case WorkDayCommand.startRest:
        engine.startRest(now);
      case WorkDayCommand.finishRest:
        engine.finishRest(now);
      case WorkDayCommand.skipRest:
        engine.skipRest(now);
      case WorkDayCommand.postponeRest:
        engine.postponeRest(now);
      case WorkDayCommand.startMeal:
        engine.startMeal(now);
      case null:
        engine.snapshot(now);
    }
    await engine.remindPlanApplied;
    return List<RestReminder>.of(port.planned);
  }

  /// Изменить настройки от текущих и вернуть новую раскладку.
  Future<List<RestReminder>> update(
    DateTime now,
    RhythmSettings Function(RhythmSettings current) change,
  ) async {
    final current = engine.snapshot(now).settings;
    engine.updateSettings(now, change(current));
    await engine.remindPlanApplied;
    return List<RestReminder>.of(port.planned);
  }
}

RestReminder _reminder(
  DateTime at,
  RestKind kind,
  Duration duration, {
  bool playSound = true,
}) =>
    RestReminder(at: at, kind: kind, duration: duration, playSound: playSound);

RestReminder _short(DateTime at, {bool playSound = true}) => _reminder(
  at,
  RestKind.short,
  const Duration(minutes: 3),
  playSound: playSound,
);

RestReminder _long(DateTime at, {bool playSound = true}) => _reminder(
  at,
  RestKind.long,
  const Duration(minutes: 10),
  playSound: playSound,
);

RestReminder _meal(DateTime at, {bool playSound = true}) => _reminder(
  at,
  RestKind.meal,
  const Duration(minutes: 60),
  playSound: playSound,
);

void main() {
  group('планирование напоминаний', () {
    test('начало рабочего дня планирует ближайшие точки отдыха', () async {
      final desk = ReminderDesk();

      final planned = await desk.at(_at(9), WorkDayCommand.start);

      // Короткий отдых 25/3, длинный 90/10, обед в 13:00: каждая точка
      // сдвигается на длительность предыдущего отдыха, длинный — ещё и на
      // длительность коротких.
      expect(planned, [
        _short(_at(9, 25)),
        _short(_at(9, 53)),
        _short(_at(10, 21)),
        _long(_at(10, 39)),
        _short(_at(11, 14)),
        _short(_at(11, 42)),
      ]);
    });

    test(
      'пауза отменяет напоминания, возобновление планирует заново',
      () async {
        final desk = ReminderDesk(reminderLimit: 2);

        expect(await desk.at(_at(9), WorkDayCommand.start), [
          _short(_at(9, 25)),
          _short(_at(9, 53)),
        ]);

        expect(await desk.at(_at(9, 10), WorkDayCommand.pause), isEmpty);

        // Пауза на 10 минут сдвигает и короткий, и длинный счётчик.
        expect(await desk.at(_at(9, 20), WorkDayCommand.resume), [
          _short(_at(9, 35)),
          _short(_at(10, 3)),
        ]);
      },
    );

    test('ручное завершение дня отменяет напоминания', () async {
      final desk = ReminderDesk(reminderLimit: 2);
      await desk.at(_at(9), WorkDayCommand.start);

      expect(await desk.at(_at(10), WorkDayCommand.finish), isEmpty);
    });

    test('конец рабочего окна отменяет напоминания', () async {
      final desk = ReminderDesk(
        reminderLimit: 4,
        settings: const RhythmSettings(
          workStart: ClockTime(9, 0),
          workEnd: ClockTime(10, 0),
        ),
      );
      await desk.at(_at(9), WorkDayCommand.start);

      expect(await desk.at(_at(10, 30)), isEmpty);
    });

    test(
      'предложение снимает напоминания, отдых планирует следующие',
      () async {
        final desk = ReminderDesk(reminderLimit: 2);
        await desk.at(_at(9), WorkDayCommand.start);

        // Предложение уже на экране — напоминать о нём не нужно.
        expect(await desk.at(_at(9, 25)), isEmpty);

        // Идущий отдых заканчивается сам, и ритм продолжается от его конца:
        // короткий отдых переносит ещё и счётчик длинного.
        expect(await desk.at(_at(9, 25), WorkDayCommand.startRest), [
          _short(_at(9, 53)),
          _short(_at(10, 21)),
        ]);

        // Досрочное завершение начинает новый интервал работы с этого момента.
        expect(await desk.at(_at(9, 27), WorkDayCommand.finishRest), [
          _short(_at(9, 52)),
          _short(_at(10, 20)),
        ]);
      },
    );

    test('пропуск отдыха планирует следующий', () async {
      final desk = ReminderDesk(reminderLimit: 2);
      await desk.at(_at(9), WorkDayCommand.start);
      await desk.at(_at(9, 25));

      expect(await desk.at(_at(9, 25), WorkDayCommand.skipRest), [
        _short(_at(9, 50)),
        _short(_at(10, 18)),
      ]);
    });

    test('отложение переносит напоминание на новый момент', () async {
      final desk = ReminderDesk(reminderLimit: 2);
      await desk.at(_at(9), WorkDayCommand.start);
      await desk.at(_at(9, 25));

      expect(await desk.at(_at(9, 25), WorkDayCommand.postponeRest), [
        _short(_at(9, 30)),
        _short(_at(9, 58)),
      ]);
    });

    test('обед попадает в раскладку со своей длительностью', () async {
      final desk = ReminderDesk(
        reminderLimit: 2,
        settings: const RhythmSettings(
          workStart: ClockTime(12, 30),
          shortRestInterval: Duration(minutes: 30),
          longRestInterval: Duration(minutes: 120),
          mealStart: ClockTime(13, 0),
        ),
      );
      await desk.at(_at(12, 30), WorkDayCommand.start);

      // В 13:00 одновременно короткий отдых и обед: предлагается обед, и он
      // начинает ритм заново от своего конца.
      expect(await desk.at(_at(12, 30)), [
        _meal(_at(13, 0)),
        _short(_at(14, 30)),
      ]);
    });

    test(
      'выключенные напоминания не планируются и включаются обратно',
      () async {
        final desk = ReminderDesk(reminderLimit: 2);
        await desk.at(_at(9), WorkDayCommand.start);

        expect(
          await desk.update(
            _at(9, 5),
            (settings) => settings.copyWith(notificationsEnabled: false),
          ),
          isEmpty,
        );

        expect(
          await desk.update(
            _at(9, 6),
            (settings) => settings.copyWith(notificationsEnabled: true),
          ),
          [_short(_at(9, 25)), _short(_at(9, 53))],
        );
      },
    );

    test('выключенный звук делает напоминания тихими', () async {
      final desk = ReminderDesk(reminderLimit: 2);
      await desk.at(_at(9), WorkDayCommand.start);

      expect(
        await desk.update(
          _at(9, 5),
          (settings) => settings.copyWith(soundEnabled: false),
        ),
        [
          _short(_at(9, 25), playSound: false),
          _short(_at(9, 53), playSound: false),
        ],
      );
    });

    test('в раскладку попадают только точки внутри рабочего окна', () async {
      final desk = ReminderDesk(
        reminderLimit: 8,
        settings: const RhythmSettings(
          workStart: ClockTime(9, 0),
          workEnd: ClockTime(10, 0),
        ),
      );

      expect(await desk.at(_at(9), WorkDayCommand.start), [
        _short(_at(9, 25)),
        _short(_at(9, 53)),
      ]);
    });

    test('ход времени без смены состояния не переписывает раскладку', () async {
      final desk = ReminderDesk(reminderLimit: 2);
      await desk.at(_at(9), WorkDayCommand.start);
      final cancels = desk.port.cancelAllCalls;

      await desk.at(_at(9, 1));
      await desk.at(_at(9, 2));
      await desk.at(_at(9, 3));

      expect(desk.port.cancelAllCalls, cancels);
    });

    test(
      'сбой записи раскладки повторяется при следующей смене состояния',
      () async {
        final port = FlakyReminderPort();
        final engine = WorkDayEngine(reminderLimit: 2, reminders: port);

        engine.startWorkDay(_at(9));
        await engine.remindPlanApplied;

        // Первая запись упала: раскладка не считается переданной.
        expect(engine.lastReminderFailure, isNotNull);
        expect(port.planned, isEmpty);

        port.failing = false;
        engine.pause(_at(9, 10));
        await engine.remindPlanApplied;
        engine.resume(_at(9, 20));
        await engine.remindPlanApplied;

        // Повторная попытка удалась: ошибка снята, раскладка на месте.
        expect(engine.lastReminderFailure, isNull);
        expect(port.planned, [_short(_at(9, 35)), _short(_at(10, 3))]);
      },
    );

    test('после перезапуска напоминания планируются заново', () async {
      final first = ReminderDesk(reminderLimit: 2);
      await first.at(_at(9), WorkDayCommand.start);
      await first.at(_at(9, 10));

      final port = RecordingReminderPort();
      final restored = WorkDayEngine.restore(
        first.engine.document(),
        reminderLimit: 2,
        reminders: port,
      );

      restored.snapshot(_at(9, 12));
      await restored.remindPlanApplied;

      expect(port.planned, [_short(_at(9, 25)), _short(_at(9, 53))]);
    });

    test('ручной обед снимает напоминание об обеде', () async {
      final desk = ReminderDesk(reminderLimit: 8);
      await desk.at(_at(9), WorkDayCommand.start);

      await desk.at(_at(10), WorkDayCommand.startMeal);

      expect(desk.port.planned.where((r) => r.kind == RestKind.meal), isEmpty);
    });

    test('раскладка совпадает с настоящими точками отдыха за день', () async {
      final desk = ReminderDesk(reminderLimit: 30);
      final planned = await desk.at(_at(9), WorkDayCommand.start);

      // Независимая проверка: проходим день на движке без порта и записываем
      // каждую точку, которую он действительно предлагает, беря каждый отдых.
      final day = WorkDayEngine();
      day.startWorkDay(_at(9));
      var now = _at(9);
      final offered = <RestReminder>[];
      while (now.isBefore(_at(18))) {
        final snapshot = day.snapshot(now);
        if (snapshot.phase == WorkDayPhase.finished) {
          break;
        }
        if (snapshot.phase != WorkDayPhase.restOffered) {
          now = now.add(const Duration(minutes: 1));
          continue;
        }
        offered.add(
          RestReminder(
            at: now,
            kind: snapshot.restKind!,
            duration: snapshot.restDuration!,
          ),
        );
        day.startRest(now);
        now = now.add(snapshot.restDuration!);
        day.snapshot(now);
      }

      expect(offered, planned);
    });

    test('лимит раскладки по умолчанию укладывается в лимит iOS', () async {
      // iOS хранит около 64 запланированных уведомлений и молча выбрасывает
      // лишние, поэтому заранее планируются только ближайшие восемь точек.
      expect(defaultReminderLimit, 8);
      expect(defaultReminderLimit, lessThan(64));

      final port = RecordingReminderPort();
      final engine = WorkDayEngine(reminders: port);
      engine.startWorkDay(_at(9));
      await engine.remindPlanApplied;

      expect(port.planned, hasLength(defaultReminderLimit));
      expect(port.planned.last.at.isBefore(_at(18)), isTrue);
    });

    test('без фонового таймера возврат догоняет день одним отдыхом', () async {
      // iOS не исполняет код в фоне: между началом дня и возвратом в
      // приложение не было ни одного снимка, а приложение было выгружено.
      final first = ReminderDesk(reminderLimit: 2);
      expect(await first.at(_at(9), WorkDayCommand.start), [
        _short(_at(9, 25)),
        _short(_at(9, 53)),
      ]);

      final port = RecordingReminderPort();
      final restored = WorkDayEngine.restore(
        first.engine.document(),
        reminderLimit: 2,
        reminders: port,
      );
      final snapshot = restored.snapshot(_at(10, 5));
      await restored.remindPlanApplied;

      // Фаза и отдых соответствуют реально прошедшему времени, а не тому
      // состоянию, в котором приложение уснуло.
      expect(snapshot.phase, WorkDayPhase.restOffered);
      expect(snapshot.restKind, RestKind.short);
      expect(snapshot.restDuration, const Duration(minutes: 3));

      // Прошедшие точки записаны пропусками, предложение ровно одно: очередь
      // из пропущенных отдыхов не копится.
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.restSkipped,
        ),
        hasLength(2),
      );
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        hasLength(1),
      );

      // Пока предложение на экране, напоминать не о чем: прошлые точки из
      // раскладки не возвращаются.
      expect(port.planned, isEmpty);
    });

    test('процесс выжил, но тиков не было: предложение одно', () async {
      final desk = ReminderDesk(reminderLimit: 2);
      await desk.at(_at(9), WorkDayCommand.start);

      // Час без единого вызова снимка — так выглядит свёрнутое приложение на
      // iOS. По возвращении отдых предлагается один раз, а не по разу на
      // каждую пропущенную точку.
      final snapshot = desk.engine.snapshot(_at(10, 5));
      await desk.engine.remindPlanApplied;

      expect(snapshot.phase, WorkDayPhase.restOffered);
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        hasLength(1),
      );

      // Раскладка, сделанная до сворачивания, заменена: прошлых напоминаний в
      // ней не остаётся.
      expect(desk.port.planned, isEmpty);
      expect(desk.port.cancelAllCalls, greaterThan(1));
    });
  });
}
