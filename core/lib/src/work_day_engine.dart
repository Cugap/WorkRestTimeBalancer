import 'clock_time.dart';
import 'exercise.dart';
import 'exercise_catalog.dart';
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
    this.longRestInterval = const Duration(minutes: 90),
    this.longRestDuration = const Duration(minutes: 10),
    this.postponeDuration = const Duration(minutes: 5),
    this.maxPostponements = 2,
    this.mealStart = const ClockTime(13, 0),
    this.mealDuration = const Duration(minutes: 60),
    this.catalog = exerciseCatalog,
  });

  /// Рабочее окно, внутри которого отслеживается ритм.
  final WorkWindow window;

  /// Интервал работы между короткими отдыхами.
  final Duration shortRestInterval;

  /// Длительность короткого отдыха.
  final Duration shortRestDuration;

  /// Интервал работы между длинными отдыхами.
  final Duration longRestInterval;

  /// Длительность длинного отдыха.
  final Duration longRestDuration;

  /// На сколько сдвигается предложение отдыха при отложении.
  final Duration postponeDuration;

  /// Сколько отложений подряд допускается для одного предложения отдыха.
  final int maxPostponements;

  /// Время суток, когда предлагается обед.
  final ClockTime mealStart;

  /// Плановая длительность обеда.
  final Duration mealDuration;

  /// Набор упражнений, из которого ядро выбирает их по кругу.
  final List<Exercise> catalog;

  WorkDayPhase _phase = WorkDayPhase.notStarted;
  DateTime? _startedAt;
  DateTime? _finishedAt;
  DateTime? _runningSince;
  DateTime? _pausedAt;
  DateTime? _workWindowEndsAt;

  /// Момент следующего короткого отдыха по счётчику ритма.
  DateTime? _nextShortRestAt;

  /// Момент следующего длинного отдыха по счётчику ритма.
  DateTime? _nextLongRestAt;

  /// Момент предложения обеда в текущем рабочем дне с учётом отложений.
  DateTime? _nextMealAt;

  /// Обед в этом рабочем дне уже состоялся (начат или пропущен).
  bool _mealTaken = false;

  /// Момент ближайшего предложения отдыха: минимум из счётчиков и обеда или
  /// отложенный момент.
  DateTime? _nextRestAt;

  /// Вид отдыха, который будет предложен в [_nextRestAt]. Отложение его не
  /// меняет, поэтому отложенный длинный отдых остаётся длинным.
  RestKind? _offerKind;

  /// Вид предложенного или идущего отдыха.
  RestKind? _currentRestKind;

  bool _restOffered = false;
  DateTime? _restEndsAt;
  DateTime? _restStartedAt;
  DateTime? _workIntervalStartedAt;
  int _postponesUsed = 0;
  List<Exercise> _restExercises = const <Exercise>[];
  WorkDayEvent? _lastRestFinished;
  int _nextExerciseIndex = 0;
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
    _nextShortRestAt = now.add(shortRestInterval);
    _nextLongRestAt = now.add(longRestInterval);
    _mealTaken = false;
    _nextMealAt = _initialMealAt(now);
    _scheduleNextOffer();
    _restOffered = false;
    _currentRestKind = null;
    _restEndsAt = null;
    _restStartedAt = null;
    _restExercises = const <Exercise>[];
    _lastRestFinished = null;
    _workIntervalStartedAt = now;
    _pausedAt = null;
    _postponesUsed = 0;
    _worked = Duration.zero;
    _events.add(WorkDayEvent.started(now));
    return const WorkDayCommandAccepted();
  }

  /// Начать предложенный отдых: работа замирает, идёт таймер отдыха.
  /// Упражнения выбираются по кругу один раз — на момент начала отдыха.
  WorkDayCommandResult startRest(DateTime now) {
    _syncWithClock(now);

    final rejection = _restCommandRejection;
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    _beginRest(now, _currentRestKind!);
    return const WorkDayCommandAccepted();
  }

  /// Начать обед вручную в любой момент идущего рабочего дня, даже раньше
  /// назначенного времени. Ручной обед считается состоявшимся: повторно в
  /// этом рабочем дне он не предлагается и не начинается.
  WorkDayCommandResult startMeal(DateTime now) {
    _syncWithClock(now);

    final rejection = switch (_phase) {
      WorkDayPhase.notStarted => RejectionReason.workDayNotStarted,
      WorkDayPhase.finished => RejectionReason.workDayAlreadyFinished,
      WorkDayPhase.paused => RejectionReason.workDayAlreadyPaused,
      WorkDayPhase.resting => RejectionReason.restInProgress,
      WorkDayPhase.running || WorkDayPhase.restOffered => null,
    };
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }
    if (_mealTaken) {
      return const WorkDayCommandRejected(RejectionReason.mealAlreadyTaken);
    }

    _beginRest(now, RestKind.meal);
    return const WorkDayCommandAccepted();
  }

  /// Начать отдых [kind] с момента [now]: работа замирает, идёт таймер, а
  /// упражнения выбираются один раз на весь отдых.
  void _beginRest(DateTime now, RestKind kind) {
    _worked += now.difference(_runningSince!);
    _runningSince = null;
    _phase = WorkDayPhase.resting;
    _currentRestKind = kind;
    _restEndsAt = now.add(_restDurationFor(kind));
    _restStartedAt = now;
    _restExercises = _takeExercises(_exerciseCountFor(kind));
    _restOffered = false;
    _nextRestAt = null;
    _offerKind = null;
    _workIntervalStartedAt = null;
    _postponesUsed = 0;
    if (kind == RestKind.meal) {
      _mealTaken = true;
      _nextMealAt = null;
    }
    _events.add(WorkDayEvent.restStarted(now, kind));
  }

  /// Завершить идущий отдых досрочно: новый интервал работы начинается с этого
  /// момента, и ритм продолжается от него.
  WorkDayCommandResult finishRest(DateTime now) {
    _syncWithClock(now);

    if (_phase != WorkDayPhase.resting) {
      return const WorkDayCommandRejected(RejectionReason.restNotInProgress);
    }

    _endRest(now, RestFinishReason.early);
    return const WorkDayCommandAccepted();
  }

  /// Пропустить предложенный отдых: новый интервал работы начинается сразу
  /// с момента пропуска, долг за пропуск не копится.
  ///
  /// Счётчик короткого отдыха при пропуске начинается заново. Счётчик
  /// длинного отдыха пропуск не обнуляет: следующий длинный отдых наступает
  /// через интервал длинного отдыха от плановой точки пропущенного, а если
  /// пропуск случился позже этого срока — от момента пропуска. Так пропуск не
  /// создаёт ни долга, ни немедленного повторного предложения.
  WorkDayCommandResult skipRest(DateTime now) {
    _syncWithClock(now);

    final rejection = _restCommandRejection;
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    final kind = _currentRestKind!;
    _restOffered = false;
    _currentRestKind = null;
    _nextShortRestAt = now.add(shortRestInterval);
    if (kind == RestKind.meal) {
      // Пропуск обеда ничего не переносит: следующий обед будет только в
      // новом рабочем дне, а длинный счётчик не сбрасывается. Новый интервал
      // работы начинается с момента пропуска, как у любого пропуска.
      _mealTaken = true;
      _nextMealAt = null;
    }
    if (kind == RestKind.long) {
      final planned = _nextLongRestAt ?? now;
      final nextLong = planned.add(longRestInterval);
      _nextLongRestAt = nextLong.isAfter(now)
          ? nextLong
          : now.add(longRestInterval);
    } else {
      // Обед с приоритетом мог вытеснить длинный отдых, точка которого уже
      // прошла: сдвигаем её так, чтобы пропуск не создавал долга.
      final longAt = _nextLongRestAt;
      if (longAt != null && !longAt.isAfter(now)) {
        _nextLongRestAt = now.add(longRestInterval);
      }
    }
    _scheduleNextOffer();
    _workIntervalStartedAt = now;
    _postponesUsed = 0;
    _events.add(WorkDayEvent.restSkipped(now, kind));
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
    final kind = _currentRestKind!;
    _currentRestKind = null;
    _nextRestAt = now.add(postponeDuration);
    if (kind == RestKind.meal) {
      _nextMealAt = _nextRestAt;
    }
    _events.add(WorkDayEvent.restPostponed(now, kind));
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

    final pausedFor = now.difference(_pausedAt!);
    _nextShortRestAt = _nextShortRestAt?.add(pausedFor);
    _nextLongRestAt = _nextLongRestAt?.add(pausedFor);
    if (!_restOffered && _offerKind != RestKind.meal) {
      // Момент обеда — настенное время: пауза его не сдвигает. Обед,
      // наступивший на паузе, ждёт возобновления и предлагается сразу.
      _nextRestAt = _nextRestAt?.add(pausedFor);
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

    if (_phase == WorkDayPhase.resting) {
      // Отдых прерван завершением дня: в журнале он считается завершённым.
      final restFinished = _restFinishedEvent(
        now,
        RestFinishReason.workDayEnded,
      );
      _lastRestFinished = restFinished;
      _clearRest();
      _events.add(restFinished);
    }

    if (_phase == WorkDayPhase.running) {
      _worked += now.difference(_runningSince!);
      _runningSince = null;
    }
    _phase = WorkDayPhase.finished;
    _finishedAt = now;
    _clearSchedule();
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
      restDuration: _restDuration,
      nextRestAt: _nextRestAtWithinWindow,
      untilNextRest: _untilNextRest(now),
      remainingRest: _remainingRest(now),
      remainingPostponements: maxPostponements - _postponesUsed,
      exercises: _restExercises,
      lastRestFinished: _lastRestFinished,
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
      _phase == WorkDayPhase.resting || _restOffered ? _currentRestKind : null;

  /// Плановая длительность предложенного или идущего отдыха.
  Duration? get _restDuration {
    final kind = _restKind;
    return kind == null ? null : _restDurationFor(kind);
  }

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

    _endRest(endsAt, RestFinishReason.natural);
  }

  /// Закончить идущий отдых в момент [endedAt]. За концом рабочего окна работа
  /// уже не начинается: день закрывается по концу окна.
  void _endRest(DateTime endedAt, RestFinishReason reason) {
    final kind = _currentRestKind!;
    final actualDuration = endedAt.difference(_restStartedAt ?? endedAt);
    final restFinished = _restFinishedEvent(endedAt, reason);
    _clearRest();
    _lastRestFinished = restFinished;

    switch (kind) {
      case RestKind.meal:
        // Обед сбрасывает оба счётчика: ритм начинается заново от его конца.
        _nextShortRestAt = endedAt.add(shortRestInterval);
        _nextLongRestAt = endedAt.add(longRestInterval);
      case RestKind.long:
        _nextLongRestAt = endedAt.add(longRestInterval);
        _nextShortRestAt = endedAt.add(shortRestInterval);
      case RestKind.short:
        // Отдых — не рабочее время: счётчик длинного отдыха сдвигается на него.
        _nextLongRestAt = _nextLongRestAt?.add(actualDuration);
        _nextShortRestAt = endedAt.add(shortRestInterval);
    }

    final windowEndsAt = _workWindowEndsAt;
    if (windowEndsAt != null && !endedAt.isBefore(windowEndsAt)) {
      _phase = WorkDayPhase.finished;
      _finishedAt = windowEndsAt;
      _clearSchedule();
      _workIntervalStartedAt = null;
      _postponesUsed = 0;
      _pausedAt = null;
      _events.add(
        WorkDayEvent.finished(
          windowEndsAt,
          WorkDayFinishReason.workWindowEnded,
        ),
      );
      _events.add(restFinished);
      return;
    }

    _phase = WorkDayPhase.running;
    _runningSince = endedAt;
    _scheduleNextOffer();
    _workIntervalStartedAt = endedAt;
    _postponesUsed = 0;
    _events.add(restFinished);
  }

  WorkDayEvent _restFinishedEvent(DateTime endedAt, RestFinishReason reason) {
    final kind = _currentRestKind ?? RestKind.short;
    return WorkDayEvent.restFinished(
      endedAt,
      kind,
      restFinishReason: reason,
      plannedDuration: _restDurationFor(kind),
      actualDuration: endedAt.difference(_restStartedAt ?? endedAt),
    );
  }

  void _clearRest() {
    _restEndsAt = null;
    _restStartedAt = null;
    _restExercises = const <Exercise>[];
    _currentRestKind = null;
  }

  /// Убрать все запланированные отдыхи: день завершён.
  void _clearSchedule() {
    _nextShortRestAt = null;
    _nextLongRestAt = null;
    _nextMealAt = null;
    _nextRestAt = null;
    _offerKind = null;
    _restOffered = false;
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
    _clearSchedule();
    _workIntervalStartedAt = null;
    _pausedAt = null;
    _postponesUsed = 0;
    _events.add(
      WorkDayEvent.finished(endsAt, WorkDayFinishReason.workWindowEnded),
    );
  }

  /// Предложить отдых, момент которого наступил. Когда счётчики совпадают или
  /// длинный наступил раньше, предлагается длинный: отдыхи не идут очередью.
  void _offerRestIfDue(DateTime now) {
    if (_phase != WorkDayPhase.running || _restOffered) {
      return;
    }
    final next = _nextRestAtWithinWindow;
    final kind = _offerKind;
    if (next == null || kind == null || now.isBefore(next)) {
      return;
    }
    _restOffered = true;
    _currentRestKind = kind;
    _events.add(WorkDayEvent.restOffered(next, kind));
  }

  /// Запланировать ближайшее предложение отдыха по двум счётчикам и обеду.
  /// При совпадении моментов обед важнее повторяющегося отдыха, а длинный
  /// отдых — важнее короткого: обед не теряется, а отдыхи не идут очередью.
  void _scheduleNextOffer() {
    final mealAt = _mealCandidateAt;
    final candidates = <(DateTime, RestKind)>[
      if (_nextShortRestAt != null) (_nextShortRestAt!, RestKind.short),
      if (_nextLongRestAt != null) (_nextLongRestAt!, RestKind.long),
      if (mealAt != null) (mealAt, RestKind.meal),
    ];
    if (candidates.isEmpty) {
      _nextRestAt = null;
      _offerKind = null;
      return;
    }
    candidates.sort((a, b) {
      final byMoment = a.$1.compareTo(b.$1);
      return byMoment != 0
          ? byMoment
          : _offerPriority(a.$2).compareTo(_offerPriority(b.$2));
    });
    _nextRestAt = candidates.first.$1;
    _offerKind = candidates.first.$2;
  }

  /// Порядок выбора при совпадении моментов: обед, длинный, короткий.
  int _offerPriority(RestKind kind) => switch (kind) {
    RestKind.meal => 0,
    RestKind.long => 1,
    RestKind.short => 2,
  };

  /// Момент обеда, если он ещё не состоялся в этом рабочем дне. Попадание за
  /// конец окна отсекает [_nextRestAtWithinWindow].
  DateTime? get _mealCandidateAt => _mealTaken ? null : _nextMealAt;

  /// Момент обеда в начале рабочего дня. Обед предлагается только в своё
  /// время: если к старту дня оно уже прошло, автоматического предложения не
  /// будет — начать обед можно вручную. Обед ровно на конце рабочего окна или
  /// позже не предлагается.
  DateTime? _initialMealAt(DateTime now) {
    final scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      mealStart.hour,
      mealStart.minute,
    );
    if (scheduled.isBefore(now) || !scheduled.isBefore(window.endOn(now))) {
      return null;
    }
    return scheduled;
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
      WorkDayPhase.running => [
        WorkDayCommand.pause,
        WorkDayCommand.finish,
        if (_canStartMealManually) WorkDayCommand.startMeal,
      ],
      WorkDayPhase.restOffered => [
        WorkDayCommand.startRest,
        WorkDayCommand.skipRest,
        if (_postponesUsed < maxPostponements) WorkDayCommand.postponeRest,
        WorkDayCommand.pause,
        WorkDayCommand.finish,
        if (_canStartMealManually) WorkDayCommand.startMeal,
      ],
      WorkDayPhase.paused => const [
        WorkDayCommand.resume,
        WorkDayCommand.finish,
      ],
      WorkDayPhase.resting => const [
        WorkDayCommand.finishRest,
        WorkDayCommand.finish,
      ],
      WorkDayPhase.finished =>
        window.contains(now) ? const [WorkDayCommand.start] : const [],
    };
  }

  /// Обед ещё можно начать вручную: он не состоялся и сейчас не предложен сам
  /// (предложенный обед начинается командой «начать отдых»).
  bool get _canStartMealManually =>
      !_mealTaken && _currentRestKind != RestKind.meal;

  Duration _workedAt(DateTime now) {
    final since = _runningSince;
    if (_phase == WorkDayPhase.running && since != null) {
      return _worked + now.difference(since);
    }
    return _worked;
  }

  /// Сколько упражнений показывает отдых: короткий — одно, длинный — два из
  /// разных категорий, обед — три, по одному из каждой категории.
  int _exerciseCountFor(RestKind kind) => switch (kind) {
    RestKind.short => 1,
    RestKind.long => 2,
    RestKind.meal => 3,
  };

  /// Плановая длительность отдыха по его виду.
  Duration _restDurationFor(RestKind kind) => switch (kind) {
    RestKind.short => shortRestDuration,
    RestKind.long => longRestDuration,
    RestKind.meal => mealDuration,
  };

  /// Взять [count] упражнений по кругу, не повторяя уже взятые в этом отдыхе и
  /// добавляя каждое следующее из другой категории. Курсор запоминается в
  /// состоянии движка, поэтому первый отдых следующего раза не повторяет
  /// прошлое упражнение, а после конца набора круг начинается заново.
  List<Exercise> _takeExercises(int count) {
    if (catalog.isEmpty) {
      return const <Exercise>[];
    }
    final taken = <Exercise>[];
    for (var slot = 0; slot < count; slot++) {
      Exercise? chosen;
      for (var step = 0; step < catalog.length; step++) {
        final index = (_nextExerciseIndex + step) % catalog.length;
        final candidate = catalog[index];
        if (taken.contains(candidate)) {
          continue;
        }
        if (taken.any((taken) => taken.category == candidate.category)) {
          continue;
        }
        chosen = candidate;
        _nextExerciseIndex = (index + 1) % catalog.length;
        break;
      }
      if (chosen == null) {
        break;
      }
      taken.add(chosen);
    }
    return List.unmodifiable(taken);
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
