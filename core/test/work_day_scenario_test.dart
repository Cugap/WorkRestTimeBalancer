import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

/// Шаг сценария: момент времени (от начала дня), команда и ожидаемое
/// наблюдаемое состояние после неё.
typedef Step = ({
  Duration at,
  WorkDayCommand? command,
  WorkDayPhase phase,
  Duration worked,
  RejectionReason? rejection,
});

DateTime _day(Duration offset) => DateTime(2026, 3, 4, 9).add(offset);

/// Проигрывает сценарий через публичный интерфейс ядра.
///
/// Интервал отдыха по умолчанию длиннее рабочего окна: сценарии про механику
/// дня не должны зависеть от ритма отдыха.
void _runScenario(List<Step> steps, {WorkDayEngine? engine}) {
  final day =
      engine ?? WorkDayEngine(shortRestInterval: const Duration(hours: 12));

  for (final step in steps) {
    final now = _day(step.at);
    final result = switch (step.command) {
      WorkDayCommand.start => day.startWorkDay(now),
      WorkDayCommand.pause => day.pause(now),
      WorkDayCommand.resume => day.resume(now),
      WorkDayCommand.finish => day.finishWorkDay(now),
      WorkDayCommand.startRest => day.startRest(now),
      WorkDayCommand.skipRest => day.skipRest(now),
      null => null,
    };

    if (step.command == null) {
      expect(
        step.rejection,
        isNull,
        reason: 'шаг без команды не может ждать отказа',
      );
    } else if (step.rejection == null) {
      expect(
        result,
        isA<WorkDayCommandAccepted>(),
        reason: 'команда на ${step.at}',
      );
    } else {
      expect(
        (result! as WorkDayCommandRejected).reason,
        step.rejection,
        reason: 'команда на ${step.at}',
      );
    }

    final snapshot = day.snapshot(now);
    expect(snapshot.phase, step.phase, reason: 'фаза на ${step.at}');
    expect(snapshot.worked, step.worked, reason: 'работа на ${step.at}');
  }
}

void main() {
  test('сценарий: день с паузой на обед и работой до конца окна', () {
    _runScenario([
      (
        at: Duration.zero,
        command: WorkDayCommand.start,
        phase: WorkDayPhase.running,
        worked: Duration.zero,
        rejection: null,
      ),
      (
        at: const Duration(hours: 1),
        command: WorkDayCommand.pause,
        phase: WorkDayPhase.paused,
        worked: const Duration(hours: 1),
        rejection: null,
      ),
      (
        at: const Duration(hours: 2),
        command: WorkDayCommand.resume,
        phase: WorkDayPhase.running,
        worked: const Duration(hours: 1),
        rejection: null,
      ),
      (
        at: const Duration(hours: 4),
        command: WorkDayCommand.finish,
        phase: WorkDayPhase.finished,
        worked: const Duration(hours: 3),
        rejection: null,
      ),
      (
        at: const Duration(hours: 5),
        command: WorkDayCommand.pause,
        phase: WorkDayPhase.finished,
        worked: const Duration(hours: 3),
        rejection: RejectionReason.workDayAlreadyFinished,
      ),
    ]);
  });

  test('сценарий: забыл завершить — день закрылся концом окна', () {
    _runScenario([
      (
        at: Duration.zero,
        command: WorkDayCommand.start,
        phase: WorkDayPhase.running,
        worked: Duration.zero,
        rejection: null,
      ),
      (
        at: const Duration(hours: 3, minutes: 30),
        command: null,
        phase: WorkDayPhase.running,
        worked: const Duration(hours: 3, minutes: 30),
        rejection: null,
      ),
      (
        at: const Duration(hours: 9),
        command: null,
        phase: WorkDayPhase.finished,
        worked: const Duration(hours: 9),
        rejection: null,
      ),
    ]);
  });

  test('сценарий: день в ритме коротких отдыхов', () {
    _runScenario([
      (
        at: Duration.zero,
        command: WorkDayCommand.start,
        phase: WorkDayPhase.running,
        worked: Duration.zero,
        rejection: null,
      ),
      (
        at: const Duration(minutes: 25),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 25),
        rejection: null,
      ),
      (
        at: const Duration(minutes: 25),
        command: WorkDayCommand.startRest,
        phase: WorkDayPhase.resting,
        worked: const Duration(minutes: 25),
        rejection: null,
      ),
      (
        at: const Duration(minutes: 28),
        command: null,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 25),
        rejection: null,
      ),
      (
        at: const Duration(minutes: 53),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 50),
        rejection: null,
      ),
      (
        at: const Duration(minutes: 54),
        command: WorkDayCommand.skipRest,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 51),
        rejection: null,
      ),
      (
        at: const Duration(hours: 1),
        command: WorkDayCommand.pause,
        phase: WorkDayPhase.paused,
        worked: const Duration(minutes: 57),
        rejection: null,
      ),
      (
        at: const Duration(hours: 1, minutes: 20),
        command: WorkDayCommand.resume,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 57),
        rejection: null,
      ),
      (
        at: const Duration(hours: 1, minutes: 39),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(hours: 1, minutes: 16),
        rejection: null,
      ),
      (
        at: const Duration(hours: 1, minutes: 39),
        command: WorkDayCommand.startRest,
        phase: WorkDayPhase.resting,
        worked: const Duration(hours: 1, minutes: 16),
        rejection: null,
      ),
      (
        at: const Duration(hours: 1, minutes: 42),
        command: null,
        phase: WorkDayPhase.running,
        worked: const Duration(hours: 1, minutes: 16),
        rejection: null,
      ),
      (
        at: const Duration(hours: 2, minutes: 7),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(hours: 1, minutes: 41),
        rejection: null,
      ),
      (
        at: const Duration(hours: 2, minutes: 8),
        command: WorkDayCommand.skipRest,
        phase: WorkDayPhase.running,
        worked: const Duration(hours: 1, minutes: 42),
        rejection: null,
      ),
      (
        at: const Duration(hours: 2, minutes: 33),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(hours: 2, minutes: 7),
        rejection: null,
      ),
    ], engine: WorkDayEngine());
  });
}
