import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

/// Часы, которые двигаются только по команде теста: реальное время не читается.
class FakeClock {
  FakeClock([DateTime? start]) : _now = start ?? _at(9);

  DateTime _now;

  DateTime get now => _now;

  DateTime advance(Duration delta) => _now = _now.add(delta);
}

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

void main() {
  late FakeClock clock;
  late WorkDayEngine engine;

  setUp(() {
    clock = FakeClock();
    // Механика дня проверяется отдельно от ритма: интервалы отдыха длиннее
    // рабочего окна, поэтому предложений отдыха в этих тестах нет.
    engine = WorkDayEngine(
      shortRestInterval: const Duration(hours: 12),
      longRestInterval: const Duration(hours: 12),
    );
  });

  group('рабочий день ещё не начат', () {
    test('фаза «не начат», доступен только старт, видно остаток окна', () {
      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.notStarted);
      expect(snapshot.availableCommands, [WorkDayCommand.start]);
      expect(snapshot.worked, Duration.zero);
      expect(snapshot.remainingInWorkWindow, const Duration(hours: 9));
      expect(snapshot.events, isEmpty);
    });
  });

  group('старт рабочего дня', () {
    test('старт переводит день в работу, счёт времени идёт', () {
      expect(engine.startWorkDay(clock.now), isA<WorkDayCommandAccepted>());

      clock.advance(const Duration(minutes: 10));
      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.availableCommands, [
        WorkDayCommand.pause,
        WorkDayCommand.finish,
        WorkDayCommand.startMeal,
      ]);
      expect(snapshot.worked, const Duration(minutes: 10));
      expect(
        snapshot.remainingInWorkWindow,
        const Duration(hours: 8, minutes: 50),
      );
      expect(snapshot.startedAt, _at(9));
      expect(snapshot.events, [WorkDayEvent.started(_at(9))]);
    });

    test('повторный старт отклоняется и не меняет состояние', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(minutes: 10));

      final result = engine.startWorkDay(clock.now);

      expect(
        (result as WorkDayCommandRejected).reason,
        RejectionReason.workDayAlreadyInProgress,
      );
      final snapshot = engine.snapshot(clock.now);
      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.worked, const Duration(minutes: 10));
      expect(snapshot.events, [WorkDayEvent.started(_at(9))]);
    });
  });

  group('пауза и возобновление', () {
    test('пауза замораживает счёт рабочего времени', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(minutes: 10));

      expect(engine.pause(clock.now), isA<WorkDayCommandAccepted>());
      clock.advance(const Duration(minutes: 30));
      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.paused);
      expect(snapshot.availableCommands, [
        WorkDayCommand.resume,
        WorkDayCommand.finish,
      ]);
      expect(snapshot.worked, const Duration(minutes: 10));
      expect(snapshot.events, [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.paused(_at(9, 10)),
      ]);
    });

    test('возобновление продолжает счёт без скачка', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(minutes: 10));
      engine.pause(clock.now);
      clock.advance(const Duration(minutes: 30));

      expect(engine.resume(clock.now), isA<WorkDayCommandAccepted>());
      clock.advance(const Duration(minutes: 5));
      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.worked, const Duration(minutes: 15));
      expect(snapshot.events, [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.paused(_at(9, 10)),
        WorkDayEvent.resumed(_at(9, 40)),
      ]);
    });

    test('пауза в неначатом дне отклоняется', () {
      final result = engine.pause(clock.now);

      expect(
        (result as WorkDayCommandRejected).reason,
        RejectionReason.workDayNotStarted,
      );
      expect(engine.snapshot(clock.now).phase, WorkDayPhase.notStarted);
    });

    test('возобновление идущего дня отклоняется', () {
      engine.startWorkDay(clock.now);

      final result = engine.resume(clock.now);

      expect(
        (result as WorkDayCommandRejected).reason,
        RejectionReason.workDayNotPaused,
      );
      expect(engine.snapshot(clock.now).phase, WorkDayPhase.running);
    });
  });

  group('конец рабочего окна', () {
    test('в конце окна день завершается сам, счёт останавливается', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(hours: 10));

      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.finished);
      expect(snapshot.worked, const Duration(hours: 9));
      expect(snapshot.finishedAt, _at(18));
      expect(snapshot.remainingInWorkWindow, Duration.zero);
      expect(snapshot.availableCommands, isEmpty);
      expect(
        snapshot.events.last,
        WorkDayEvent.finished(_at(18), WorkDayFinishReason.workWindowEnded),
      );
    });

    test('автозавершение пишется в журнал один раз', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(hours: 10));

      engine.snapshot(clock.now);
      engine.snapshot(clock.now);

      expect(engine.snapshot(clock.now).events, [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.finished(_at(18), WorkDayFinishReason.workWindowEnded),
      ]);
    });

    test('на паузе конец окна тоже завершает день, пауза не идёт в счёт', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(hours: 1));
      engine.pause(clock.now);
      clock.advance(const Duration(hours: 10));

      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.finished);
      expect(snapshot.worked, const Duration(hours: 1));
      expect(snapshot.finishedAt, _at(18));
    });

    test('команда после конца окна отклоняется как завершённый день', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(hours: 10));

      final result = engine.pause(clock.now);

      expect(
        (result as WorkDayCommandRejected).reason,
        RejectionReason.workDayAlreadyFinished,
      );
    });

    test('старт после конца окна отклоняется с причиной', () {
      clock.advance(const Duration(hours: 12));

      final snapshot = engine.snapshot(clock.now);
      expect(snapshot.availableCommands, isEmpty);
      expect(snapshot.remainingInWorkWindow, Duration.zero);

      final result = engine.startWorkDay(clock.now);
      expect(
        (result as WorkDayCommandRejected).reason,
        RejectionReason.outsideWorkWindow,
      );
      expect(engine.snapshot(clock.now).phase, WorkDayPhase.notStarted);
    });

    test('старт до начала окна отклоняется с причиной', () {
      clock = FakeClock(_at(8));

      final result = engine.startWorkDay(clock.now);

      expect(
        (result as WorkDayCommandRejected).reason,
        RejectionReason.outsideWorkWindow,
      );
    });
  });

  group('новый рабочий день в тот же день', () {
    test('после ручного завершения день можно начать заново', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(hours: 1));
      engine.finishWorkDay(clock.now);
      clock.advance(const Duration(hours: 1));

      expect(engine.startWorkDay(clock.now), isA<WorkDayCommandAccepted>());
      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.worked, Duration.zero);
      expect(snapshot.remainingInWorkWindow, const Duration(hours: 7));
      expect(snapshot.events, [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.finished(_at(10), WorkDayFinishReason.manual),
        WorkDayEvent.started(_at(11)),
      ]);
    });
  });

  group('следующий календарный день', () {
    test('остаток окна считается от нового дня, а не от вчерашнего', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(hours: 1));
      engine.finishWorkDay(clock.now);
      clock.advance(const Duration(hours: 23));

      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.finished);
      expect(snapshot.remainingInWorkWindow, const Duration(hours: 9));
      expect(snapshot.availableCommands, [WorkDayCommand.start]);
    });

    test(
      'день, закрытый концом окна, на следующий день показывает новое окно',
      () {
        engine.startWorkDay(clock.now);
        clock.advance(const Duration(hours: 24));

        final snapshot = engine.snapshot(clock.now);

        expect(snapshot.phase, WorkDayPhase.finished);
        expect(snapshot.remainingInWorkWindow, const Duration(hours: 9));
      },
    );
  });

  group('ручное завершение', () {
    test('завершение фиксирует отработанное время и фазу', () {
      engine.startWorkDay(clock.now);
      clock.advance(const Duration(minutes: 10));
      engine.pause(clock.now);
      clock.advance(const Duration(minutes: 20));
      engine.resume(clock.now);
      clock.advance(const Duration(minutes: 5));

      expect(engine.finishWorkDay(clock.now), isA<WorkDayCommandAccepted>());
      clock.advance(const Duration(minutes: 30));
      final snapshot = engine.snapshot(clock.now);

      expect(snapshot.phase, WorkDayPhase.finished);
      expect(snapshot.availableCommands, [WorkDayCommand.start]);
      expect(snapshot.worked, const Duration(minutes: 15));
      expect(snapshot.finishedAt, _at(9, 35));
      expect(
        snapshot.remainingInWorkWindow,
        const Duration(hours: 7, minutes: 55),
      );
      expect(
        snapshot.events.last,
        WorkDayEvent.finished(_at(9, 35), WorkDayFinishReason.manual),
      );
    });

    test('завершение неначатого дня отклоняется', () {
      final result = engine.finishWorkDay(clock.now);

      expect(
        (result as WorkDayCommandRejected).reason,
        RejectionReason.workDayNotStarted,
      );
    });

    test('повторное завершение отклоняется', () {
      engine.startWorkDay(clock.now);
      engine.finishWorkDay(clock.now);

      final result = engine.finishWorkDay(clock.now);

      expect(
        (result as WorkDayCommandRejected).reason,
        RejectionReason.workDayAlreadyFinished,
      );
      expect(engine.snapshot(clock.now).phase, WorkDayPhase.finished);
    });
  });
}
