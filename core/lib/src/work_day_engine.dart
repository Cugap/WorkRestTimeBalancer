import 'dart:async';

import 'exercise.dart';
import 'exercise_catalog.dart';
import 'persisted_document.dart';
import 'rest_kind.dart';
import 'rest_reminder.dart';
import 'rest_reminder_port.dart';
import 'rhythm_settings.dart';
import 'settings_validation.dart';
import 'work_day_command.dart';
import 'work_day_event.dart';
import 'work_day_snapshot.dart';
import 'work_window.dart';

/// Сколько ближайших точек отдыха ядро напоминает заранее по умолчанию.
const int defaultReminderLimit = 8;

/// Движок рабочего дня. Не читает системное время: каждый вызов получает момент
/// от оболочки, поэтому поведение полностью воспроизводимо в тестах.
///
/// Время внутри одного запуска обязано не убывать. Движок сам держит эту
/// границу: момент, который меньше последнего увиденного, считается тем же
/// последним моментом. Поэтому перевод системных часов назад — до или после
/// перезапуска — не отматывает ритм и не повторяет события.
final class WorkDayEngine {
  /// Настройки, переданные сюда, считаются доверенными: значения по умолчанию
  /// или восстановленные из хранилища. Диапазоны для ввода пользователя
  /// проверяет [updateSettings]; конструктор их не перепроверяет.
  WorkDayEngine({
    RhythmSettings settings = RhythmSettings.defaults,
    this.postponeDuration = const Duration(minutes: 5),
    this.maxPostponements = 2,
    this.catalog = exerciseCatalog,
    this.reminderLimit = defaultReminderLimit,
    RestReminderPort? reminders,
  }) : _settings = settings,
       _reminders = reminders;

  /// Восстановить движок из документа: настройки, журнал и, если он есть,
  /// текущий рабочий день. Состояние дня применяется как есть; отставание по
  /// времени разбирает первая синхронизация — как будто приложение было
  /// закрыто с момента [WorkDayState.lastObservedAt].
  factory WorkDayEngine.restore(
    PersistedDocument document, {
    Duration postponeDuration = const Duration(minutes: 5),
    int maxPostponements = 2,
    List<Exercise> catalog = exerciseCatalog,
    int reminderLimit = defaultReminderLimit,
    RestReminderPort? reminders,
  }) {
    final engine = WorkDayEngine(
      settings: document.settings,
      postponeDuration: postponeDuration,
      maxPostponements: maxPostponements,
      catalog: catalog,
      reminderLimit: reminderLimit,
      reminders: reminders,
    );
    engine._events.addAll(document.journal);
    final day = document.day;
    if (day != null) {
      engine._applyState(day);
    }
    return engine;
  }

  /// Действующие настройки ритма и рабочего окна.
  RhythmSettings _settings;

  /// На сколько сдвигается предложение отдыха при отложении.
  final Duration postponeDuration;

  /// Сколько отложений подряд допускается для одного предложения отдыха.
  final int maxPostponements;

  /// Набор упражнений, из которого ядро выбирает их по кругу.
  final List<Exercise> catalog;

  /// Сколько ближайших точек отдыха напоминать заранее. Небольшое окно нужно
  /// из-за лимита на число запланированных уведомлений на iOS (около 64) и
  /// ради того, чтобы каждая смена состояния переписывала только актуальные
  /// напоминания. По умолчанию [defaultReminderLimit].
  final int reminderLimit;

  /// Порт напоминаний; null — ядро работает без напоминаний (тесты ядра и
  /// платформы без уведомлений).
  final RestReminderPort? _reminders;

  /// Рабочее окно из действующих настроек. Оно есть всегда: движок хранит
  /// только допустимые настройки.
  WorkWindow get _window => _settings.workWindow!;

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

  /// Плановая длительность идущего отдыха на момент его начала. Изменение
  /// настроек не переписывает идущий отдых.
  Duration? _restPlannedDuration;
  DateTime? _workIntervalStartedAt;
  int _postponesUsed = 0;
  List<Exercise> _restExercises = const <Exercise>[];
  WorkDayEvent? _lastRestFinished;
  int _nextExerciseIndex = 0;
  Duration _worked = Duration.zero;
  final List<WorkDayEvent> _events = <WorkDayEvent>[];

  /// Последний момент, который движок уже обработал. Нижняя граница времени:
  /// всё, что раньше, считается этим моментом.
  DateTime? _lastObservedAt;

  /// Момент последнего наблюдения на сохранении: с него начинается разбор
  /// времени, прошедшего при закрытом приложении. Живёт только до первой
  /// синхронизации после восстановления.
  DateTime? _closedSince;

  /// Собрать документ из текущего состояния. Состояние дня отсутствует, пока
  /// рабочий день не начат; журнал и настройки сохраняются всегда.
  PersistedDocument document() => PersistedDocument(
    settings: _settings,
    journal: _events,
    day: _phase == WorkDayPhase.notStarted ? null : _state(),
  );

  /// Отметить в журнале, что настройки и журнал сохранены в файл переноса.
  void recordExport(DateTime now) {
    _events.add(WorkDayEvent.dataExported(_syncWithClock(now)));
  }

  /// Заменить настройки и журнал импортированным документом с момента [now].
  ///
  /// Идущий рабочий день не трогается: фаза, начало интервала работы, идущий
  /// отдых и показанное предложение остаются прежними, а новые настройки лишь
  /// применяются к расчёту следующих отдыхов. Состояние дня из документа
  /// игнорируется — переносится только то, что спецификация называет данными.
  /// Момент импорта дописывается в конец нового журнала.
  void applyImportedDocument(DateTime now, PersistedDocument imported) {
    now = _syncWithClock(now);

    final previous = _settings;
    _settings = imported.settings;
    _events
      ..clear()
      ..addAll(imported.journal)
      ..add(WorkDayEvent.dataImported(now));
    _lastRestFinished = _lastRestFinishedInJournal();
    _applySettingsToSchedule(now, previous);
  }

  WorkDayState _state() => WorkDayState(
    lastObservedAt: _lastObservedAt,
    phase: _phase,
    startedAt: _startedAt,
    finishedAt: _finishedAt,
    runningSince: _runningSince,
    pausedAt: _pausedAt,
    workWindowEndsAt: _workWindowEndsAt,
    nextShortRestAt: _nextShortRestAt,
    nextLongRestAt: _nextLongRestAt,
    nextMealAt: _nextMealAt,
    mealTaken: _mealTaken,
    nextRestAt: _nextRestAt,
    offerKind: _offerKind,
    currentRestKind: _currentRestKind,
    restOffered: _restOffered,
    restEndsAt: _restEndsAt,
    restStartedAt: _restStartedAt,
    restPlannedDuration: _restPlannedDuration,
    workIntervalStartedAt: _workIntervalStartedAt,
    postponesUsed: _postponesUsed,
    restExercises: _restExercises,
    nextExerciseIndex: _nextExerciseIndex,
    worked: _worked,
  );

  void _applyState(WorkDayState state) {
    _phase = state.phase;
    _startedAt = state.startedAt;
    _finishedAt = state.finishedAt;
    _runningSince = state.runningSince;
    _pausedAt = state.pausedAt;
    _workWindowEndsAt = state.workWindowEndsAt;
    _nextShortRestAt = state.nextShortRestAt;
    _nextLongRestAt = state.nextLongRestAt;
    _nextMealAt = state.nextMealAt;
    _mealTaken = state.mealTaken;
    _nextRestAt = state.nextRestAt;
    _offerKind = state.offerKind;
    _currentRestKind = state.currentRestKind;
    _restOffered = state.restOffered;
    _restEndsAt = state.restEndsAt;
    _restStartedAt = state.restStartedAt;
    _restPlannedDuration = state.restPlannedDuration;
    _workIntervalStartedAt = state.workIntervalStartedAt;
    _postponesUsed = state.postponesUsed;
    _restExercises = state.restExercises;
    _nextExerciseIndex = state.nextExerciseIndex;
    _worked = state.worked;
    _lastObservedAt = state.lastObservedAt;
    _closedSince = state.lastObservedAt;
    _lastRestFinished = _lastRestFinishedInJournal();
  }

  /// Последнее завершение отдыха в журнале текущего рабочего дня: снимок
  /// восстанавливает его по журналу, а не хранит второй копией.
  WorkDayEvent? _lastRestFinishedInJournal() {
    for (final event in _events.reversed) {
      if (event.type == WorkDayEventType.restFinished) {
        return event;
      }
      if (event.type == WorkDayEventType.workDayStarted) {
        return null;
      }
    }
    return null;
  }

  /// Начать рабочий день.
  WorkDayCommandResult startWorkDay(DateTime now) =>
      _commanded(now, _startWorkDay);

  WorkDayCommandResult _startWorkDay(DateTime now) {
    if (_visiblePhase != WorkDayPhase.notStarted &&
        _visiblePhase != WorkDayPhase.finished) {
      return const WorkDayCommandRejected(
        RejectionReason.workDayAlreadyInProgress,
      );
    }
    if (!_window.contains(now)) {
      return const WorkDayCommandRejected(RejectionReason.outsideWorkWindow);
    }

    _phase = WorkDayPhase.running;
    _startedAt = now;
    _finishedAt = null;
    _runningSince = now;
    _workWindowEndsAt = _window.endOn(now);
    _nextShortRestAt = now.add(_settings.shortRestInterval);
    _nextLongRestAt = now.add(_settings.longRestInterval);
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
  WorkDayCommandResult startRest(DateTime now) => _commanded(now, _startRest);

  WorkDayCommandResult _startRest(DateTime now) {
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
  WorkDayCommandResult startMeal(DateTime now) => _commanded(now, _startMeal);

  WorkDayCommandResult _startMeal(DateTime now) {
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
    _restPlannedDuration = _restDurationFor(kind);
    _restEndsAt = now.add(_restPlannedDuration!);
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
    _events.add(
      WorkDayEvent.restStarted(
        now,
        kind,
        plannedDuration: _restPlannedDuration,
      ),
    );
  }

  /// Завершить идущий отдых досрочно: новый интервал работы начинается с этого
  /// момента, и ритм продолжается от него.
  WorkDayCommandResult finishRest(DateTime now) => _commanded(now, _finishRest);

  WorkDayCommandResult _finishRest(DateTime now) {
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
  WorkDayCommandResult skipRest(DateTime now) => _commanded(now, _skipRest);

  WorkDayCommandResult _skipRest(DateTime now) {
    final rejection = _restCommandRejection;
    if (rejection != null) {
      return WorkDayCommandRejected(rejection);
    }

    _skipAt(now, _currentRestKind!);
    return const WorkDayCommandAccepted();
  }

  /// Правила пропуска в момент [at] для отдыха [kind]. Пропуск не создаёт
  /// долга: счётчик короткого отдыха начинается заново, счётчик длинного не
  /// обнуляется, а новый интервал работы начинается с момента пропуска.
  void _skipAt(DateTime at, RestKind kind) {
    _restOffered = false;
    _currentRestKind = null;
    _nextShortRestAt = at.add(_settings.shortRestInterval);
    if (kind == RestKind.meal) {
      // Пропуск обеда ничего не переносит: следующий обед будет только в
      // новом рабочем дне, а длинный счётчик не сбрасывается. Новый интервал
      // работы начинается с момента пропуска, как у любого пропуска.
      _mealTaken = true;
      _nextMealAt = null;
    }
    if (kind == RestKind.long) {
      final planned = _nextLongRestAt ?? at;
      final nextLong = planned.add(_settings.longRestInterval);
      _nextLongRestAt = nextLong.isAfter(at)
          ? nextLong
          : at.add(_settings.longRestInterval);
    } else {
      // Обед с приоритетом мог вытеснить длинный отдых, точка которого уже
      // прошла: сдвигаем её так, чтобы пропуск не создавал долга.
      final longAt = _nextLongRestAt;
      if (longAt != null && !longAt.isAfter(at)) {
        _nextLongRestAt = at.add(_settings.longRestInterval);
      }
    }
    _scheduleNextOffer();
    _workIntervalStartedAt = at;
    _postponesUsed = 0;
    _events.add(
      WorkDayEvent.restSkipped(
        at,
        kind,
        plannedDuration: _restDurationFor(kind),
      ),
    );
  }

  /// Отложить предложенный отдых: предложение вернётся через
  /// [postponeDuration], а время работы продолжит идти. Допускается не больше
  /// [maxPostponements] отложений подряд.
  WorkDayCommandResult postponeRest(DateTime now) =>
      _commanded(now, _postponeRest);

  WorkDayCommandResult _postponeRest(DateTime now) {
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
    _events.add(
      WorkDayEvent.restPostponed(
        now,
        kind,
        plannedDuration: _restDurationFor(kind),
      ),
    );
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
  WorkDayCommandResult pause(DateTime now) => _commanded(now, _pause);

  WorkDayCommandResult _pause(DateTime now) {
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
  WorkDayCommandResult resume(DateTime now) => _commanded(now, _resume);

  WorkDayCommandResult _resume(DateTime now) {
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
  WorkDayCommandResult finishWorkDay(DateTime now) =>
      _commanded(now, _finishWorkDay);

  WorkDayCommandResult _finishWorkDay(DateTime now) {
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

  /// Применить новые настройки с момента [now].
  ///
  /// Недопустимые значения отклоняются целиком: ни настройки, ни ритм не
  /// меняются. Принятые настройки сразу влияют на расчёт следующего отдыха и
  /// пересчитывают конец рабочего окна текущего дня, но не прерывают идущий
  /// отдых, не отменяют показанное предложение и не завершают рабочий день.
  WorkDayCommandResult updateSettings(DateTime now, RhythmSettings candidate) =>
      _commanded(now, (at) => _updateSettings(at, candidate));

  WorkDayCommandResult _updateSettings(DateTime now, RhythmSettings candidate) {
    final violation = settingsViolation(candidate);
    if (violation != null) {
      return WorkDayCommandRejected(violation);
    }

    final previous = _settings;
    _settings = candidate;
    _applySettingsToSchedule(now, previous);
    _events.add(WorkDayEvent.settingsChanged(now));
    return const WorkDayCommandAccepted();
  }

  /// Вернуть все настройки к значениям по умолчанию.
  WorkDayCommandResult resetSettings(DateTime now) =>
      _commanded(now, (at) => _updateSettings(at, RhythmSettings.defaults));

  /// Перенести действующие настройки на уже запланированный ритм.
  ///
  /// Счётчики пересчитываются от своей точки отсчёта: момент следующего отдыха
  /// уже равен «отсчёт + прежний интервал», поэтому достаточно заменить
  /// слагаемое. Идущий отдых и текущее предложение не трогаются — они
  /// доигрывают по прежним значениям, а новые интервалы применятся к расчёту
  /// следующего отдыха.
  void _applySettingsToSchedule(DateTime now, RhythmSettings previous) {
    if (_phase == WorkDayPhase.notStarted || _phase == WorkDayPhase.finished) {
      return;
    }

    _workWindowEndsAt = _window.endOn(_startedAt ?? now);

    if (_phase == WorkDayPhase.resting || _restOffered) {
      return;
    }

    _nextShortRestAt = _rebaseInterval(
      _nextShortRestAt,
      previous.shortRestInterval,
      _settings.shortRestInterval,
    );
    _nextLongRestAt = _rebaseInterval(
      _nextLongRestAt,
      previous.longRestInterval,
      _settings.longRestInterval,
    );
    if (!_mealTaken && _postponesUsed == 0) {
      // Отложенный обед сохраняет свой момент: отложение — часть текущего
      // предложения, а настройки меняют только базовое время обеда.
      _nextMealAt = _initialMealAt(now);
    }
    _scheduleNextOffer();
  }

  /// Сдвинуть момент, построенный как «отсчёт + [previous]», на [updated].
  DateTime? _rebaseInterval(
    DateTime? moment,
    Duration previous,
    Duration updated,
  ) => moment?.subtract(previous).add(updated);

  /// Текущее состояние на момент [now].
  WorkDaySnapshot snapshot(DateTime now) {
    now = _syncWithClock(now);

    final snapshot = WorkDaySnapshot(
      phase: _visiblePhase,
      availableCommands: _availableCommands(now),
      settings: _settings,
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

    _pushReminderPlan();
    return snapshot;
  }

  /// Выполнить команду и обновить напоминания. Время догоняется до [now] до
  /// команды, поэтому и отказ может изменить состояние — раскладка напоминаний
  /// обновляется при любом исходе команды.
  WorkDayCommandResult _commanded(
    DateTime now,
    WorkDayCommandResult Function(DateTime at) command,
  ) {
    final result = command(_syncWithClock(now));
    _pushReminderPlan();
    return result;
  }

  /// Дождаться, пока порт получит последнюю раскладку напоминаний. Нужно
  /// оболочке перед выходом и тестам, чтобы проверять раскладку без гонок.
  Future<void> get remindPlanApplied => _reminderWrites;

  /// Последняя раскладка, переданная в порт: повторная передача того же
  /// списка не делается, иначе тик экрана переписывал бы уведомления каждую
  /// секунду.
  List<RestReminder> _pushedReminders = const <RestReminder>[];

  /// Раскладки уходят в порт строго по очереди: поздняя не обгоняет раннюю.
  Future<void> _reminderWrites = Future<void>.value();

  void _pushReminderPlan() {
    final port = _reminders;
    if (port == null) {
      return;
    }
    final plan = _reminderPlan();
    if (_sameReminders(plan, _pushedReminders)) {
      return;
    }
    _reminderWrites = _reminderWrites
        .then((_) async {
          await port.cancelAll();
          for (final reminder in plan) {
            await port.schedule(reminder);
          }
          // Раскладка считается переданной только после успешной записи:
          // иначе сбой платформы навсегда скрыл бы повторную попытку.
          _pushedReminders = plan;
          lastReminderFailure = null;
        })
        .catchError((Object error) {
          // Сбой платформенных напоминаний не должен ломать ритм: следующая
          // смена состояния повторит раскладку.
          lastReminderFailure = error;
        });
  }

  /// Последняя ошибка передачи раскладки в порт; null — раскладка применилась.
  /// Нужна тестам и диагностике: сам ритм от напоминаний не зависит.
  Object? lastReminderFailure;

  bool _sameReminders(List<RestReminder> left, List<RestReminder> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  /// Напоминания на ближайшие точки отдыха: не больше [reminderLimit] штук и
  /// только внутри рабочего окна. Пустой список означает «отменить всё» —
  /// так ядро отвечает на паузу, конец рабочего дня, выключенные напоминания
  /// и уже показанное или идущее предложение.
  ///
  /// Точки считаются вперёд по тем же правилам, что и настоящий ритм: каждый
  /// отдых сдвигает счётчик своего вида на свою длительность плюс интервал,
  /// короткий отдых переносит и счётчик длинного, обед сбрасывает оба.
  List<RestReminder> _reminderPlan() {
    if (!_settings.notificationsEnabled) {
      return const <RestReminder>[];
    }
    final endsAt = _workWindowEndsAt;
    final counters = _reminderCounters;
    if (endsAt == null || counters == null) {
      return const <RestReminder>[];
    }

    var shortAt = counters.shortAt;
    var longAt = counters.longAt;
    var mealAt = counters.mealAt;
    final reminders = <RestReminder>[];
    while (reminders.length < reminderLimit) {
      final candidates =
          <(DateTime, RestKind)>[
            if (shortAt != null) (shortAt, RestKind.short),
            if (longAt != null) (longAt, RestKind.long),
            if (mealAt != null) (mealAt, RestKind.meal),
          ].where((candidate) {
            final at = candidate.$1;
            return at.isAfter(counters.from) && at.isBefore(endsAt);
          }).toList();
      if (candidates.isEmpty) {
        break;
      }
      candidates.sort((a, b) {
        final byMoment = a.$1.compareTo(b.$1);
        return byMoment != 0
            ? byMoment
            : _offerPriority(a.$2).compareTo(_offerPriority(b.$2));
      });

      final (at, kind) = candidates.first;
      final duration = _restDurationFor(kind);
      reminders.add(
        RestReminder(
          at: at,
          kind: kind,
          duration: duration,
          playSound: _settings.soundEnabled,
        ),
      );
      switch (kind) {
        case RestKind.meal:
          shortAt = at.add(duration).add(_settings.shortRestInterval);
          longAt = at.add(duration).add(_settings.longRestInterval);
          mealAt = null;
        case RestKind.long:
          shortAt = at.add(duration).add(_settings.shortRestInterval);
          longAt = at.add(duration).add(_settings.longRestInterval);
        case RestKind.short:
          shortAt = at.add(duration).add(_settings.shortRestInterval);
          longAt = longAt?.add(duration);
      }
    }
    return List<RestReminder>.unmodifiable(reminders);
  }

  /// Счётчики, от которых начинается проекция напоминаний, и момент, раньше
  /// которого точек отдыха уже нет. Null — напоминать сейчас не о чем: день не
  /// идёт, стоит на паузе, завершён или отдых уже предлагается.
  ({DateTime from, DateTime? shortAt, DateTime? longAt, DateTime? mealAt})?
  get _reminderCounters {
    switch (_visiblePhase) {
      case WorkDayPhase.notStarted:
      case WorkDayPhase.finished:
      case WorkDayPhase.paused:
      case WorkDayPhase.restOffered:
        return null;
      case WorkDayPhase.running:
        final from = _lastObservedAt;
        if (from == null) {
          return null;
        }
        // Отложенное предложение вернётся в свой момент, а счётчик его вида
        // ещё показывает старую точку — берём момент возврата.
        final postponedAt = _postponesUsed > 0 ? _nextRestAt : null;
        return (
          from: from,
          shortAt: _offerKind == RestKind.short && postponedAt != null
              ? postponedAt
              : _nextShortRestAt,
          longAt: _offerKind == RestKind.long && postponedAt != null
              ? postponedAt
              : _nextLongRestAt,
          mealAt: _offerKind == RestKind.meal && postponedAt != null
              ? postponedAt
              : _mealCandidateAt,
        );
      case WorkDayPhase.resting:
        final endsAt = _restEndsAt;
        final kind = _currentRestKind;
        final windowEndsAt = _workWindowEndsAt;
        if (endsAt == null || kind == null || windowEndsAt == null) {
          return null;
        }
        if (!endsAt.isBefore(windowEndsAt)) {
          return null;
        }
        // Отдых доигрывает до планового конца: от него и продолжается ритм.
        final planned = _restPlannedDuration ?? Duration.zero;
        return switch (kind) {
          RestKind.meal => (
            from: endsAt,
            shortAt: endsAt.add(_settings.shortRestInterval),
            longAt: endsAt.add(_settings.longRestInterval),
            mealAt: null,
          ),
          RestKind.long => (
            from: endsAt,
            shortAt: endsAt.add(_settings.shortRestInterval),
            longAt: endsAt.add(_settings.longRestInterval),
            mealAt: _mealCandidateAt,
          ),
          RestKind.short => (
            from: endsAt,
            shortAt: endsAt.add(_settings.shortRestInterval),
            longAt: _nextLongRestAt?.add(planned),
            mealAt: _mealCandidateAt,
          ),
        };
    }
  }

  /// Фаза, которую видит оболочка: предложенный отдых — это идущий рабочий
  /// день с активным предложением.
  WorkDayPhase get _visiblePhase =>
      _phase == WorkDayPhase.running && _restOffered
      ? WorkDayPhase.restOffered
      : _phase;

  RestKind? get _restKind =>
      _phase == WorkDayPhase.resting || _restOffered ? _currentRestKind : null;

  /// Плановая длительность предложенного или идущего отдыха. У идущего отдыха
  /// она зафиксирована при начале, поэтому смена настроек его не переписывает.
  Duration? get _restDuration {
    final kind = _restKind;
    if (kind == null) {
      return null;
    }
    if (_phase == WorkDayPhase.resting) {
      return _restPlannedDuration ?? _restDurationFor(kind);
    }
    return _restDurationFor(kind);
  }

  /// Довести состояние до момента [now] и вернуть момент, который движок
  /// считает текущим: не раньше последнего увиденного.
  DateTime _syncWithClock(DateTime now) {
    final observed = _lastObservedAt;
    final effective = observed != null && now.isBefore(observed)
        ? observed
        : now;

    final closedSince = _closedSince;
    _closedSince = null;
    if (closedSince != null) {
      _catchUpWhileClosed(closedSince, effective);
    }

    _completeRestIfDue(effective);
    _closeAtWorkWindowEndIfDue(effective);
    _offerRestIfDue(effective);
    _lastObservedAt = effective;
    return effective;
  }

  /// Разобрать время, прошедшее при закрытом приложении, по порядку: идущий
  /// отдых доигрывает до своего конца, каждая прошедшая точка отдыха становится
  /// пропуском, конец рабочего окна закрывает день.
  ///
  /// Пропуски не создают долга: после разбора пользователю достаётся ровно один
  /// текущий отдых, а не очередь из пропущенных.
  void _catchUpWhileClosed(DateTime closedSince, DateTime now) {
    if (!now.isAfter(closedSince)) {
      return;
    }

    var missedRests = false;
    RestKind? repeatingKind;
    while (true) {
      final restEndsAt = _restEndsAt;
      if (_phase == WorkDayPhase.resting &&
          restEndsAt != null &&
          !restEndsAt.isAfter(now)) {
        _endRest(restEndsAt, RestFinishReason.natural);
        continue;
      }

      final offerAt = _phase == WorkDayPhase.running && !_restOffered
          ? _nextRestAtWithinWindow
          : null;
      final offerKind = _offerKind;
      if (offerAt != null && offerKind != null && !offerAt.isAfter(now)) {
        _skipAt(offerAt, offerKind);
        missedRests = true;
        if (offerKind != RestKind.meal) {
          repeatingKind = offerKind;
        }
        continue;
      }

      final endsAt = _workWindowEndsAt;
      final windowDue =
          endsAt != null &&
          !endsAt.isAfter(now) &&
          (_phase == WorkDayPhase.running || _phase == WorkDayPhase.paused);
      if (windowDue) {
        _closeAtWorkWindowEndIfDue(now);
        continue;
      }

      break;
    }

    if (missedRests) {
      // Пропущенный обед не переносится: если за закрытие пропущено только его,
      // текущим отдыхом становится короткий.
      _offerAfterClosedInterval(now, repeatingKind ?? RestKind.short);
    }
  }

  /// Показать единственный текущий отдых после пропусков, накопившихся за время
  /// закрытия. Очереди нет: предложение одно, и оно сразу на экране.
  void _offerAfterClosedInterval(DateTime now, RestKind kind) {
    if (_phase != WorkDayPhase.running || _restOffered) {
      return;
    }
    final endsAt = _workWindowEndsAt;
    if (endsAt == null || !now.isBefore(endsAt)) {
      return;
    }
    _restOffered = true;
    _currentRestKind = kind;
    _events.add(
      WorkDayEvent.restOffered(
        now,
        kind,
        plannedDuration: _restDurationFor(kind),
      ),
    );
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
        _nextShortRestAt = endedAt.add(_settings.shortRestInterval);
        _nextLongRestAt = endedAt.add(_settings.longRestInterval);
      case RestKind.long:
        _nextLongRestAt = endedAt.add(_settings.longRestInterval);
        _nextShortRestAt = endedAt.add(_settings.shortRestInterval);
      case RestKind.short:
        // Отдых — не рабочее время: счётчик длинного отдыха сдвигается на него.
        _nextLongRestAt = _nextLongRestAt?.add(actualDuration);
        _nextShortRestAt = endedAt.add(_settings.shortRestInterval);
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
      plannedDuration: _restPlannedDuration ?? _restDurationFor(kind),
      actualDuration: endedAt.difference(_restStartedAt ?? endedAt),
    );
  }

  void _clearRest() {
    _restEndsAt = null;
    _restStartedAt = null;
    _restPlannedDuration = null;
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
    _events.add(
      WorkDayEvent.restOffered(
        next,
        kind,
        plannedDuration: _restDurationFor(kind),
      ),
    );
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
      _settings.mealStart.hour,
      _settings.mealStart.minute,
    );
    if (scheduled.isBefore(now) || !scheduled.isBefore(_window.endOn(now))) {
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
        _window.contains(now) ? const [WorkDayCommand.start] : const [],
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
        _window.contains(now) ? const [WorkDayCommand.start] : const [],
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
    RestKind.short => _settings.shortRestDuration,
    RestKind.long => _settings.longRestDuration,
    RestKind.meal => _settings.mealDuration,
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
      WorkDayPhase.notStarted || WorkDayPhase.finished => _window.endOn(now),
    };
    final remaining = endsAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
