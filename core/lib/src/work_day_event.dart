import 'rest_kind.dart';

/// Что произошло с рабочим днём. Журнал нужен для будущей статистики.
enum WorkDayEventType {
  workDayStarted,
  workDayPaused,
  workDayResumed,
  workDayFinished,
  restOffered,
  restStarted,
  restSkipped,
  restPostponed,
  restFinished,
}

/// Причина завершения рабочего дня.
enum WorkDayFinishReason { manual, workWindowEnded }

/// Причина завершения отдыха.
enum RestFinishReason {
  /// Отдых доиграл до конца.
  natural,

  /// Отдых завершён досрочно.
  early,

  /// Отдых прерван завершением рабочего дня.
  workDayEnded,
}

final class WorkDayEvent {
  const WorkDayEvent.started(this.at)
    : type = WorkDayEventType.workDayStarted,
      finishReason = null,
      restKind = null,
      restFinishReason = null,
      plannedDuration = null,
      actualDuration = null;

  const WorkDayEvent.paused(this.at)
    : type = WorkDayEventType.workDayPaused,
      finishReason = null,
      restKind = null,
      restFinishReason = null,
      plannedDuration = null,
      actualDuration = null;

  const WorkDayEvent.resumed(this.at)
    : type = WorkDayEventType.workDayResumed,
      finishReason = null,
      restKind = null,
      restFinishReason = null,
      plannedDuration = null,
      actualDuration = null;

  const WorkDayEvent.finished(this.at, WorkDayFinishReason this.finishReason)
    : type = WorkDayEventType.workDayFinished,
      restKind = null,
      restFinishReason = null,
      plannedDuration = null,
      actualDuration = null;

  const WorkDayEvent.restOffered(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restOffered,
      finishReason = null,
      restFinishReason = null,
      plannedDuration = null,
      actualDuration = null;

  const WorkDayEvent.restStarted(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restStarted,
      finishReason = null,
      restFinishReason = null,
      plannedDuration = null,
      actualDuration = null;

  const WorkDayEvent.restSkipped(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restSkipped,
      finishReason = null,
      restFinishReason = null,
      plannedDuration = null,
      actualDuration = null;

  const WorkDayEvent.restPostponed(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restPostponed,
      finishReason = null,
      restFinishReason = null,
      plannedDuration = null,
      actualDuration = null;

  const WorkDayEvent.restFinished(
    this.at,
    RestKind this.restKind, {
    this.restFinishReason = RestFinishReason.natural,
    this.plannedDuration,
    this.actualDuration,
  }) : type = WorkDayEventType.restFinished,
       finishReason = null;

  final WorkDayEventType type;
  final DateTime at;
  final WorkDayFinishReason? finishReason;

  /// Вид отдыха для событий отдыха; null для событий рабочего дня.
  final RestKind? restKind;

  /// Причина завершения отдыха; null для событий, которые отдых не завершают.
  final RestFinishReason? restFinishReason;

  /// Запланированная длительность отдыха; null для событий без длительности.
  final Duration? plannedDuration;

  /// Фактическая длительность отдыха; null для событий без длительности.
  final Duration? actualDuration;

  @override
  bool operator ==(Object other) =>
      other is WorkDayEvent &&
      other.type == type &&
      other.at == at &&
      other.finishReason == finishReason &&
      other.restKind == restKind &&
      other.restFinishReason == restFinishReason &&
      other.plannedDuration == plannedDuration &&
      other.actualDuration == actualDuration;

  @override
  int get hashCode => Object.hash(
    type,
    at,
    finishReason,
    restKind,
    restFinishReason,
    plannedDuration,
    actualDuration,
  );

  @override
  String toString() =>
      'WorkDayEvent($type at $at'
      '${finishReason == null ? '' : ', $finishReason'}'
      '${restKind == null ? '' : ', $restKind'}'
      '${restFinishReason == null ? '' : ', $restFinishReason'}'
      '${plannedDuration == null ? '' : ', plan $plannedDuration'}'
      '${actualDuration == null ? '' : ', actual $actualDuration'})';
}
