/// Что произошло с рабочим днём. Журнал нужен для будущей статистики.
enum WorkDayEventType {
  workDayStarted,
  workDayPaused,
  workDayResumed,
  workDayFinished,
}

/// Причина завершения рабочего дня.
enum WorkDayFinishReason { manual, workWindowEnded }

final class WorkDayEvent {
  const WorkDayEvent.started(this.at)
    : type = WorkDayEventType.workDayStarted,
      finishReason = null;

  const WorkDayEvent.paused(this.at)
    : type = WorkDayEventType.workDayPaused,
      finishReason = null;

  const WorkDayEvent.resumed(this.at)
    : type = WorkDayEventType.workDayResumed,
      finishReason = null;

  const WorkDayEvent.finished(this.at, WorkDayFinishReason this.finishReason)
    : type = WorkDayEventType.workDayFinished;

  final WorkDayEventType type;
  final DateTime at;
  final WorkDayFinishReason? finishReason;

  @override
  bool operator ==(Object other) =>
      other is WorkDayEvent &&
      other.type == type &&
      other.at == at &&
      other.finishReason == finishReason;

  @override
  int get hashCode => Object.hash(type, at, finishReason);

  @override
  String toString() =>
      'WorkDayEvent($type at $at'
      '${finishReason == null ? '' : ', $finishReason'})';
}
