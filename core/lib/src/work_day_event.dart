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

final class WorkDayEvent {
  const WorkDayEvent.started(this.at)
    : type = WorkDayEventType.workDayStarted,
      finishReason = null,
      restKind = null;

  const WorkDayEvent.paused(this.at)
    : type = WorkDayEventType.workDayPaused,
      finishReason = null,
      restKind = null;

  const WorkDayEvent.resumed(this.at)
    : type = WorkDayEventType.workDayResumed,
      finishReason = null,
      restKind = null;

  const WorkDayEvent.finished(this.at, WorkDayFinishReason this.finishReason)
    : type = WorkDayEventType.workDayFinished,
      restKind = null;

  const WorkDayEvent.restOffered(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restOffered,
      finishReason = null;

  const WorkDayEvent.restStarted(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restStarted,
      finishReason = null;

  const WorkDayEvent.restSkipped(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restSkipped,
      finishReason = null;

  const WorkDayEvent.restPostponed(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restPostponed,
      finishReason = null;

  const WorkDayEvent.restFinished(this.at, RestKind this.restKind)
    : type = WorkDayEventType.restFinished,
      finishReason = null;

  final WorkDayEventType type;
  final DateTime at;
  final WorkDayFinishReason? finishReason;

  /// Вид отдыха для событий отдыха; null для событий рабочего дня.
  final RestKind? restKind;

  @override
  bool operator ==(Object other) =>
      other is WorkDayEvent &&
      other.type == type &&
      other.at == at &&
      other.finishReason == finishReason &&
      other.restKind == restKind;

  @override
  int get hashCode => Object.hash(type, at, finishReason, restKind);

  @override
  String toString() =>
      'WorkDayEvent($type at $at'
      '${finishReason == null ? '' : ', $finishReason'}'
      '${restKind == null ? '' : ', $restKind'})';
}
