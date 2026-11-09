import 'rest_kind.dart';
import 'work_day_command.dart';
import 'work_day_event.dart';
import 'work_day_snapshot.dart';
import 'work_window.dart';

/// Движок рабочего дня. Не читает системное время: каждый вызов получает момент
/// от оболочки, поэтому поведение полностью воспроизводимо в тестах.
/// Оболочка обязана передавать неубывающее время — тогда перевод системных
/// часов назад не сдвигает ритм.
final class WorkDayEngine {
  WorkDayEngine({
    this.window = WorkWindow.standard,
    this.shortRestInterval = const Duration(minutes: 25),
    this.shortRestDuration = const Duration(minutes: 3),
    this.postponeDuration = const Duration(minutes: 5),
    this.maxPostponements = 2,
  });

  /// Рабочее окно, внутри которого отслеживается ритм.
  final WorkWindow window;

  /// Интервал работы между короткими отдыхами.
  final Duration shortRestInterval;

  /// Длительность короткого отдыха.
  final Duration shortRestDuration;

  /// На сколько сдвигается предложение отдыха при отложении.
  final Duration postponeDuration;

  /// Сколько отложений подряд допускается для одного предложения отдыха.
  final int maxPostponements;

  WorkDayPhase _phase = WorkDayPhase.notStarted;
  DateTime? _startedAt;
  DateTime? _finishedAt;
  DateTime? _runningSince;
  DateTime? _pausedAt;
  DateTime? _workWindowEndsAt;
  DateTime? _nextRestAt;
  bool _restOffered = false;
  DateTime? _restEndsAt;
  DateTime? _workIntervalStartedAt;
  int _postponesUsed = 0;
  Duration _worked = Duration.zero;
  final List<WorkDayEvent> _events = <WorkDayEvent>[];

  /// Начать рабочий день.
  WorkDayCommandResult startWorkDay(DateTime now) {
    _syncWithClock(now);

    if (_visiblePhase != WorkDayPhase.notStarted &&
        _visiblePhase != WorkDayPhase.finished) {
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
    _nextRestAt = now.add(shortRestInterval);
    _restOffered = false;
    _restEndsAt = null;
    _workIntervalStartedAt = now;
    _pausedAt = null;
    _postponesUsed = 0;
    _worked = Duration.zero;
    _events.add(WorkDayEvent.started(now));
    return const WorkDayCommandAccepted();
  }

  /// Начать предложенный отдых: работа замирает, идёт таймер отдыха.
  WorkDayCommandResult startRest(DateTime now) {
    _syncWithClock(now);

    final rejection = _restCommandRejection;
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    _worked += now.difference(_runningSince!);
    _runningSince = null;
    _phase = WorkDayPhase.resting;
    _restEndsAt = now.add(shortRestDuration);
    _restOffered = false;
    _nextRestAt = null;
    _workIntervalStartedAt = null;
    _postponesUsed = 0;
    _events.add(WorkDayEvent.restStarted(now, RestKind.short));
    return const WorkDayCommandAccepted();
  }

  /// Пропустить предложенный отдых: новый интервал работы начинается сразу
  /// с момента пропуска, долг за пропуск не копится.
  WorkDayCommandResult skipRest(DateTime now) {
    _syncWithClock(now);

    final rejection = _restCommandRejection;
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    _restOffered = false;
    _nextRestAt = now.add(shortRestInterval);
    _workIntervalStartedAt = now;
    _postponesUsed = 0;
    _events.add(WorkDayEvent.restSkipped(now, RestKind.short));
    return const WorkDayCommandAccepted();
  }

  /// Отложить предложенный отдых: предложение вернётся через
  /// [postponeDuration], а время работы продолжит идти. Допускается не больше
  /// [maxPostponements] отложений подряд.
  WorkDayCommandResult postponeRest(DateTime now) {
    _syncWithClock(now);

    final rejection = _restCommandRejection;
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }
    if (_postponesUsed >= maxPostponements) {
      return const WorkDayCommandRejected(RejectionReason.postponeLimitReached);
    }

    _postponesUsed++;
    _restOffered = false;
    _nextRestAt = now.add(postponeDuration);
    _events.add(WorkDayEvent.restPostponed(now, RestKind.short));
    return const WorkDayCommandAccepted();
  }

  /// Почему команда отдыха не может выполниться прямо сейчас.
  RejectionReason? get _restCommandRejection {
    if (_phase == WorkDayPhase.resting) {
      return RejectionReason.restInProgress;
    }
    if (_phase != WorkDayPhase.running || !_restOffered) {
      return RejectionReason.restNotOffered;
    }
    return null;
  }

  /// Поставить рабочий день на паузу: счёт рабочего времени замирает.
  /// Предложенный отдых на паузе ждёт возобновления.
  WorkDayCommandResult pause(DateTime now) {
    _syncWithClock(now);

    final rejection = switch (_visiblePhase) {
      WorkDayPhase.notStarted => RejectionReason.workDayNotStarted,
      WorkDayPhase.finished => RejectionReason.workDayAlreadyFinished,
      WorkDayPhase.paused => RejectionReason.workDayAlreadyPaused,
      WorkDayPhase.resting => RejectionReason.restInProgress,
      WorkDayPhase.running || WorkDayPhase.restOffered => null,
    };
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    _worked += now.difference(_runningSince!);
    _runningSince = null;
    _pausedAt = now;
    _phase = WorkDayPhase.paused;
    _events.add(WorkDayEvent.paused(now));
    return const WorkDayCommandAccepted();
  }

  /// Продолжить рабочий день после паузы: счёт идёт с того же места, а
  /// следующий отдых сдвигается на длительность паузы.
  WorkDayCommandResult resume(DateTime now) {
    _syncWithClock(now);

    final rejection = switch (_phase) {
      WorkDayPhase.notStarted => RejectionReason.workDayNotStarted,
      WorkDayPhase.finished => RejectionReason.workDayAlreadyFinished,
      WorkDayPhase.paused => null,
      WorkDayPhase.resting => RejectionReason.restInProgress,
      WorkDayPhase.running ||
      WorkDayPhase.restOffered => RejectionReason.workDayNotPaused,
    };
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    if (!_restOffered) {
      final next = _nextRestAt;
      if (next != null) {
        _nextRestAt = next.add(now.difference(_pausedAt!));
      }
    }
    _pausedAt = null;
    _runningSince = now;
    _phase = WorkDayPhase.running;
    _events.add(WorkDayEvent.resumed(now));
    return const WorkDayCommandAccepted();
  }

  /// Завершить рабочий день вручную. Идущий отдых при этом прерывается.
  WorkDayCommandResult finishWorkDay(DateTime now) {
    _syncWithClock(now);

    final rejection = switch (_phase) {
      WorkDayPhase.notStarted => RejectionReason.workDayNotStarted,
      WorkDayPhase.finished => RejectionReason.workDayAlreadyFinished,
      WorkDayPhase.running ||
      WorkDayPhase.paused ||
      WorkDayPhase.restOffered ||
      WorkDayPhase.resting => null,
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
    _nextRestAt = null;
    _restOffered = false;
    _restEndsAt = null;
    _workIntervalStartedAt = null;
    _pausedAt = null;
    _postponesUsed = 0;
    _events.add(WorkDayEvent.finished(now, WorkDayFinishReason.manual));
    return const WorkDayCommandAccepted();
  }

  /// Текущее состояние на момент [now].
  WorkDaySnapshot snapshot(DateTime now) {
    _syncWithClock(now);

    return WorkDaySnapshot(
      phase: _visiblePhase,
      availableCommands: _availableCommands(now),
      worked: _workedAt(now),
      remainingInWorkWindow: _remainingInWorkWindow(now),
      startedAt: _startedAt,
      finishedAt: _finishedAt,
      workWindowEndsAt: _workWindowEndsAt,
      workIntervalStartedAt: _workIntervalStartedAt,
      restKind: _restKind,
      nextRestAt: _nextRestAtWithinWindow,
      untilNextRest: _untilNextRest(now),
      remainingRest: _remainingRest(now),
      remainingPostponements: maxPostponements - _postponesUsed,
      events: _events,
    );
  }

  /// Фаза, которую видит оболочка: предложенный отдых — это идущий рабочий
  /// день с активным предложением.
  WorkDayPhase get _visiblePhase =>
      _phase == WorkDayPhase.running && _restOffered
      ? WorkDayPhase.restOffered
      : _phase;

  RestKind? get _restKind =>
      _phase == WorkDayPhase.resting || _restOffered ? RestKind.short : null;

  void _syncWithClock(DateTime now) {
    _completeRestIfDue(now);
    _closeAtWorkWindowEndIfDue(now);
    _offerRestIfDue(now);
  }

  /// Отдых заканчивается сам: новый интервал работы начинается с его конца.
  void _completeRestIfDue(DateTime now) {
    final endsAt = _restEndsAt;
    if (_phase != WorkDayPhase.resting ||
        endsAt == null ||
        now.isBefore(endsAt)) {
      return;
    }

    _restEndsAt = null;
    final windowEndsAt = _workWindowEndsAt;
    if (windowEndsAt != null && !endsAt.isBefore(windowEndsAt)) {
      // Отдых доигран уже за концом окна: день закрывается по концу окна,
      // а отдых записывается в журнал позже — по своему фактическому концу.
      _phase = WorkDayPhase.finished;
      _finishedAt = windowEndsAt;
      _nextRestAt = null;
      _workIntervalStartedAt = null;
      _postponesUsed = 0;
      _events.add(
        WorkDayEvent.finished(
          windowEndsAt,
          WorkDayFinishReason.workWindowEnded,
        ),
      );
      _events.add(WorkDayEvent.restFinished(endsAt, RestKind.short));
      return;
    }

    _phase = WorkDayPhase.running;
    _runningSince = endsAt;
    _nextRestAt = endsAt.add(shortRestInterval);
    _workIntervalStartedAt = endsAt;
    _postponesUsed = 0;
    _events.add(WorkDayEvent.restFinished(endsAt, RestKind.short));
  }

  void _closeAtWorkWindowEndIfDue(DateTime now) {
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
    _nextRestAt = null;
    _restOffered = false;
    _workIntervalStartedAt = null;
    _pausedAt = null;
    _postponesUsed = 0;
    _events.add(
      WorkDayEvent.finished(endsAt, WorkDayFinishReason.workWindowEnded),
    );
  }

  void _offerRestIfDue(DateTime now) {
    if (_phase != WorkDayPhase.running || _restOffered) {
      return;
    }
    final next = _nextRestAtWithinWindow;
    if (next == null || now.isBefore(next)) {
      return;
    }
    _restOffered = true;
    _events.add(WorkDayEvent.restOffered(next, RestKind.short));
  }

  /// Момент следующего отдыха, только если он ещё может наступить внутри
  /// рабочего окна: отдых за концом окна не предлагается. Пока отдых предложен
  /// или идёт, следующего момента ещё нет.
  DateTime? get _nextRestAtWithinWindow {
    if (_restOffered) {
      return null;
    }
    final next = _nextRestAt;
    final endsAt = _workWindowEndsAt;
    if (next == null || endsAt == null || !next.isBefore(endsAt)) {
      return null;
    }
    return next;
  }

  Duration? _untilNextRest(DateTime now) {
    if (_restOffered) {
      return Duration.zero;
    }
    if (_phase != WorkDayPhase.running && _phase != WorkDayPhase.paused) {
      return null;
    }
    final next = _nextRestAtWithinWindow;
    if (next == null) {
      return null;
    }
    final reference = _phase == WorkDayPhase.paused ? _pausedAt! : now;
    final remaining = next.difference(reference);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration? _remainingRest(DateTime now) {
    final endsAt = _restEndsAt;
    if (_phase != WorkDayPhase.resting || endsAt == null) {
      return null;
    }
    final remaining = endsAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  List<WorkDayCommand> _availableCommands(DateTime now) {
    return switch (_visiblePhase) {
      WorkDayPhase.notStarted =>
        window.contains(now) ? const [WorkDayCommand.start] : const [],
      WorkDayPhase.running => const [
        WorkDayCommand.pause,
        WorkDayCommand.finish,
      ],
      WorkDayPhase.restOffered =>
        _postponesUsed < maxPostponements
            ? const [
                WorkDayCommand.startRest,
                WorkDayCommand.skipRest,
                WorkDayCommand.postponeRest,
                WorkDayCommand.pause,
                WorkDayCommand.finish,
              ]
            : const [
                WorkDayCommand.startRest,
                WorkDayCommand.skipRest,
                WorkDayCommand.pause,
                WorkDayCommand.finish,
              ],
      WorkDayPhase.paused => const [
        WorkDayCommand.resume,
        WorkDayCommand.finish,
      ],
      WorkDayPhase.resting => const [WorkDayCommand.finish],
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
    final endsAt = switch (_phase) {
      WorkDayPhase.running ||
      WorkDayPhase.paused ||
      WorkDayPhase.restOffered ||
      WorkDayPhase.resting => _workWindowEndsAt!,
      WorkDayPhase.notStarted || WorkDayPhase.finished => window.endOn(now),
    };
    final remaining = endsAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
