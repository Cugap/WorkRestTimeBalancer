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
void _runScenario(List<Step> steps) {
  final engine = WorkDayEngine();

  for (final step in steps) {
    final now = _day(step.at);
    final result = switch (step.command) {
      WorkDayCommand.start => engine.startWorkDay(now),
      WorkDayCommand.pause => engine.pause(now),
      WorkDayCommand.resume => engine.resume(now),
      WorkDayCommand.finish => engine.finishWorkDay(now),
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

    final snapshot = engine.snapshot(now);
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
}
