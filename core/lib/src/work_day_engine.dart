import 'work_day_command.dart';
import 'work_day_event.dart';
import 'work_day_snapshot.dart';
import 'work_window.dart';

/// Движок рабочего дня. Не читает системное время: каждый вызов получает момент
/// от оболочки, поэтому поведение полностью воспроизводимо в тестах.
final class WorkDayEngine {
  WorkDayEngine({this.window = WorkWindow.standard});

  /// Рабочее окно, внутри которого отслеживается ритм.
  final WorkWindow window;

  WorkDayPhase _phase = WorkDayPhase.notStarted;
  DateTime? _startedAt;
  DateTime? _finishedAt;
  DateTime? _runningSince;
  DateTime? _workWindowEndsAt;
  Duration _worked = Duration.zero;
  final List<WorkDayEvent> _events = <WorkDayEvent>[];

  /// Начать рабочий день.
  WorkDayCommandResult startWorkDay(DateTime now) {
    _syncWithClock(now);

    if (_phase == WorkDayPhase.running || _phase == WorkDayPhase.paused) {
      return const WorkDayCommandRejected(
        RejectionReason.workDayAlreadyInProgress,
      );
    }
    if (!window.contains(now)) {
      return const WorkDayCommandRejected(RejectionReason.outsideWorkWindow);
    }

    _phase = WorkDayPhase.running;
    _startedAt = now;
    _finishedAt = null;
    _runningSince = now;
    _workWindowEndsAt = window.endOn(now);
    _worked = Duration.zero;
    _events.add(WorkDayEvent.started(now));
    return const WorkDayCommandAccepted();
  }

  /// Поставить рабочий день на паузу: счёт рабочего времени замирает.
  WorkDayCommandResult pause(DateTime now) {
    _syncWithClock(now);

    final rejection = switch (_phase) {
      WorkDayPhase.notStarted => RejectionReason.workDayNotStarted,
      WorkDayPhase.finished => RejectionReason.workDayAlreadyFinished,
      WorkDayPhase.paused => RejectionReason.workDayAlreadyPaused,
      WorkDayPhase.running => null,
    };
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    _worked += now.difference(_runningSince!);
    _runningSince = null;
    _phase = WorkDayPhase.paused;
    _events.add(WorkDayEvent.paused(now));
    return const WorkDayCommandAccepted();
  }

  /// Продолжить рабочий день после паузы: счёт идёт с того же места.
  WorkDayCommandResult resume(DateTime now) {
    _syncWithClock(now);

    final rejection = switch (_phase) {
      WorkDayPhase.notStarted => RejectionReason.workDayNotStarted,
      WorkDayPhase.finished => RejectionReason.workDayAlreadyFinished,
      WorkDayPhase.running => RejectionReason.workDayNotPaused,
      WorkDayPhase.paused => null,
    };
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    _runningSince = now;
    _phase = WorkDayPhase.running;
    _events.add(WorkDayEvent.resumed(now));
    return const WorkDayCommandAccepted();
  }

  /// Завершить рабочий день вручную.
  WorkDayCommandResult finishWorkDay(DateTime now) {
    _syncWithClock(now);

    final rejection = switch (_phase) {
      WorkDayPhase.notStarted => RejectionReason.workDayNotStarted,
      WorkDayPhase.finished => RejectionReason.workDayAlreadyFinished,
      WorkDayPhase.running || WorkDayPhase.paused => null,
    };
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    if (_phase == WorkDayPhase.running) {
      _worked += now.difference(_runningSince!);
      _runningSince = null;
    }
    _phase = WorkDayPhase.finished;
    _finishedAt = now;
    _events.add(WorkDayEvent.finished(now, WorkDayFinishReason.manual));
    return const WorkDayCommandAccepted();
  }

  /// Текущее состояние на момент [now].
  WorkDaySnapshot snapshot(DateTime now) {
    _syncWithClock(now);

    return WorkDaySnapshot(
      phase: _phase,
      availableCommands: _availableCommands(now),
      worked: _workedAt(now),
      remainingInWorkWindow: _remainingInWorkWindow(now),
      startedAt: _startedAt,
      finishedAt: _finishedAt,
      workWindowEndsAt: _workWindowEndsAt,
      events: _events,
    );
  }

  void _syncWithClock(DateTime now) {
    final endsAt = _workWindowEndsAt;
    if (endsAt == null || now.isBefore(endsAt)) {
      return;
    }
    if (_phase != WorkDayPhase.running && _phase != WorkDayPhase.paused) {
      return;
    }

    if (_phase == WorkDayPhase.running) {
      _worked += endsAt.difference(_runningSince!);
      _runningSince = null;
    }
    _phase = WorkDayPhase.finished;
    _finishedAt = endsAt;
    _events.add(
      WorkDayEvent.finished(endsAt, WorkDayFinishReason.workWindowEnded),
    );
  }

  List<WorkDayCommand> _availableCommands(DateTime now) {
    return switch (_phase) {
      WorkDayPhase.notStarted =>
        window.contains(now) ? const [WorkDayCommand.start] : const [],
      WorkDayPhase.running => const [
        WorkDayCommand.pause,
        WorkDayCommand.finish,
      ],
      WorkDayPhase.paused => const [
        WorkDayCommand.resume,
        WorkDayCommand.finish,
      ],
      WorkDayPhase.finished =>
        window.contains(now) ? const [WorkDayCommand.start] : const [],
    };
  }

  Duration _workedAt(DateTime now) {
    final since = _runningSince;
    if (_phase == WorkDayPhase.running && since != null) {
      return _worked + now.difference(since);
    }
    return _worked;
  }

  Duration _remainingInWorkWindow(DateTime now) {
    final endsAt = _workWindowEndsAt ?? window.endOn(now);
    final remaining = endsAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
