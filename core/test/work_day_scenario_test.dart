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

WorkDayCommandResult? _dispatch(
  WorkDayEngine day,
  WorkDayCommand? command,
  DateTime now,
) => switch (command) {
  WorkDayCommand.start => day.startWorkDay(now),
  WorkDayCommand.pause => day.pause(now),
  WorkDayCommand.resume => day.resume(now),
  WorkDayCommand.finish => day.finishWorkDay(now),
  WorkDayCommand.startRest => day.startRest(now),
  WorkDayCommand.finishRest => day.finishRest(now),
  WorkDayCommand.skipRest => day.skipRest(now),
  WorkDayCommand.postponeRest => day.postponeRest(now),
  null => null,
};

/// Проигрывает сценарий через публичный интерфейс ядра.
///
/// Интервал отдыха по умолчанию длиннее рабочего окна: сценарии про механику
/// дня не должны зависеть от ритма отдыха.
void _runScenario(List<Step> steps, {WorkDayEngine? engine}) {
  final day =
      engine ?? WorkDayEngine(shortRestInterval: const Duration(hours: 12));

  for (final step in steps) {
    final now = _day(step.at);
    final result = _dispatch(day, step.command, now);

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

/// Шаг сценария отложений: к обычным ожиданиям добавляет остаток отложений и
/// момент возобновления предложения.
typedef PostponeStep = ({
  Duration at,
  WorkDayCommand? command,
  WorkDayPhase phase,
  Duration worked,
  RejectionReason? rejection,
  int remainingPostponements,
  DateTime? nextRestAt,
});

/// Проигрывает сценарий отложений на движке с настройками ритма по умолчанию.
void _runPostponeScenario(List<PostponeStep> steps) {
  final day = WorkDayEngine();

  for (final step in steps) {
    final now = _day(step.at);
    final result = _dispatch(day, step.command, now);

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
    expect(
      snapshot.remainingPostponements,
      step.remainingPostponements,
      reason: 'остаток отложений на ${step.at}',
    );
    expect(
      snapshot.nextRestAt,
      step.nextRestAt,
      reason: 'следующий отдых на ${step.at}',
    );
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

  test('сценарий: два отложения подряд, отказ третьему и сброс счётчика', () {
    _runPostponeScenario([
      (
        at: Duration.zero,
        command: WorkDayCommand.start,
        phase: WorkDayPhase.running,
        worked: Duration.zero,
        rejection: null,
        remainingPostponements: 2,
        nextRestAt: _day(const Duration(minutes: 25)),
      ),
      (
        at: const Duration(minutes: 25),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 25),
        rejection: null,
        remainingPostponements: 2,
        nextRestAt: null,
      ),
      (
        at: const Duration(minutes: 25),
        command: WorkDayCommand.postponeRest,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 25),
        rejection: null,
        remainingPostponements: 1,
        nextRestAt: _day(const Duration(minutes: 30)),
      ),
      (
        at: const Duration(minutes: 30),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 30),
        rejection: null,
        remainingPostponements: 1,
        nextRestAt: null,
      ),
      (
        at: const Duration(minutes: 30),
        command: WorkDayCommand.postponeRest,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 30),
        rejection: null,
        remainingPostponements: 0,
        nextRestAt: _day(const Duration(minutes: 35)),
      ),
      (
        at: const Duration(minutes: 35),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 35),
        rejection: null,
        remainingPostponements: 0,
        nextRestAt: null,
      ),
      (
        at: const Duration(minutes: 36),
        command: WorkDayCommand.postponeRest,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 36),
        rejection: RejectionReason.postponeLimitReached,
        remainingPostponements: 0,
        nextRestAt: null,
      ),
      (
        at: const Duration(minutes: 36),
        command: WorkDayCommand.skipRest,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 36),
        rejection: null,
        remainingPostponements: 2,
        nextRestAt: _day(const Duration(minutes: 61)),
      ),
      (
        at: const Duration(minutes: 61),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 61),
        rejection: null,
        remainingPostponements: 2,
        nextRestAt: null,
      ),
      (
        at: const Duration(minutes: 61),
        command: WorkDayCommand.startRest,
        phase: WorkDayPhase.resting,
        worked: const Duration(minutes: 61),
        rejection: null,
        remainingPostponements: 2,
        nextRestAt: null,
      ),
      (
        at: const Duration(minutes: 64),
        command: null,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 61),
        rejection: null,
        remainingPostponements: 2,
        nextRestAt: _day(const Duration(minutes: 89)),
      ),
      (
        at: const Duration(minutes: 89),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 86),
        rejection: null,
        remainingPostponements: 2,
        nextRestAt: null,
      ),
    ]);
  });

  test('сценарий: досрочное завершение отдыха продолжает ритм', () {
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
        at: const Duration(minutes: 27),
        command: WorkDayCommand.finishRest,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 25),
        rejection: null,
      ),
      (
        at: const Duration(minutes: 52),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 50),
        rejection: null,
      ),
      (
        at: const Duration(minutes: 52),
        command: WorkDayCommand.startRest,
        phase: WorkDayPhase.resting,
        worked: const Duration(minutes: 50),
        rejection: null,
      ),
      (
        at: const Duration(minutes: 53),
        command: WorkDayCommand.finishRest,
        phase: WorkDayPhase.running,
        worked: const Duration(minutes: 50),
        rejection: null,
      ),
      (
        at: const Duration(minutes: 78),
        command: null,
        phase: WorkDayPhase.restOffered,
        worked: const Duration(minutes: 75),
        rejection: null,
      ),
    ], engine: WorkDayEngine());
  });
}
