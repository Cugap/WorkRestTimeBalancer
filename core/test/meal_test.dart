import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

DateTime _at(int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 3, 4, hour, minute, second);

/// Движок, в котором повторяющиеся отдыхи не мешают проверять обед.
WorkDayEngine _mealOnlyEngine({
  ClockTime mealStart = const ClockTime(13, 0),
  WorkWindow window = WorkWindow.standard,
}) => WorkDayEngine(
  settings: RhythmSettings(
    workStart: window.start,
    workEnd: window.end,
    mealStart: mealStart,
    shortRestInterval: const Duration(hours: 12),
    longRestInterval: const Duration(hours: 12),
  ),
);

void main() {
  group('предложение обеда', () {
    test('в 13:00 предлагается обед на 60 минут', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));

      final before = engine.snapshot(_at(12, 59, 59));
      expect(before.phase, WorkDayPhase.running);
      expect(before.restKind, isNull);
      expect(before.untilNextRest, const Duration(seconds: 1));

      final offered = engine.snapshot(_at(13));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.meal);
      expect(offered.restDuration, const Duration(minutes: 60));
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
        WorkDayEvent.restOffered(_at(13), RestKind.meal),
      );
    });

    test('обед не считается длинным отдыхом ни в снимке, ни в журнале', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(13));

      expect(engine.startRest(_at(13)), isA<WorkDayCommandAccepted>());
      final started = engine.snapshot(_at(13));
      expect(started.restKind, RestKind.meal);
      expect(started.restKind, isNot(RestKind.long));

      final afterRest = engine.snapshot(_at(14));
      expect(afterRest.phase, WorkDayPhase.running);
      expect(
        afterRest.lastRestFinished,
        WorkDayEvent.restFinished(
          _at(14),
          RestKind.meal,
          plannedDuration: const Duration(minutes: 60),
          actualDuration: const Duration(minutes: 60),
        ),
      );
      expect(
        afterRest.events
            .where((event) => event.type == WorkDayEventType.restFinished)
            .single
            .restKind,
        RestKind.meal,
      );
    });

    test('обед показывает три упражнения — по одному из каждой категории', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(13));
      engine.startRest(_at(13));

      final exercises = engine.snapshot(_at(13)).exercises;

      expect(exercises, hasLength(3));
      expect(
        exercises.map((exercise) => exercise.category).toSet(),
        ExerciseCategory.values.toSet(),
      );
      expect(exercises.map((exercise) => exercise.id).toSet(), hasLength(3));
    });

    test('выбор упражнений обеда детерминирован', () {
      List<String> firstRun() {
        final engine = _mealOnlyEngine()..startWorkDay(_at(9));
        engine.snapshot(_at(13));
        engine.startRest(_at(13));
        return engine
            .snapshot(_at(13))
            .exercises
            .map((exercise) => exercise.id)
            .toList();
      }

      expect(firstRun(), firstRun());
    });

    test('обед не повторяет упражнение предыдущего отдыха', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(minutes: 25),
          longRestInterval: const Duration(hours: 12),
        ),
      )..startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));
      final previous = engine.snapshot(_at(9, 25)).exercises.single;
      engine.finishRest(_at(9, 26));

      expect(engine.startMeal(_at(9, 30)), isA<WorkDayCommandAccepted>());
      final exercises = engine.snapshot(_at(9, 30)).exercises;

      expect(exercises, hasLength(3));
      expect(exercises, isNot(contains(previous)));
      expect(
        exercises.map((exercise) => exercise.category).toSet(),
        ExerciseCategory.values.toSet(),
      );
    });

    test('обед, момент которого совпадает с коротким отдыхом, выигрывает', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(hours: 4),
          longRestInterval: const Duration(hours: 12),
        ),
      )..startWorkDay(_at(9));

      final offered = engine.snapshot(_at(13));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.meal);
      expect(
        offered.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        [WorkDayEvent.restOffered(_at(13), RestKind.meal)],
      );

      engine.startRest(_at(13));
      final afterMeal = engine.snapshot(_at(14));

      expect(afterMeal.phase, WorkDayPhase.running);
      expect(afterMeal.restKind, isNull);
      // Оба счётчика начались заново от конца обеда: короткий в 18:00 уже не
      // предлагается.
      expect(afterMeal.nextRestAt, isNull);
    });

    test('обед, момент которого совпадает с длинным отдыхом, выигрывает', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(hours: 12),
          longRestInterval: const Duration(hours: 4),
        ),
      )..startWorkDay(_at(9));

      final offered = engine.snapshot(_at(13));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.meal);

      engine.startRest(_at(13));
      final afterMeal = engine.snapshot(_at(14));

      expect(afterMeal.phase, WorkDayPhase.running);
      expect(afterMeal.restKind, isNull);
      expect(afterMeal.nextRestAt, isNull);
    });

    test('обед за концом рабочего окна не предлагается', () {
      final engine = _mealOnlyEngine(
        mealStart: const ClockTime(13, 0),
        window: WorkWindow(
          start: const ClockTime(9, 0),
          end: const ClockTime(12, 0),
        ),
      )..startWorkDay(_at(9));

      final beforeEnd = engine.snapshot(_at(11, 59));
      expect(beforeEnd.phase, WorkDayPhase.running);
      expect(beforeEnd.nextRestAt, isNull);

      final finished = engine.snapshot(_at(12));
      expect(finished.phase, WorkDayPhase.finished);
      expect(
        finished.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        isEmpty,
      );
    });

    test('обед ровно на конце окна тоже не предлагается', () {
      final engine = _mealOnlyEngine(
        mealStart: const ClockTime(12, 0),
        window: WorkWindow(
          start: const ClockTime(9, 0),
          end: const ClockTime(12, 0),
        ),
      )..startWorkDay(_at(9));

      expect(engine.snapshot(_at(11, 59)).nextRestAt, isNull);
      expect(engine.snapshot(_at(12)).phase, WorkDayPhase.finished);
    });

    test('предложение обеда приходит один раз за рабочий день', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));

      engine.snapshot(_at(13));
      engine.skipRest(_at(13));

      final later = engine.snapshot(_at(17));
      expect(later.phase, WorkDayPhase.running);
      expect(later.restKind, isNull);
      expect(
        later.events.where(
          (event) =>
              event.type == WorkDayEventType.restOffered &&
              event.restKind == RestKind.meal,
        ),
        hasLength(1),
      );
    });

    test('новый рабочий день снова делает обед доступным', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));
      engine.startMeal(_at(10));
      engine.finishRest(_at(10, 30));
      engine.finishWorkDay(_at(10, 40));

      expect(engine.startWorkDay(_at(12, 30)), isA<WorkDayCommandAccepted>());
      final offered = engine.snapshot(_at(13));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.meal);
      expect(offered.availableCommands, contains(WorkDayCommand.startRest));
    });

    test('обед, время которого прошло к старту дня, ждёт ручного старта', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(14));

      final snapshot = engine.snapshot(_at(14));
      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.restKind, isNull);
      expect(snapshot.availableCommands, contains(WorkDayCommand.startMeal));

      expect(engine.startMeal(_at(14, 5)), isA<WorkDayCommandAccepted>());
      expect(engine.snapshot(_at(14, 5)).restKind, RestKind.meal);
    });
  });

  group('ручной старт обеда', () {
    test('обед можно начать до 13:00, и он считается состоявшимся', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));

      expect(engine.snapshot(_at(10)).availableCommands, [
        WorkDayCommand.pause,
        WorkDayCommand.finish,
        WorkDayCommand.startMeal,
      ]);

      expect(engine.startMeal(_at(10)), isA<WorkDayCommandAccepted>());
      final started = engine.snapshot(_at(10));

      expect(started.phase, WorkDayPhase.resting);
      expect(started.restKind, RestKind.meal);
      expect(started.restDuration, const Duration(minutes: 60));
      expect(started.remainingRest, const Duration(minutes: 60));
      expect(started.exercises, hasLength(3));
      expect(
        started.events.last,
        WorkDayEvent.restStarted(_at(10), RestKind.meal),
      );

      engine.finishRest(_at(10, 30));
      final atMealTime = engine.snapshot(_at(13));

      expect(atMealTime.phase, WorkDayPhase.running);
      expect(atMealTime.restKind, isNull);
      expect(
        atMealTime.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        isEmpty,
      );
      expect(
        atMealTime.availableCommands,
        isNot(contains(WorkDayCommand.startMeal)),
      );
    });

    test('ручной обед сбрасывает счётчики короткого и длинного отдыха', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(minutes: 25),
          longRestInterval: const Duration(minutes: 45),
        ),
      )..startWorkDay(_at(9));

      engine.startMeal(_at(10));
      engine.finishRest(_at(10, 30));

      final afterMeal = engine.snapshot(_at(10, 30));
      expect(afterMeal.nextRestAt, _at(10, 55));
      expect(afterMeal.untilNextRest, const Duration(minutes: 25));

      engine.snapshot(_at(10, 55));
      engine.skipRest(_at(10, 55));

      final longOffered = engine.snapshot(_at(11, 15));
      expect(longOffered.phase, WorkDayPhase.restOffered);
      expect(longOffered.restKind, RestKind.long);
    });

    test('обед вытесняет предложенный короткий отдых', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(minutes: 25),
          longRestInterval: const Duration(hours: 12),
        ),
      )..startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));

      expect(engine.startMeal(_at(9, 26)), isA<WorkDayCommandAccepted>());
      final started = engine.snapshot(_at(9, 26));

      expect(started.phase, WorkDayPhase.resting);
      expect(started.restKind, RestKind.meal);

      engine.finishRest(_at(10));
      final afterMeal = engine.snapshot(_at(10));

      expect(afterMeal.phase, WorkDayPhase.running);
      expect(afterMeal.nextRestAt, _at(10, 25));
    });

    test('начать обед можно и из предложения о самом обеде', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(13));

      expect(engine.startMeal(_at(13)), isA<WorkDayCommandAccepted>());

      final started = engine.snapshot(_at(13));
      expect(started.phase, WorkDayPhase.resting);
      expect(started.restKind, RestKind.meal);
    });

    test('ручной старт обеда отклоняется с причиной и не меняет состояние', () {
      final engine = _mealOnlyEngine();

      expect(
        (engine.startMeal(_at(9)) as WorkDayCommandRejected).reason,
        RejectionReason.workDayNotStarted,
      );

      engine.startWorkDay(_at(9));
      engine.pause(_at(9, 10));
      expect(
        (engine.startMeal(_at(9, 20)) as WorkDayCommandRejected).reason,
        RejectionReason.workDayAlreadyPaused,
      );
      engine.resume(_at(9, 20));

      engine.startMeal(_at(9, 30));
      final duringMeal = engine.snapshot(_at(9, 30));
      expect(
        (engine.startMeal(_at(9, 31)) as WorkDayCommandRejected).reason,
        RejectionReason.restInProgress,
      );
      expect(engine.snapshot(_at(9, 31)).events, duringMeal.events);

      engine.finishRest(_at(9, 40));
      final afterMeal = engine.snapshot(_at(9, 40));
      expect(
        (engine.startMeal(_at(9, 41)) as WorkDayCommandRejected).reason,
        RejectionReason.mealAlreadyTaken,
      );
      expect(engine.snapshot(_at(9, 41)).events, afterMeal.events);

      engine.finishWorkDay(_at(9, 50));
      final finished = engine.snapshot(_at(9, 50));
      expect(
        (engine.startMeal(_at(9, 55)) as WorkDayCommandRejected).reason,
        RejectionReason.workDayAlreadyFinished,
      );
      expect(engine.snapshot(_at(9, 55)).events, finished.events);
    });
  });

  group('отложение и пропуск обеда', () {
    test('обед можно отложить дважды, третье отложение отклоняется', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(13));

      expect(engine.postponeRest(_at(13)), isA<WorkDayCommandAccepted>());
      final first = engine.snapshot(_at(13));
      expect(first.phase, WorkDayPhase.running);
      expect(first.nextRestAt, _at(13, 5));
      expect(first.remainingPostponements, 1);
      expect(
        first.events.last,
        WorkDayEvent.restPostponed(_at(13), RestKind.meal),
      );

      engine.snapshot(_at(13, 5));
      expect(engine.postponeRest(_at(13, 5)), isA<WorkDayCommandAccepted>());
      final second = engine.snapshot(_at(13, 5));
      expect(second.nextRestAt, _at(13, 10));
      expect(second.remainingPostponements, 0);

      final offered = engine.snapshot(_at(13, 10));
      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.meal);
      expect(offered.availableCommands, [
        WorkDayCommand.startRest,
        WorkDayCommand.skipRest,
        WorkDayCommand.pause,
        WorkDayCommand.finish,
      ]);

      final before = offered.events;
      expect(
        (engine.postponeRest(_at(13, 11)) as WorkDayCommandRejected).reason,
        RejectionReason.postponeLimitReached,
      );
      expect(engine.snapshot(_at(13, 11)).events, before);

      expect(engine.startRest(_at(13, 11)), isA<WorkDayCommandAccepted>());
      expect(engine.snapshot(_at(13, 11)).restKind, RestKind.meal);
    });

    test(
      'пропуск обеда ничего не переносит и не сбрасывает длинный счётчик',
      () {
        final engine = WorkDayEngine(
          settings: RhythmSettings(
            shortRestInterval: const Duration(hours: 12),
            longRestInterval: const Duration(minutes: 90),
          ),
        )..startWorkDay(_at(9));

        engine.snapshot(_at(10, 30));
        engine.skipRest(_at(10, 30));
        engine.snapshot(_at(12));
        engine.skipRest(_at(12));

        final offered = engine.snapshot(_at(13));
        expect(offered.phase, WorkDayPhase.restOffered);
        expect(offered.restKind, RestKind.meal);

        expect(engine.skipRest(_at(13, 1)), isA<WorkDayCommandAccepted>());
        final skipped = engine.snapshot(_at(13, 1));

        expect(skipped.phase, WorkDayPhase.running);
        expect(skipped.restKind, isNull);
        expect(skipped.nextRestAt, _at(13, 30));
        expect(
          skipped.events.last,
          WorkDayEvent.restSkipped(_at(13, 1), RestKind.meal),
        );

        final longOffered = engine.snapshot(_at(13, 30));
        expect(longOffered.phase, WorkDayPhase.restOffered);
        expect(longOffered.restKind, RestKind.long);
      },
    );

    test('отложенный обед не теряется, пока предлагается другой отдых', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(minutes: 25),
          longRestInterval: const Duration(hours: 12),
          mealStart: const ClockTime(9, 30),
        ),
      )..startWorkDay(_at(9));

      // Короткий отдых наступает раньше обеда и занимает единственное
      // предложение; обед ждёт своей очереди.
      final shortOffered = engine.snapshot(_at(9, 25));
      expect(shortOffered.phase, WorkDayPhase.restOffered);
      expect(shortOffered.restKind, RestKind.short);

      engine.skipRest(_at(9, 26));
      final mealOffered = engine.snapshot(_at(9, 30));

      expect(mealOffered.phase, WorkDayPhase.restOffered);
      expect(mealOffered.restKind, RestKind.meal);
      expect(
        mealOffered.events
            .where((event) => event.type == WorkDayEventType.restOffered)
            .last,
        WorkDayEvent.restOffered(_at(9, 30), RestKind.meal),
      );
    });
  });

  group('завершение обеда и журнал', () {
    test('обед доигрывает до конца и пишет план и факт в журнал', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(13));
      engine.startRest(_at(13));

      expect(engine.snapshot(_at(13, 59)).phase, WorkDayPhase.resting);
      expect(
        engine.snapshot(_at(13, 59)).remainingRest,
        const Duration(minutes: 1),
      );

      final finished = engine.snapshot(_at(14));

      expect(finished.phase, WorkDayPhase.running);
      expect(finished.remainingRest, isNull);
      expect(
        finished.lastRestFinished,
        WorkDayEvent.restFinished(
          _at(14),
          RestKind.meal,
          plannedDuration: const Duration(minutes: 60),
          actualDuration: const Duration(minutes: 60),
        ),
      );
    });

    test('досрочное завершение обеда сбрасывает оба счётчика', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(minutes: 25),
          longRestInterval: const Duration(minutes: 90),
        ),
      )..startWorkDay(_at(9));
      engine.startMeal(_at(10));

      engine.finishRest(_at(10, 20));
      final finished = engine.snapshot(_at(10, 20));

      expect(finished.phase, WorkDayPhase.running);
      expect(finished.nextRestAt, _at(10, 45));
      expect(finished.untilNextRest, const Duration(minutes: 25));
      expect(
        finished.lastRestFinished,
        WorkDayEvent.restFinished(
          _at(10, 20),
          RestKind.meal,
          restFinishReason: RestFinishReason.early,
          plannedDuration: const Duration(minutes: 60),
          actualDuration: const Duration(minutes: 20),
        ),
      );
    });
  });

  group('обед и пауза', () {
    test('обед, наступивший на паузе, ждёт возобновления', () {
      final engine = _mealOnlyEngine()..startWorkDay(_at(9));
      engine.pause(_at(12));

      final paused = engine.snapshot(_at(13));
      expect(paused.phase, WorkDayPhase.paused);
      expect(paused.restKind, isNull);

      engine.resume(_at(13, 10));
      final resumed = engine.snapshot(_at(13, 10));

      expect(resumed.phase, WorkDayPhase.restOffered);
      expect(resumed.restKind, RestKind.meal);
      expect(resumed.nextRestAt, isNull);
    });
  });
}
