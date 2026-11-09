import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

DateTime _at(int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 3, 4, hour, minute, second);

void main() {
  late WorkDayEngine engine;

  setUp(() {
    engine = WorkDayEngine();
  });

  /// День начат в 9:00, первое предложение отдыха показано в 9:25.
  void offerFirstRest() {
    engine.startWorkDay(_at(9));
    engine.snapshot(_at(9, 25));
  }

  /// Предложение отдыха показано, отложено дважды и снова показано в 9:35.
  void postponeTwice() {
    offerFirstRest();
    engine.postponeRest(_at(9, 25));
    engine.snapshot(_at(9, 30));
    engine.postponeRest(_at(9, 30));
    engine.snapshot(_at(9, 35));
  }

  group('отложение короткого отдыха', () {
    test('отложение возвращает предложение через 5 минут, работа идёт', () {
      engine.startWorkDay(_at(9));

      final offered = engine.snapshot(_at(9, 25));
      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.remainingPostponements, 2);
      expect(offered.availableCommands, [
        WorkDayCommand.startRest,
        WorkDayCommand.skipRest,
        WorkDayCommand.postponeRest,
        WorkDayCommand.pause,
        WorkDayCommand.finish,
        WorkDayCommand.startMeal,
      ]);

      expect(engine.postponeRest(_at(9, 25)), isA<WorkDayCommandAccepted>());
      final postponed = engine.snapshot(_at(9, 25));

      expect(postponed.phase, WorkDayPhase.running);
      expect(postponed.restKind, isNull);
      expect(postponed.worked, const Duration(minutes: 25));
      expect(postponed.nextRestAt, _at(9, 30));
      expect(postponed.untilNextRest, const Duration(minutes: 5));
      expect(postponed.remainingPostponements, 1);
      expect(postponed.availableCommands, [
        WorkDayCommand.pause,
        WorkDayCommand.finish,
        WorkDayCommand.startMeal,
      ]);
      expect(
        postponed.events.last,
        WorkDayEvent.restPostponed(
          _at(9, 25),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
      );

      final countdown = engine.snapshot(_at(9, 29, 59));
      expect(countdown.phase, WorkDayPhase.running);
      expect(countdown.untilNextRest, const Duration(seconds: 1));
      expect(countdown.worked, const Duration(minutes: 29, seconds: 59));

      final shown = engine.snapshot(_at(9, 30));
      expect(shown.phase, WorkDayPhase.restOffered);
      expect(shown.worked, const Duration(minutes: 30));
      expect(shown.untilNextRest, Duration.zero);
      expect(shown.nextRestAt, isNull);
      expect(shown.remainingPostponements, 1);
      expect(
        shown.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        [
          WorkDayEvent.restOffered(
            _at(9, 25),
            RestKind.short,
            plannedDuration: const Duration(minutes: 3),
          ),
          WorkDayEvent.restOffered(
            _at(9, 30),
            RestKind.short,
            plannedDuration: const Duration(minutes: 3),
          ),
        ],
      );
    });

    test(
      'после двух отложений подряд остаются только «начать» и «пропустить»',
      () {
        offerFirstRest();
        expect(engine.postponeRest(_at(9, 25)), isA<WorkDayCommandAccepted>());
        engine.snapshot(_at(9, 30));
        expect(engine.postponeRest(_at(9, 30)), isA<WorkDayCommandAccepted>());

        final postponed = engine.snapshot(_at(9, 30));
        expect(postponed.phase, WorkDayPhase.running);
        expect(postponed.nextRestAt, _at(9, 35));
        expect(postponed.untilNextRest, const Duration(minutes: 5));
        expect(postponed.remainingPostponements, 0);

        final offered = engine.snapshot(_at(9, 35));
        expect(offered.phase, WorkDayPhase.restOffered);
        expect(offered.remainingPostponements, 0);
        expect(offered.availableCommands, [
          WorkDayCommand.startRest,
          WorkDayCommand.skipRest,
          WorkDayCommand.pause,
          WorkDayCommand.finish,
          WorkDayCommand.startMeal,
        ]);
      },
    );

    test('третье отложение подряд отклоняется и не меняет состояние', () {
      postponeTwice();

      expect(
        (engine.postponeRest(_at(9, 36)) as WorkDayCommandRejected).reason,
        RejectionReason.postponeLimitReached,
      );
      final after = engine.snapshot(_at(9, 36));

      expect(after.phase, WorkDayPhase.restOffered);
      expect(after.worked, const Duration(minutes: 36));
      expect(after.nextRestAt, isNull);
      expect(after.untilNextRest, Duration.zero);
      expect(after.remainingPostponements, 0);
      expect(
        after.events.where(
          (event) => event.type == WorkDayEventType.restPostponed,
        ),
        hasLength(2),
      );
      expect(
        after.events.last,
        WorkDayEvent.restOffered(
          _at(9, 35),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
      );
    });
  });

  group('сброс счётчика отложений', () {
    test('счётчик сбрасывается, когда отдых начался', () {
      postponeTwice();

      expect(engine.startRest(_at(9, 35)), isA<WorkDayCommandAccepted>());
      final started = engine.snapshot(_at(9, 35));

      expect(started.phase, WorkDayPhase.resting);
      expect(started.remainingPostponements, 2);

      final finished = engine.snapshot(_at(9, 38));

      expect(finished.phase, WorkDayPhase.running);
      expect(finished.remainingPostponements, 2);
      expect(finished.nextRestAt, _at(10, 3));

      final offeredAgain = engine.snapshot(_at(10, 3));

      expect(offeredAgain.phase, WorkDayPhase.restOffered);
      expect(offeredAgain.remainingPostponements, 2);
      expect(engine.postponeRest(_at(10, 3)), isA<WorkDayCommandAccepted>());
    });

    test('счётчик сбрасывается, когда отдых пропущен', () {
      postponeTwice();

      expect(engine.skipRest(_at(9, 35)), isA<WorkDayCommandAccepted>());
      final skipped = engine.snapshot(_at(9, 35));

      expect(skipped.phase, WorkDayPhase.running);
      expect(skipped.remainingPostponements, 2);
      expect(skipped.nextRestAt, _at(10));

      final offered = engine.snapshot(_at(10));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.remainingPostponements, 2);
      expect(engine.postponeRest(_at(10)), isA<WorkDayCommandAccepted>());
      expect(
        engine.snapshot(_at(10)).remainingPostponements,
        1,
        reason: 'после сброса лимит снова полный',
      );
    });

    test('счётчик сбрасывается при досрочном завершении отдыха', () {
      postponeTwice();

      expect(engine.startRest(_at(9, 35)), isA<WorkDayCommandAccepted>());
      expect(engine.finishRest(_at(9, 36)), isA<WorkDayCommandAccepted>());

      final early = engine.snapshot(_at(9, 36));

      expect(early.phase, WorkDayPhase.running);
      expect(early.remainingPostponements, 2);
      expect(early.nextRestAt, _at(10, 1));

      final offered = engine.snapshot(_at(10, 1));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.remainingPostponements, 2);
      expect(engine.postponeRest(_at(10, 1)), isA<WorkDayCommandAccepted>());
      expect(engine.snapshot(_at(10, 1)).remainingPostponements, 1);
    });

    test('счётчик сбрасывается при завершении рабочего дня', () {
      postponeTwice();

      expect(engine.finishWorkDay(_at(9, 36)), isA<WorkDayCommandAccepted>());
      expect(engine.snapshot(_at(9, 36)).remainingPostponements, 2);

      expect(engine.startWorkDay(_at(9, 40)), isA<WorkDayCommandAccepted>());

      final newDay = engine.snapshot(_at(10, 5));

      expect(newDay.phase, WorkDayPhase.restOffered);
      expect(newDay.remainingPostponements, 2);
      expect(engine.postponeRest(_at(10, 5)), isA<WorkDayCommandAccepted>());
      expect(engine.postponeRest(_at(10, 10)), isA<WorkDayCommandAccepted>());
      expect(engine.snapshot(_at(10, 15)).remainingPostponements, 0);
    });
  });

  group('отложение и пауза', () {
    test('на паузе отложение недоступно и не тратит попытку', () {
      offerFirstRest();
      engine.pause(_at(9, 26));

      expect(
        (engine.postponeRest(_at(9, 27)) as WorkDayCommandRejected).reason,
        RejectionReason.restNotOffered,
      );
      final paused = engine.snapshot(_at(9, 40));

      expect(paused.phase, WorkDayPhase.paused);
      expect(paused.restKind, RestKind.short);
      expect(paused.remainingPostponements, 2);
      expect(paused.availableCommands, [
        WorkDayCommand.resume,
        WorkDayCommand.finish,
      ]);

      expect(engine.resume(_at(9, 40)), isA<WorkDayCommandAccepted>());
      final resumed = engine.snapshot(_at(9, 40));

      expect(resumed.phase, WorkDayPhase.restOffered);
      expect(resumed.remainingPostponements, 2);
      expect(resumed.availableCommands, contains(WorkDayCommand.postponeRest));

      expect(engine.postponeRest(_at(9, 40)), isA<WorkDayCommandAccepted>());
      final postponed = engine.snapshot(_at(9, 40));

      expect(postponed.nextRestAt, _at(9, 45));
      expect(postponed.remainingPostponements, 1);
    });

    test('пауза сдвигает отложенное предложение вместе с ритмом', () {
      offerFirstRest();
      engine.postponeRest(_at(9, 25));
      engine.pause(_at(9, 26));

      final paused = engine.snapshot(_at(9, 40));

      expect(paused.phase, WorkDayPhase.paused);
      expect(paused.nextRestAt, _at(9, 30));
      expect(paused.untilNextRest, const Duration(minutes: 4));

      expect(engine.resume(_at(9, 40)), isA<WorkDayCommandAccepted>());
      final resumed = engine.snapshot(_at(9, 40));

      expect(resumed.phase, WorkDayPhase.running);
      expect(resumed.worked, const Duration(minutes: 26));
      expect(resumed.nextRestAt, _at(9, 44));
      expect(resumed.untilNextRest, const Duration(minutes: 4));
      expect(resumed.remainingPostponements, 1);

      expect(engine.snapshot(_at(9, 44)).phase, WorkDayPhase.restOffered);
    });
  });

  group('отложение и конец рабочего окна', () {
    test('отложенное предложение за концом окна не предлагается', () {
      engine.startWorkDay(_at(17, 30));

      expect(engine.snapshot(_at(17, 55)).phase, WorkDayPhase.restOffered);
      expect(engine.postponeRest(_at(17, 55)), isA<WorkDayCommandAccepted>());
      final postponed = engine.snapshot(_at(17, 55));

      expect(postponed.phase, WorkDayPhase.running);
      expect(postponed.nextRestAt, isNull);
      expect(postponed.untilNextRest, isNull);
      expect(postponed.remainingPostponements, 1);

      expect(engine.snapshot(_at(17, 59)).phase, WorkDayPhase.running);

      final closed = engine.snapshot(_at(18));

      expect(closed.phase, WorkDayPhase.finished);
      expect(closed.finishedAt, _at(18));
      expect(closed.worked, const Duration(minutes: 30));
      expect(closed.restKind, isNull);
      expect(closed.remainingPostponements, 2);
      expect(closed.events, [
        WorkDayEvent.started(_at(17, 30)),
        WorkDayEvent.restOffered(
          _at(17, 55),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
        WorkDayEvent.restPostponed(
          _at(17, 55),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
        WorkDayEvent.finished(_at(18), WorkDayFinishReason.workWindowEnded),
      ]);
      expect(
        (engine.postponeRest(_at(18)) as WorkDayCommandRejected).reason,
        RejectionReason.restNotOffered,
      );
    });
  });

  group('отказ отложению', () {
    test('без предложения отложение отклоняется', () {
      expect(
        (engine.postponeRest(_at(9)) as WorkDayCommandRejected).reason,
        RejectionReason.restNotOffered,
      );

      engine.startWorkDay(_at(9));

      expect(
        (engine.postponeRest(_at(9, 10)) as WorkDayCommandRejected).reason,
        RejectionReason.restNotOffered,
      );
      final after = engine.snapshot(_at(9, 10));

      expect(after.phase, WorkDayPhase.running);
      expect(after.remainingPostponements, 2);
      expect(after.nextRestAt, _at(9, 25));
    });

    test('во время отдыха отложение отклоняется', () {
      offerFirstRest();
      engine.startRest(_at(9, 25));

      expect(
        (engine.postponeRest(_at(9, 26)) as WorkDayCommandRejected).reason,
        RejectionReason.restInProgress,
      );
      final duringRest = engine.snapshot(_at(9, 26));

      expect(duringRest.phase, WorkDayPhase.resting);
      expect(duringRest.remainingPostponements, 2);
      expect(duringRest.remainingRest, const Duration(minutes: 2));
    });
  });
}
