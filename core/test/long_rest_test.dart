import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

DateTime _at(int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 3, 4, hour, minute, second);

/// Движок, в котором короткие отдыхи не мешают проверять длинный.
WorkDayEngine _longOnlyEngine() => WorkDayEngine(
  settings: RhythmSettings(shortRestInterval: const Duration(hours: 12)),
);

Exercise _exercise(String id, ExerciseCategory category) => Exercise(
  id: id,
  name: id,
  description: id,
  duration: const Duration(seconds: 30),
  category: category,
);

void main() {
  group('предложение длинного отдыха', () {
    test('через 90 минут работы предлагается длинный отдых на 10 минут', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(9));

      final before = engine.snapshot(_at(10, 29, 59));
      expect(before.phase, WorkDayPhase.running);
      expect(before.untilNextRest, const Duration(seconds: 1));
      expect(before.restKind, isNull);
      expect(before.restDuration, isNull);

      final offered = engine.snapshot(_at(10, 30));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.long);
      expect(offered.restDuration, const Duration(minutes: 10));
      expect(offered.untilNextRest, Duration.zero);
      expect(offered.nextRestAt, isNull);
      expect(
        offered.events.last,
        WorkDayEvent.restOffered(_at(10, 30), RestKind.long),
      );
    });

    test('длинный отдых идёт 10 минут и показывает два упражнения', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(10, 30));

      expect(engine.startRest(_at(10, 30)), isA<WorkDayCommandAccepted>());
      final started = engine.snapshot(_at(10, 30));

      expect(started.phase, WorkDayPhase.resting);
      expect(started.restKind, RestKind.long);
      expect(started.restDuration, const Duration(minutes: 10));
      expect(started.remainingRest, const Duration(minutes: 10));
      expect(started.exercises, hasLength(2));
      expect(
        started.events.last,
        WorkDayEvent.restStarted(_at(10, 30), RestKind.long),
      );
    });

    test('длинный отдых завершается сам и сбрасывает свой счётчик', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(10, 30));
      engine.startRest(_at(10, 30));

      final afterRest = engine.snapshot(_at(10, 40));

      expect(afterRest.phase, WorkDayPhase.running);
      expect(afterRest.restKind, isNull);
      expect(afterRest.nextRestAt, _at(12, 10));
      expect(
        afterRest.lastRestFinished,
        WorkDayEvent.restFinished(
          _at(10, 40),
          RestKind.long,
          plannedDuration: const Duration(minutes: 10),
          actualDuration: const Duration(minutes: 10),
        ),
      );
    });

    test('длинный отдых за концом рабочего окна не предлагается', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(16, 40));

      final before = engine.snapshot(_at(17, 30));

      expect(before.phase, WorkDayPhase.running);
      expect(before.nextRestAt, isNull);
      expect(before.untilNextRest, isNull);

      final atWindowEnd = engine.snapshot(_at(18));

      expect(atWindowEnd.phase, WorkDayPhase.finished);
      expect(
        atWindowEnd.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        isEmpty,
      );
    });
  });

  group('приоритет длинного отдыха над коротким', () {
    test('при совпадении моментов предлагается только длинный', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(minutes: 25),
          longRestInterval: const Duration(minutes: 50),
        ),
      )..startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      expect(engine.skipRest(_at(9, 25)), isA<WorkDayCommandAccepted>());

      final offered = engine.snapshot(_at(9, 50));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.long);
      expect(
        offered.events
            .where((event) => event.type == WorkDayEventType.restOffered)
            .toList(),
        [
          WorkDayEvent.restOffered(_at(9, 25), RestKind.short),
          WorkDayEvent.restOffered(_at(9, 50), RestKind.long),
        ],
      );
    });

    test('длинный отдых раньше короткого прерывает ожидание короткого', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(minutes: 25),
          longRestInterval: const Duration(minutes: 20),
        ),
      )..startWorkDay(_at(9));

      final offered = engine.snapshot(_at(9, 26));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.long);
      expect(
        offered.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        [WorkDayEvent.restOffered(_at(9, 20), RestKind.long)],
      );
    });

    test('короткий отдых не сбрасывает счётчик длинного', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));

      engine.snapshot(_at(9, 25));
      engine.skipRest(_at(9, 25));
      engine.snapshot(_at(9, 50));
      engine.skipRest(_at(9, 50));
      engine.snapshot(_at(10, 15));
      engine.skipRest(_at(10, 15));

      final offered = engine.snapshot(_at(10, 30));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.long);
      expect(
        offered.events.last,
        WorkDayEvent.restOffered(_at(10, 30), RestKind.long),
      );
    });

    test('досрочно завершённый короткий отдых тоже не сбрасывает длинный', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));
      engine.finishRest(_at(9, 26));

      engine.snapshot(_at(9, 51));
      engine.skipRest(_at(9, 51));
      engine.snapshot(_at(10, 16));
      engine.skipRest(_at(10, 16));

      // Короткий отдых внёс в счёт длинного только свою минуту: 9:00 + 90 мин
      // + 1 мин отдыха.
      final offered = engine.snapshot(_at(10, 31));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.long);
      expect(
        offered.events.last,
        WorkDayEvent.restOffered(_at(10, 31), RestKind.long),
      );
    });

    test('отложенный длинный отдых остаётся длинным', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(10, 30));

      expect(engine.postponeRest(_at(10, 30)), isA<WorkDayCommandAccepted>());
      final postponed = engine.snapshot(_at(10, 30));
      expect(postponed.phase, WorkDayPhase.running);
      expect(postponed.nextRestAt, _at(10, 35));
      expect(postponed.remainingPostponements, 1);
      expect(
        postponed.events.last,
        WorkDayEvent.restPostponed(_at(10, 30), RestKind.long),
      );

      final offeredAgain = engine.snapshot(_at(10, 35));
      expect(offeredAgain.restKind, RestKind.long);
      expect(engine.postponeRest(_at(10, 35)), isA<WorkDayCommandAccepted>());

      final afterLimit = engine.snapshot(_at(10, 40));
      expect(afterLimit.restKind, RestKind.long);
      expect(afterLimit.remainingPostponements, 0);

      expect(engine.startRest(_at(10, 40)), isA<WorkDayCommandAccepted>());
      expect(engine.snapshot(_at(10, 40)).exercises, hasLength(2));
    });
  });

  group('пропуск длинного отдыха', () {
    test('пропуск не создаёт долг и не предлагает тот же отдых сразу', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(10, 30));

      expect(engine.skipRest(_at(10, 35)), isA<WorkDayCommandAccepted>());
      final skipped = engine.snapshot(_at(10, 35));

      expect(skipped.phase, WorkDayPhase.running);
      expect(skipped.restKind, isNull);
      expect(
        skipped.events.last,
        WorkDayEvent.restSkipped(_at(10, 35), RestKind.long),
      );
      expect(engine.snapshot(_at(10, 36)).phase, WorkDayPhase.running);
      expect(engine.snapshot(_at(11, 59)).phase, WorkDayPhase.running);
    });

    test('счётчик длинного отдыха при пропуске не начинается заново', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(10, 30));
      engine.skipRest(_at(10, 35));

      // Отсчёт идёт от плановой точки 10:30, а не от момента пропуска: иначе
      // следующий длинный отдых был бы в 12:05.
      final skipped = engine.snapshot(_at(10, 35));

      expect(skipped.nextRestAt, _at(12));
      expect(skipped.untilNextRest, const Duration(minutes: 85));

      final offered = engine.snapshot(_at(12));

      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.long);
    });
  });

  group('пауза и длинный отдых', () {
    test('пауза сдвигает момент длинного отдыха на её длительность', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(9));

      engine.pause(_at(9, 30));
      expect(engine.resume(_at(10)), isA<WorkDayCommandAccepted>());

      final resumed = engine.snapshot(_at(10));

      expect(resumed.phase, WorkDayPhase.running);
      expect(resumed.nextRestAt, _at(11));
      expect(resumed.untilNextRest, const Duration(hours: 1));
    });
  });

  group('досрочное завершение длинного отдыха', () {
    test('сбрасывает счётчик длинного отдыха', () {
      final engine = _longOnlyEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(10, 30));
      engine.startRest(_at(10, 30));

      expect(engine.finishRest(_at(10, 35)), isA<WorkDayCommandAccepted>());
      final early = engine.snapshot(_at(10, 35));

      expect(early.phase, WorkDayPhase.running);
      expect(early.nextRestAt, _at(12, 5));
      expect(
        early.lastRestFinished,
        WorkDayEvent.restFinished(
          _at(10, 35),
          RestKind.long,
          restFinishReason: RestFinishReason.early,
          plannedDuration: const Duration(minutes: 10),
          actualDuration: const Duration(minutes: 5),
        ),
      );
      expect(engine.snapshot(_at(11)).phase, WorkDayPhase.running);
    });
  });

  group('упражнения длинного отдыха', () {
    test('два упражнения из разных категорий, без повтора предыдущего', () {
      final engine = WorkDayEngine();
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));
      final shortExercise = engine.snapshot(_at(9, 25)).exercises.single;
      engine.finishRest(_at(9, 28));

      engine.snapshot(_at(9, 53));
      engine.skipRest(_at(9, 53));
      engine.snapshot(_at(10, 18));
      engine.skipRest(_at(10, 18));
      engine.snapshot(_at(10, 33));
      engine.startRest(_at(10, 33));

      final exercises = engine.snapshot(_at(10, 33)).exercises;

      expect(exercises, hasLength(2));
      expect(exercises.first, isNot(shortExercise));
      expect(exercises.first.category, isNot(exercises.last.category));
      expect(exerciseCatalog, containsAll(exercises));
    });

    test('пара набирается из разных категорий по кругу детерминированно', () {
      final catalog = [
        _exercise('eyes-one', ExerciseCategory.eyes),
        _exercise('eyes-two', ExerciseCategory.eyes),
        _exercise('hands-one', ExerciseCategory.hands),
      ];
      List<String> longRestPair() {
        final engine = WorkDayEngine(
          settings: RhythmSettings(
            shortRestInterval: const Duration(hours: 12),
          ),
          catalog: catalog,
        )..startWorkDay(_at(9));
        engine.snapshot(_at(10, 30));
        engine.startRest(_at(10, 30));
        return engine
            .snapshot(_at(10, 30))
            .exercises
            .map((exercise) => exercise.id)
            .toList();
      }

      // Второе упражнение той же категории пропускается, выбор повторяем.
      expect(longRestPair(), ['eyes-one', 'hands-one']);
      expect(longRestPair(), ['eyes-one', 'hands-one']);
    });
  });
}
