import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

/// Движок с коротким ритмом и рабочим окном на все сутки: тесты набора
/// упражнений проходят много отдыхов и не должны упираться в конец окна.
WorkDayEngine _engine() => WorkDayEngine(
  window: WorkWindow(
    start: const ClockTime(0, 0),
    end: const ClockTime(23, 59),
  ),
  shortRestInterval: const Duration(minutes: 1),
  shortRestDuration: const Duration(seconds: 20),
  longRestInterval: const Duration(hours: 12),
);

void main() {
  group('набор упражнений', () {
    test('набор поставляется с приложением: 25–40 упражнений', () {
      expect(exerciseCatalog.length, inInclusiveRange(25, 40));
    });

    test('у упражнения есть название, описание, длительность и категория', () {
      for (final exercise in exerciseCatalog) {
        expect(exercise.id, isNotEmpty);
        expect(exercise.name.trim(), isNotEmpty);
        expect(exercise.description.trim(), isNotEmpty);
        expect(exercise.duration, greaterThan(Duration.zero));
      }
    });

    test('в наборе есть упражнения всех трёх категорий', () {
      final categories = exerciseCatalog
          .map((exercise) => exercise.category)
          .toSet();

      expect(categories, ExerciseCategory.values.toSet());
    });

    test('идентификаторы упражнений уникальны', () {
      final ids = exerciseCatalog.map((exercise) => exercise.id).toSet();

      expect(ids, hasLength(exerciseCatalog.length));
    });
  });

  group('выбор упражнения на коротком отдыхе', () {
    test('короткий отдых показывает ровно одно упражнение из набора', () {
      final engine = _engine();
      var now = DateTime(2026, 3, 4);
      engine.startWorkDay(now);
      now = now.add(const Duration(minutes: 1));
      engine.snapshot(now);
      engine.startRest(now);

      final snapshot = engine.snapshot(now);

      expect(snapshot.phase, WorkDayPhase.resting);
      expect(snapshot.exercises, hasLength(1));
      expect(exerciseCatalog, contains(snapshot.exercises.single));
    });

    test('вне отдыха упражнений нет', () {
      final engine = _engine();
      var now = DateTime(2026, 3, 4);
      engine.startWorkDay(now);

      expect(engine.snapshot(now).exercises, isEmpty);

      now = now.add(const Duration(minutes: 1));
      expect(engine.snapshot(now).phase, WorkDayPhase.restOffered);
      expect(engine.snapshot(now).exercises, isEmpty);

      engine.startRest(now);
      engine.finishRest(now);

      expect(engine.snapshot(now).phase, WorkDayPhase.running);
      expect(engine.snapshot(now).exercises, isEmpty);
    });

    test('упражнения идут по кругу: каждый отдых берёт следующее', () {
      final engine = _engine();
      var now = DateTime(2026, 3, 4);
      engine.startWorkDay(now);

      final shown = <Exercise>[];
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(minutes: 1));
        engine.snapshot(now);
        engine.startRest(now);
        shown.add(engine.snapshot(now).exercises.single);
        engine.finishRest(now);
      }

      expect(shown, exerciseCatalog.take(3));
    });

    test('после конца набора круг начинается заново', () {
      final engine = _engine();
      var now = DateTime(2026, 3, 4);
      engine.startWorkDay(now);

      final shown = <Exercise>[];
      for (var i = 0; i <= exerciseCatalog.length; i++) {
        now = now.add(const Duration(minutes: 1));
        engine.snapshot(now);
        engine.startRest(now);
        shown.add(engine.snapshot(now).exercises.single);
        engine.finishRest(now);
      }

      expect(shown.sublist(0, exerciseCatalog.length), exerciseCatalog);
      expect(shown.last, exerciseCatalog.first);
    });

    test('упражнение не повторяет упражнение предыдущего отдыха', () {
      final engine = _engine();
      var now = DateTime(2026, 3, 4);
      engine.startWorkDay(now);

      Exercise nextExercise() {
        now = now.add(const Duration(minutes: 1));
        engine.snapshot(now);
        engine.startRest(now);
        final exercise = engine.snapshot(now).exercises.single;
        engine.finishRest(now);
        return exercise;
      }

      Exercise? previous;
      for (var i = 0; i < exerciseCatalog.length; i++) {
        final exercise = nextExercise();
        expect(exercise, isNot(previous), reason: 'отдых $i повторил прошлое');
        previous = exercise;
      }
    });

    test('пропущенный отдых не расходует упражнение', () {
      final engine = _engine();
      var now = DateTime(2026, 3, 4);
      engine.startWorkDay(now);

      now = now.add(const Duration(minutes: 1));
      engine.snapshot(now);
      engine.skipRest(now);

      now = now.add(const Duration(minutes: 1));
      engine.snapshot(now);
      engine.startRest(now);

      expect(engine.snapshot(now).exercises.single, exerciseCatalog.first);
    });
  });
}
