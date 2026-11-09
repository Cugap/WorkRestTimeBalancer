import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

DateTime _at(int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 3, 4, hour, minute, second);

void main() {
  late WorkDayEngine engine;

  setUp(() {
    engine = WorkDayEngine();
  });

  group('предложение короткого отдыха', () {
    test('в момент отдыха ядро предлагает короткий отдых', () {
      engine.startWorkDay(_at(9));

      final before = engine.snapshot(_at(9, 24, 59));
      expect(before.phase, WorkDayPhase.running);
      expect(before.untilNextRest, const Duration(seconds: 1));
      expect(before.restKind, isNull);

      final offered = engine.snapshot(_at(9, 25));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.short);
      expect(offered.untilNextRest, Duration.zero);
      expect(offered.nextRestAt, isNull);
      expect(offered.availableCommands, [
        WorkDayCommand.startRest,
        WorkDayCommand.skipRest,
        WorkDayCommand.postponeRest,
        WorkDayCommand.pause,
        WorkDayCommand.finish,
      ]);
      expect(
        offered.events.last,
        WorkDayEvent.restOffered(_at(9, 25), RestKind.short),
      );
    });

    test('пока отдых предложен, время работы продолжает идти', () {
      engine.startWorkDay(_at(9));

      final snapshot = engine.snapshot(_at(9, 30));

      expect(snapshot.phase, WorkDayPhase.restOffered);
      expect(snapshot.worked, const Duration(minutes: 30));
    });

    test('предложение пишется в журнал один раз', () {
      engine.startWorkDay(_at(9));

      engine.snapshot(_at(9, 25));
      engine.snapshot(_at(9, 26));
      final events = engine.snapshot(_at(9, 27)).events;

      expect(
        events.where((event) => event.type == WorkDayEventType.restOffered),
        hasLength(1),
      );
    });

    test('долгий пропуск тика не создаёт очередь отдыхов', () {
      engine.startWorkDay(_at(9));

      final snapshot = engine.snapshot(_at(10));

      expect(snapshot.phase, WorkDayPhase.restOffered);
      expect(snapshot.worked, const Duration(hours: 1));
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        hasLength(1),
      );
    });
  });

  group('начало короткого отдыха', () {
    test('«Начать» запускает таймер отдыха, время работы замирает', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 27));

      expect(engine.startRest(_at(9, 27)), isA<WorkDayCommandAccepted>());
      final started = engine.snapshot(_at(9, 27));

      expect(started.phase, WorkDayPhase.resting);
      expect(started.restKind, RestKind.short);
      expect(started.remainingRest, const Duration(minutes: 3));
      expect(started.untilNextRest, isNull);
      expect(started.nextRestAt, isNull);
      expect(started.workIntervalStartedAt, isNull);
      expect(started.worked, const Duration(minutes: 27));
      expect(started.availableCommands, [
        WorkDayCommand.finishRest,
        WorkDayCommand.finish,
      ]);
      expect(
        started.events.last,
        WorkDayEvent.restStarted(_at(9, 27), RestKind.short),
      );

      final oneMinuteLater = engine.snapshot(_at(9, 28));

      expect(oneMinuteLater.remainingRest, const Duration(minutes: 2));
      expect(oneMinuteLater.worked, const Duration(minutes: 27));
    });

    test('отдых заканчивается сам и начинается новый интервал работы', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      final afterRest = engine.snapshot(_at(9, 28));

      expect(afterRest.phase, WorkDayPhase.running);
      expect(afterRest.restKind, isNull);
      expect(afterRest.remainingRest, isNull);
      expect(afterRest.worked, const Duration(minutes: 25));
      expect(afterRest.untilNextRest, const Duration(minutes: 25));
      expect(afterRest.nextRestAt, _at(9, 53));
      expect(afterRest.workIntervalStartedAt, _at(9, 28));
      expect(afterRest.events, [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.restOffered(_at(9, 25), RestKind.short),
        WorkDayEvent.restStarted(_at(9, 25), RestKind.short),
        WorkDayEvent.restFinished(
          _at(9, 28),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
          actualDuration: const Duration(minutes: 3),
        ),
      ]);
    });

    test('новый интервал считается от конца отдыха, а не от момента тика', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      final snapshot = engine.snapshot(_at(9, 40));

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.worked, const Duration(minutes: 37));
      expect(snapshot.nextRestAt, _at(9, 53));
      expect(snapshot.untilNextRest, const Duration(minutes: 13));
    });

    test('завершение рабочего дня во время отдыха прерывает отдых', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      expect(engine.finishWorkDay(_at(9, 26)), isA<WorkDayCommandAccepted>());
      final snapshot = engine.snapshot(_at(9, 26));

      expect(snapshot.phase, WorkDayPhase.finished);
      expect(snapshot.remainingRest, isNull);
      expect(snapshot.restKind, isNull);
      expect(snapshot.worked, const Duration(minutes: 25));
    });
  });

  group('досрочное завершение отдыха', () {
    test('«Закончить сейчас» сразу начинает новый интервал работы', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      expect(engine.finishRest(_at(9, 26)), isA<WorkDayCommandAccepted>());
      final snapshot = engine.snapshot(_at(9, 26));

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.restKind, isNull);
      expect(snapshot.remainingRest, isNull);
      expect(snapshot.exercises, isEmpty);
      expect(snapshot.worked, const Duration(minutes: 25));
      expect(snapshot.workIntervalStartedAt, _at(9, 26));
      expect(snapshot.nextRestAt, _at(9, 51));
      expect(snapshot.untilNextRest, const Duration(minutes: 25));
      expect(snapshot.availableCommands, [
        WorkDayCommand.pause,
        WorkDayCommand.finish,
      ]);
    });

    test('досрочное завершение пишется в журнал с причиной и длительностью', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));
      engine.finishRest(_at(9, 26));

      final snapshot = engine.snapshot(_at(9, 26));
      final expected = WorkDayEvent.restFinished(
        _at(9, 26),
        RestKind.short,
        restFinishReason: RestFinishReason.early,
        plannedDuration: const Duration(minutes: 3),
        actualDuration: const Duration(minutes: 1),
      );

      expect(snapshot.lastRestFinished, expected);
      expect(snapshot.events, [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.restOffered(_at(9, 25), RestKind.short),
        WorkDayEvent.restStarted(_at(9, 25), RestKind.short),
        expected,
      ]);
    });

    test('естественное завершение отмечает плановую и фактическую длительность', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      final lastRest = engine.snapshot(_at(9, 28)).lastRestFinished!;

      expect(lastRest.restFinishReason, RestFinishReason.natural);
      expect(lastRest.plannedDuration, const Duration(minutes: 3));
      expect(lastRest.actualDuration, const Duration(minutes: 3));
    });

    test('после досрочного завершения новый отдых приходит по ритму', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));
      engine.finishRest(_at(9, 26));

      expect(engine.snapshot(_at(9, 50, 59)).phase, WorkDayPhase.running);
      expect(engine.snapshot(_at(9, 51)).phase, WorkDayPhase.restOffered);
    });

    test('завершение отдыха, когда отдых не идёт, отклоняется', () {
      engine.startWorkDay(_at(9));

      expect(
        (engine.finishRest(_at(9, 10)) as WorkDayCommandRejected).reason,
        RejectionReason.restNotInProgress,
      );
      expect(engine.snapshot(_at(9, 10)).phase, WorkDayPhase.running);

      engine.snapshot(_at(9, 25));

      expect(
        (engine.finishRest(_at(9, 26)) as WorkDayCommandRejected).reason,
        RejectionReason.restNotInProgress,
      );
      expect(engine.snapshot(_at(9, 26)).phase, WorkDayPhase.restOffered);
    });

    test('досрочное завершение после конца окна закрывает день', () {
      engine.startWorkDay(_at(17, 30));
      engine.snapshot(_at(17, 55));
      engine.startRest(_at(17, 58));

      expect(engine.finishRest(_at(18, 0, 30)), isA<WorkDayCommandAccepted>());
      final snapshot = engine.snapshot(_at(18, 0, 30));

      expect(snapshot.phase, WorkDayPhase.finished);
      expect(snapshot.finishedAt, _at(18));
      expect(snapshot.remainingRest, isNull);
      expect(
        snapshot.lastRestFinished,
        WorkDayEvent.restFinished(
          _at(18, 0, 30),
          RestKind.short,
          restFinishReason: RestFinishReason.early,
          plannedDuration: const Duration(minutes: 3),
          actualDuration: const Duration(minutes: 2, seconds: 30),
        ),
      );
    });

    test('завершение рабочего дня во время отдыха пишет конец отдыха', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));
      engine.finishWorkDay(_at(9, 26));

      final snapshot = engine.snapshot(_at(9, 26));
      final expected = WorkDayEvent.restFinished(
        _at(9, 26),
        RestKind.short,
        restFinishReason: RestFinishReason.workDayEnded,
        plannedDuration: const Duration(minutes: 3),
        actualDuration: const Duration(minutes: 1),
      );

      expect(snapshot.lastRestFinished, expected);
      expect(snapshot.events, [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.restOffered(_at(9, 25), RestKind.short),
        WorkDayEvent.restStarted(_at(9, 25), RestKind.short),
        expected,
        WorkDayEvent.finished(_at(9, 26), WorkDayFinishReason.manual),
      ]);
    });
  });

  group('пропуск короткого отдыха', () {
    test('«Пропустить» сразу начинает новый интервал работы', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));

      expect(engine.skipRest(_at(9, 26)), isA<WorkDayCommandAccepted>());
      final snapshot = engine.snapshot(_at(9, 26));

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.restKind, isNull);
      expect(snapshot.untilNextRest, const Duration(minutes: 25));
      expect(snapshot.nextRestAt, _at(9, 51));
      expect(snapshot.workIntervalStartedAt, _at(9, 26));
      expect(snapshot.worked, const Duration(minutes: 26));
      expect(
        snapshot.events.last,
        WorkDayEvent.restSkipped(_at(9, 26), RestKind.short),
      );
    });

    test('пропущенный отдых не предлагается повторно и не копится долгом', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.skipRest(_at(9, 25));

      expect(engine.snapshot(_at(9, 30)).phase, WorkDayPhase.running);
      expect(engine.snapshot(_at(9, 49, 59)).phase, WorkDayPhase.running);
      expect(engine.snapshot(_at(9, 50)).phase, WorkDayPhase.restOffered);
    });
  });

  group('отказ команд отдыха', () {
    test('начало и пропуск без предложения отклоняются', () {
      engine.startWorkDay(_at(9));

      expect(
        (engine.startRest(_at(9, 10)) as WorkDayCommandRejected).reason,
        RejectionReason.restNotOffered,
      );
      expect(
        (engine.skipRest(_at(9, 10)) as WorkDayCommandRejected).reason,
        RejectionReason.restNotOffered,
      );
      expect(engine.snapshot(_at(9, 10)).phase, WorkDayPhase.running);
    });

    test('во время отдыха пауза и повторный старт отклоняются', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      expect(
        (engine.pause(_at(9, 26)) as WorkDayCommandRejected).reason,
        RejectionReason.restInProgress,
      );
      expect(
        (engine.startRest(_at(9, 26)) as WorkDayCommandRejected).reason,
        RejectionReason.restInProgress,
      );
      final snapshot = engine.snapshot(_at(9, 26));

      expect(snapshot.phase, WorkDayPhase.resting);
      expect(snapshot.remainingRest, const Duration(minutes: 2));
    });

    test('старт нового рабочего дня во время отдыха отклоняется', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      expect(
        (engine.startWorkDay(_at(9, 26)) as WorkDayCommandRejected).reason,
        RejectionReason.workDayAlreadyInProgress,
      );
    });
  });

  group('пауза и ритм отдыха', () {
    test('пауза сдвигает следующий отдых на её длительность', () {
      engine.startWorkDay(_at(9));
      engine.pause(_at(9, 10));
      engine.resume(_at(9, 30));

      final snapshot = engine.snapshot(_at(9, 30));

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.nextRestAt, _at(9, 45));
      expect(snapshot.untilNextRest, const Duration(minutes: 15));
      expect(snapshot.workIntervalStartedAt, _at(9));
    });

    test('на паузе отсчёт до отдыха замирает', () {
      engine.startWorkDay(_at(9));
      engine.pause(_at(9, 10));

      final early = engine.snapshot(_at(9, 12));
      final late = engine.snapshot(_at(9, 40));

      expect(early.untilNextRest, const Duration(minutes: 15));
      expect(late.untilNextRest, const Duration(minutes: 15));
      expect(late.phase, WorkDayPhase.paused);
      expect(late.restKind, isNull);
    });

    test('предложенный отдых на паузе ждёт возобновления', () {
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.pause(_at(9, 26));

      final paused = engine.snapshot(_at(9, 30));

      expect(paused.phase, WorkDayPhase.paused);
      expect(paused.restKind, RestKind.short);
      expect(paused.untilNextRest, Duration.zero);

      expect(engine.resume(_at(9, 40)), isA<WorkDayCommandAccepted>());
      final resumed = engine.snapshot(_at(9, 40));

      expect(resumed.phase, WorkDayPhase.restOffered);
      expect(resumed.availableCommands, [
        WorkDayCommand.startRest,
        WorkDayCommand.skipRest,
        WorkDayCommand.postponeRest,
        WorkDayCommand.pause,
        WorkDayCommand.finish,
      ]);
      expect(engine.startRest(_at(9, 41)), isA<WorkDayCommandAccepted>());
      expect(engine.snapshot(_at(9, 41)).phase, WorkDayPhase.resting);
    });
  });

  group('конец рабочего окна и ритм', () {
    test('отдых, момент которого попадает за конец окна, не предлагается', () {
      engine.startWorkDay(_at(17, 40));

      final snapshot = engine.snapshot(_at(17, 40));

      expect(snapshot.nextRestAt, isNull);
      expect(snapshot.untilNextRest, isNull);

      final atWindowEnd = engine.snapshot(_at(18));

      expect(atWindowEnd.phase, WorkDayPhase.finished);
      expect(atWindowEnd.restKind, isNull);
      expect(atWindowEnd.worked, const Duration(minutes: 20));
    });

    test('пауза может сдвинуть отдых за конец окна', () {
      engine.startWorkDay(_at(17));
      engine.pause(_at(17, 10));
      engine.resume(_at(17, 50));

      expect(engine.snapshot(_at(17, 50)).untilNextRest, isNull);
      expect(engine.snapshot(_at(17, 59)).phase, WorkDayPhase.running);
      expect(engine.snapshot(_at(18)).phase, WorkDayPhase.finished);
    });

    test('отдых доигрывается за концом окна, день закрывается по окну', () {
      engine.startWorkDay(_at(17, 30));
      engine.snapshot(_at(17, 55));
      engine.startRest(_at(17, 58));

      final duringRest = engine.snapshot(_at(18));
      expect(duringRest.phase, WorkDayPhase.resting);
      expect(duringRest.remainingRest, const Duration(minutes: 1));

      final afterRest = engine.snapshot(_at(18, 1));

      expect(afterRest.phase, WorkDayPhase.finished);
      expect(afterRest.finishedAt, _at(18));
      expect(afterRest.worked, const Duration(minutes: 28));
      expect(afterRest.events, [
        WorkDayEvent.started(_at(17, 30)),
        WorkDayEvent.restOffered(_at(17, 55), RestKind.short),
        WorkDayEvent.restStarted(_at(17, 58), RestKind.short),
        WorkDayEvent.finished(_at(18), WorkDayFinishReason.workWindowEnded),
        WorkDayEvent.restFinished(
          _at(18, 1),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
          actualDuration: const Duration(minutes: 3),
        ),
      ]);
    });
  });

  group('расчёт момента короткого отдыха', () {
    test('отсчёт начинается со старта рабочего дня', () {
      engine.startWorkDay(_at(9));

      final snapshot = engine.snapshot(_at(9));

      expect(snapshot.untilNextRest, const Duration(minutes: 25));
      expect(snapshot.nextRestAt, _at(9, 25));
      expect(snapshot.restKind, isNull);
    });

    test('отсчёт идёт от фактического старта, а не от начала окна', () {
      engine.startWorkDay(_at(9, 7));

      final snapshot = engine.snapshot(_at(9, 20));

      expect(snapshot.untilNextRest, const Duration(minutes: 12));
      expect(snapshot.nextRestAt, _at(9, 32));
    });

    test('до старта и после завершения дня отдых не запланирован', () {
      expect(engine.snapshot(_at(9)).untilNextRest, isNull);
      expect(engine.snapshot(_at(9)).nextRestAt, isNull);

      engine.startWorkDay(_at(9));
      engine.finishWorkDay(_at(9, 10));
      final snapshot = engine.snapshot(_at(9, 10));

      expect(snapshot.untilNextRest, isNull);
      expect(snapshot.nextRestAt, isNull);
      expect(snapshot.restKind, isNull);
    });
  });
}
