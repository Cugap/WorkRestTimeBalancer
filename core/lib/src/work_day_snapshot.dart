import 'exercise.dart';
import 'rest_kind.dart';
import 'rhythm_settings.dart';
import 'work_day_command.dart';
import 'work_day_event.dart';

/// Снимок рабочего дня: всё, что экран показывает, не вычисляя ничего сам.
final class WorkDaySnapshot {
  WorkDaySnapshot({
    required this.phase,
    required List<WorkDayCommand> availableCommands,
    required this.settings,
    required this.worked,
    required this.remainingInWorkWindow,
    required this.remainingPostponements,
    required List<WorkDayEvent> events,
    List<Exercise> exercises = const <Exercise>[],
    this.startedAt,
    this.finishedAt,
    this.workWindowEndsAt,
    this.workIntervalStartedAt,
    this.restKind,
    this.restDuration,
    this.nextRestAt,
    this.untilNextRest,
    this.remainingRest,
    this.lastRestFinished,
  }) : availableCommands = List.unmodifiable(availableCommands),
       events = List.unmodifiable(events),
       exercises = List.unmodifiable(exercises);

  final WorkDayPhase phase;

  /// Действия, которые ядро сейчас примет; экран не решает это сам.
  final List<WorkDayCommand> availableCommands;

  /// Действующие настройки ритма и рабочего окна. Экран показывает их как есть
  /// и отправляет изменённые обратно в движок.
  final RhythmSettings settings;

  /// Отработанное время внутри рабочего дня без пауз.
  final Duration worked;

  /// Сколько осталось до конца рабочего окна; никогда не отрицательно.
  final Duration remainingInWorkWindow;

  /// Момент начала текущего рабочего дня.
  final DateTime? startedAt;

  /// Момент завершения рабочего дня.
  final DateTime? finishedAt;

  /// Конец рабочего окна текущего рабочего дня.
  final DateTime? workWindowEndsAt;

  /// Начало текущего интервала работы: момент старта дня, конца отдыха или
  /// пропуска. На паузе не меняется, во время отдыха отсутствует.
  final DateTime? workIntervalStartedAt;

  /// Вид идущего или предложенного отдыха; null, если отдыха нет.
  final RestKind? restKind;

  /// Плановая длительность идущего или предложенного отдыха; null, если
  /// отдыха нет. Экран показывает её в предложении, не вычисляя сам.
  final Duration? restDuration;

  /// Момент следующего отдыха по часам; null, если следующий отдых ещё не
  /// запланирован (отдых предложен или идёт) или не наступит в этом рабочем
  /// дне. На паузе момент не сдвигается — сдвиг происходит при возобновлении.
  final DateTime? nextRestAt;

  /// Сколько осталось до следующего отдыха по счётчику ритма; на паузе
  /// замирает, у предложенного отдыха равен нулю. Null, если отдых не
  /// запланирован или уже идёт. Никогда не отрицательно.
  final Duration? untilNextRest;

  /// Сколько осталось от идущего отдыха; null, если отдых не идёт.
  /// Никогда не отрицательно.
  final Duration? remainingRest;

  /// Сколько отложений ещё доступно для текущего предложения отдыха. Лимит
  /// один на цепочку предложений: сбрасывается, когда отдых начался,
  /// пропущен или завершён. Вне предложения равен полному лимиту.
  final int remainingPostponements;

  /// Упражнения текущего отдыха: короткий отдых показывает ровно одно,
  /// длинный — два из разных категорий, обед — три, по одному из каждой
  /// категории. Вне отдыха список пуст.
  final List<Exercise> exercises;

  /// Событие о завершении последнего отдыха текущего рабочего дня с причиной
  /// и плановой/фактической длительностью; null, пока отдых не завершался.
  final WorkDayEvent? lastRestFinished;

  /// Журнал событий рабочего дня.
  final List<WorkDayEvent> events;
}
